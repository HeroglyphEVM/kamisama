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
    uint32 public constant MAX_SUPPLY_PER_NATION = 1000;
    uint32 public constant TOTAL_NATIONS = 7;
    uint32 public constant RESERVED_IDS_PER_NATION = 15;
    uint256 public COST;

    address public treasury;
    uint32 public lastedUnlockedNation;
    uint32 public freeMintPassLeft;

    mapping(uint32 nation => uint32 lastMintedId) public lastMintedIdByNation;
    mapping(uint32 nation => string) public nationCollectionURIs;
    mapping(uint32 nation => uint32) public reservedNFTLeft;
    mapping(address validator => uint32) public freeMintPassBalance;

    bool public isImmutable;

    constructor(uint256 _cost, address _owner, address _treasury, address _lzEndpoint)
        OAppCore(_lzEndpoint, _owner)
        Ownable(_owner)
    {
        require(_treasury != address(0), InvalidTreasury());
        COST = _cost;

        treasury = _treasury;
        freeMintPassLeft = RESERVED_IDS_PER_NATION * TOTAL_NATIONS;
        reservedNFTLeft[0] = RESERVED_IDS_PER_NATION;
    }

    function _lzReceive(
        Origin calldata,
        bytes32 _guid,
        bytes calldata _message,
        address, /*_executor*/ // @dev unused in the default implementation.
        bytes calldata /*_extraData*/ // @dev unused in the default implementation.
    ) internal virtual override {
        (uint32 _blockNumber, address _of) = abi.decode(_message, (uint32, address));
        uint32 freeMintPassCached = freeMintPassLeft;
        if (freeMintPassCached == 0) revert NoMoreFreeMintPass();

        freeMintPassCached--;
        freeMintPassBalance[_of]++;

        freeMintPassLeft = freeMintPassCached;

        emit FreeMintPassGiven(_guid, _blockNumber, _of, freeMintPassCached);
    }

    function mint(uint32[] calldata _nations, uint32[] calldata _quantities, bool _useFreeMintPass)
        external
        payable
        override
    {
        uint256 totalNations = _nations.length;
        if (_useFreeMintPass && msg.value > 0) {
            revert NativeDetectedWhenFreeMintPassIsUsed();
        }

        require(totalNations == _quantities.length, MismathArrayLength());

        uint256 totalCost = 0;
        for (uint256 i = 0; i < totalNations; ++i) {
            totalCost += COST * _quantities[i];
            _executeMint(_nations[i], msg.sender, _quantities[i], _useFreeMintPass);
        }

        if (_useFreeMintPass) return;

        require(msg.value == totalCost, NotEnoughNative());

        (bool successNativeCall,) = treasury.call{ value: totalCost }("");
        require(successNativeCall, FailedToSendNative());
    }

    function _executeMint(uint32 _nation, address _to, uint32 _quantity, bool _useFreeMintPass) internal {
        require(_nation <= lastedUnlockedNation, NationNotFound());
        require(_quantity > 0, InvalidQuantity());
        uint32 lastIdeMintedCached = lastMintedIdByNation[_nation];

        require(lastIdeMintedCached + _quantity <= MAX_SUPPLY_PER_NATION, MaxSupplyReached());
        lastMintedIdByNation[_nation] = lastIdeMintedCached + _quantity;

        if (_useFreeMintPass) {
            _spendFreePass(_nation, _quantity);
        }

        uint256 nftId = 0;
        uint32 reservedLeft = reservedNFTLeft[_nation];

        for (uint32 i = 0; i < _quantity; ++i) {
            nftId = ++lastIdeMintedCached + (MAX_SUPPLY_PER_NATION * _nation);

            if (lastIdeMintedCached > (MAX_SUPPLY_PER_NATION - reservedLeft)) {
                require(_useFreeMintPass, ValidatorReservedID());
            }

            _safeMint(_to, nftId);
            emit KamisamaMinted(_to, _nation, nftId);
        }
    }

    function _spendFreePass(uint32 _nation, uint32 _quantity) internal {
        uint32 totalReservedLeft = reservedNFTLeft[_nation];
        uint32 validatorFreePass = freeMintPassBalance[msg.sender];

        require(totalReservedLeft >= _quantity, MaxFreePassUsedOnNation());
        require(validatorFreePass >= _quantity, NoFreePass());

        validatorFreePass -= _quantity;
        totalReservedLeft -= _quantity;

        reservedNFTLeft[_nation] = totalReservedLeft;
        freeMintPassBalance[msg.sender] = validatorFreePass;
    }

    function unlockNewNation() external onlyOwner {
        uint32 cached = lastedUnlockedNation + 1;
        require(cached < TOTAL_NATIONS, MaxNationReached());

        reservedNFTLeft[cached] = RESERVED_IDS_PER_NATION;
        lastedUnlockedNation = cached;

        emit NewNationUnlocked(cached);
    }

    function reveals(uint32 _nation, string calldata _ipfs) external onlyOwner {
        string memory currentIPFS = nationCollectionURIs[_nation];

        require(!isImmutable || bytes(currentIPFS).length == 0, Immutable());

        nationCollectionURIs[_nation] = _ipfs;
        emit Revealed(_nation, _ipfs);
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

    function setCost(uint256 _cost) external onlyOwner {
        COST = _cost;
        emit CostSet(_cost);
    }

    function name() public pure override returns (string memory) {
        return "Kamisama";
    }

    function symbol() public pure override returns (string memory) {
        return "KAMI";
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_exists(id), TokenDoesNotExist());

        string memory baseURI = nationCollectionURIs[getNation(id)];
        return bytes(baseURI).length > 0 ? string.concat(baseURI, LibString.toString(id)) : "";
    }

    function getNation(uint256 id) public pure returns (uint32) {
        return uint32((id - 1) / MAX_SUPPLY_PER_NATION);
    }
}
