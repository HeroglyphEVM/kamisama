// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC721 } from "solady/tokens/ERC721.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IKamisama } from "./interfaces/IKamisama.sol";
import { IKamisamaFactory } from "./interfaces/IKamisamaFactory.sol";

import { VRFV2PlusClient } from
  "chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { VRFV2PlusWrapperConsumerBase } from "./vendor/VRFV2PlusWrapperConsumerBase.sol";
import { Initializable } from "solady/utils/Initializable.sol";

/**
 * @title Kamisama
 * @author 0xAtum
 * @notice Kamisama is a collection of NFTs that randomizes the minting for the user.
 */
contract Kamisama is IKamisama, ERC721, VRFV2PlusWrapperConsumerBase, Initializable {
  uint32 public constant GAS_LIMIT = 200_000;
  uint16 public constant CONFIRMATIONS = 20;
  uint32 public constant WORDS = 1;

  mapping(uint256 => MintRequest) public mintRequests;
  mapping(uint256 nftId => uint256) public ipfsFileIds;

  string private internal_name;
  string private internal_symbol;
  string public collectionURI;
  IKamisamaFactory public FACTORY;

  uint256 public COST;
  uint256 public MAX_SUPPLY;
  uint256 public nextIdToMint;

  function initialize(
    uint256 _cost,
    uint256 _maxSupply,
    address _vrfV2PlusWrapper,
    string calldata _name,
    string calldata _symbol,
    string calldata _collectionURI
  ) external override initializer {
    require(bytes(_name).length > 0, Misconfiguration(ERROR_CODE.NAME_EMPTY));
    require(bytes(_symbol).length > 0, Misconfiguration(ERROR_CODE.SYMBOL_EMPTY));
    require(
      bytes(_collectionURI).length > 0, Misconfiguration(ERROR_CODE.COLLECTION_URI_EMPTY)
    );
    require(_maxSupply > 0, Misconfiguration(ERROR_CODE.MAX_SUPPLY_ZERO));

    COST = _cost;
    MAX_SUPPLY = _maxSupply;
    _initVRFWrapper(_vrfV2PlusWrapper);
    internal_name = _name;
    internal_symbol = _symbol;
    collectionURI = _collectionURI;

    FACTORY = IKamisamaFactory(msg.sender);
    nextIdToMint = 1;
  }

  function mint() external payable {
    require(nextIdToMint <= MAX_SUPPLY, MaxSupplyReached());
    uint256 CACHED_COST = COST;

    (uint256 requestId, uint256 paid) =
      requestRandomnessPayInNative(GAS_LIMIT, CONFIRMATIONS, WORDS, "");

    mintRequests[requestId] =
      MintRequest({ to: msg.sender, nftId: nextIdToMint, result: 0 });

    paid += CACHED_COST;
    nextIdToMint++;

    require(msg.value >= paid, NotEnoughNative());

    bool successNativeCall;

    (successNativeCall,) = FACTORY.treasury().call{ value: CACHED_COST }("");
    require(successNativeCall, FailedToSendNative());

    if (msg.value > paid) {
      (successNativeCall,) = msg.sender.call{ value: msg.value - paid }("");
      require(successNativeCall, FailedToSendNative());
    }

    emit MintRequestCreated(requestId, mintRequests[requestId]);
  }

  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords)
    internal
    override
  {
    MintRequest storage request = mintRequests[_requestId];
    require(request.result == 0, MintRequestAlreadyFulfilled());

    address to = request.to;
    uint256 seed = _randomWords[0];
    uint256 nftId = request.nftId;
    request.nftId = nftId;
    request.result = seed;

    ipfsFileIds[nftId] = (seed % MAX_SUPPLY) + 1;

    // We do not want to revert, so we pre-verify if it can be minted to the receiver
    if (_canSafeMint(address(0), to, nftId, "")) {
      _mint(to, nftId);
    }

    emit MintRequestUpdated(_requestId, request);
  }

  function changeRequestReceiver(uint256 _requestId, address _newReceiver) external {
    MintRequest storage request = mintRequests[_requestId];
    require(request.to == msg.sender, OnlyRequestReceiver());
    require(_newReceiver != address(0), InvalidReceiver());

    request.to = _newReceiver;

    emit MintRequestUpdated(_requestId, request);
  }

  function retryMinting(uint256 _requestId) external {
    MintRequest memory request = mintRequests[_requestId];
    uint256 nftId = request.nftId;

    require(nftId > 0, MintRequestNotFulfilled());
    require(!_exists(nftId), TokenAlreadyMinted());

    _safeMint(request.to, nftId);
  }

  function _canSafeMint(address from, address to, uint256 id, bytes memory data)
    private
    returns (bool success_)
  {
    bool isContract;

    assembly {
      isContract := extcodesize(to) // Can handle dirty upper bits.
    }

    if (!isContract) return true;

    success_ = true;
    /// @solidity memory-safe-assembly
    assembly {
      // Prepare the calldata.
      let m := mload(0x40)
      let onERC721ReceivedSelector := 0x150b7a02
      mstore(m, onERC721ReceivedSelector)
      mstore(add(m, 0x20), caller()) // The `operator`, which is always `msg.sender`.
      mstore(add(m, 0x40), shr(96, shl(96, from)))
      mstore(add(m, 0x60), id)
      mstore(add(m, 0x80), 0x80)
      let n := mload(data)
      mstore(add(m, 0xa0), n)
      if n { pop(staticcall(gas(), 4, add(data, 0x20), n, add(m, 0xc0), n)) }
      // Revert if the call reverts.
      if iszero(call(gas(), to, 0, add(m, 0x1c), add(n, 0xa4), m, 0x20)) {
        if returndatasize() { success_ := false }
      }
      // Load the returndata and compare it.
      if iszero(eq(mload(m), shl(224, onERC721ReceivedSelector))) { success_ := false }
    }

    return success_;
  }

  function getVRFNativeCost() public view returns (uint256) {
    return i_vrfV2PlusWrapper.calculateRequestPriceNative(GAS_LIMIT, WORDS);
  }

  function name() public view override returns (string memory) {
    return internal_name;
  }

  function symbol() public view override returns (string memory) {
    return internal_symbol;
  }

  function tokenURI(uint256 id) public view override returns (string memory) {
    require(_exists(id), TokenDoesNotExist());

    string memory baseURI = collectionURI;
    return bytes(baseURI).length > 0
      ? string.concat(baseURI, LibString.toString(ipfsFileIds[id]))
      : "";
  }
}
