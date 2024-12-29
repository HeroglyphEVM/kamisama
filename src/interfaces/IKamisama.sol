// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IKamisama {
    error MaxSupplyReached();
    error NotEnoughNative();
    error FailedToSendNative();
    error Immutable();
    error InvalidTreasury();

    event KamisamaValidatorMinted(uint256 indexed nftId, address indexed to, bytes32 guid, uint32 indexed blockNumber);
    event Revealed(string collectionURI);
    event KamisamaMinted(address indexed to, uint256 indexed nftId, uint256 cost);
    event ImmutableActivated();
    event TreasurySet(address indexed treasury);
    event MoreUnlocked(uint32 amount);

    /**
     * @notice Mint a Kamisama NFT.
     * @dev This function is payable and requires the caller to send the correct amount of native tokens.
     */
    function mint() external payable;
}
