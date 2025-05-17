// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IKamisamaHeroglyphs {
    error GasLimitTooLow();
    error NotEnoughToPayLayerZero();

    event KamisamaSet(address indexed kamisama);
    event LzTargetEndpointIdUpdated(uint32 indexed lzTargetEndpointId);
    event LzGasLimitUpdated(uint32 indexed lzGasLimit);
    event KamisamaMintRequested(bytes32 indexed guid, uint256 indexed blockNumber, address indexed validatorWithdrawer);
    event KamisamaAlreadyMintedForIdentity(uint256 indexed blockNumber, string validatorName);
}
