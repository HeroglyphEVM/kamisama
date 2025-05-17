// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IKamisama {
    error MaxSupplyReached();
    error MaxFreePassUsedOnNation();
    error NoFreePass();
    error NotEnoughNative();
    error NativeDetectedWhenFreeMintPassIsUsed();
    error FailedToSendNative();
    error Immutable();
    error InvalidTreasury();
    error NoMoreFreeMintPass();
    error NationNotFound();
    error MaxNationReached();
    error MismathArrayLength();
    error ValidatorReservedID();
    error InvalidQuantity();

    event FreeMintPassGiven(
        bytes32 indexed guid, uint32 indexed blockNumber, address indexed to, uint32 totalMintPassLeft
    );
    event Revealed(uint32 indexed nation, string collectionURI);
    event KamisamaMinted(address indexed to, uint32 indexed nation, uint256 indexed nftId);
    event ImmutableActivated();
    event TreasurySet(address indexed treasury);
    event MoreUnlocked(uint32 amount);
    event NewNationUnlocked(uint32 indexed nation);
    event CostSet(uint256 cost);

    /**
     * @notice Mint Kamisama NFTs.
     * @param _nations Array of nation ids
     * @param _quantities Array of quantities to mint
     * @param _useFreeMintPass Whether to use free mint pass
     * @dev This function is payable and requires the caller to send the correct amount of native tokens.
     */
    function mint(uint32[] calldata _nations, uint32[] calldata _quantities, bool _useFreeMintPass) external payable;
}
