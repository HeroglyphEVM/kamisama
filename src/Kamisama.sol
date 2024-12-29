// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC721 } from "solady/tokens/ERC721.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IKamisama } from "./interfaces/IKamisama.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OAppReceiver } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppReceiver.sol";
import { OAppCore, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

/**
 * @title Kamisama
 * @author Heroglyphs' team
 * @notice Kamisama is a collection of NFTs that randomizes the nft metadata of the minted nfts.
 * @custom:export abi
 */
contract Kamisama is IKamisama, ERC721, OAppReceiver {
    uint256 public immutable COST;
    uint256 public constant MAX_SUPPLY = 7000;

    string public collectionURI;

    address public treasury;
    uint32 public lastMintedID;
    uint32 public unlockedIds;

    bool public isImmutable;

    constructor(uint256 _cost, address _owner, address _treasury, address _lzEndpoint)
        OAppCore(_lzEndpoint, _owner)
        Ownable(_owner)
    {
        require(_treasury != address(0), InvalidTreasury());
        COST = _cost;
        unlockedIds = 1000;

        treasury = _treasury;
    }

    function _lzReceive(
        Origin calldata,
        bytes32 _guid,
        bytes calldata _message,
        address, /*_executor*/ // @dev unused in the default implementation.
        bytes calldata /*_extraData*/ // @dev unused in the default implementation.
    ) internal virtual override {
        (uint32 _blockNumber, address _of) = abi.decode(_message, (uint32, address));
        uint256 nftId = _executeMint(_of);

        emit KamisamaValidatorMinted(nftId, _of, _guid, _blockNumber);
    }

    function mint() external payable override {
        require(msg.value == COST, NotEnoughNative());
        _executeMint(msg.sender);
    }

    function _executeMint(address _to) internal returns (uint256 nftId_) {
        require(lastMintedID < unlockedIds, MaxSupplyReached());
        nftId_ = ++lastMintedID;

        _safeMint(_to, nftId_);
        emit KamisamaMinted(_to, nftId_, msg.value);

        if (msg.value == 0) return nftId_;

        (bool successNativeCall,) = treasury.call{ value: COST }("");
        require(successNativeCall, FailedToSendNative());

        return nftId_;
    }

    function injectMore(uint32 _amount) external onlyOwner {
        uint32 cachedUnlockedIds = unlockedIds + _amount;
        require(cachedUnlockedIds <= MAX_SUPPLY, MaxSupplyReached());

        unlockedIds = cachedUnlockedIds;
        emit MoreUnlocked(_amount);
    }

    function reveals(string calldata _ipfs) external onlyOwner {
        require(!isImmutable, Immutable());

        collectionURI = _ipfs;
        emit Revealed(_ipfs);
    }

    function setImmutable() external onlyOwner {
        isImmutable = true;
        emit ImmutableActivated();
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), InvalidTreasury());

        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function name() public pure override returns (string memory) {
        return "Kamisama";
    }

    function symbol() public pure override returns (string memory) {
        return "KAMI";
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_exists(id), TokenDoesNotExist());

        string memory baseURI = collectionURI;
        return bytes(baseURI).length > 0 ? string.concat(baseURI, LibString.toString(id)) : "";
    }
}
