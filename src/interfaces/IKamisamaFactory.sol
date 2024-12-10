// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IKamisamaFactory {
  event CollectionCreated(uint32 indexed id, address collection);

  function treasury() external view returns (address);
}
