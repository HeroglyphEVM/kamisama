// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IHeroglyphsRelayExtension {
    struct BlockProducerInfo {
        string validatorName;
        uint32 validatorIndex;
    }

    function getBlockProducerInfo(uint256 _blockId) external view returns (BlockProducerInfo memory);
}
