// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IKamisamaFactory } from "./interfaces/IKamisamaFactory.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { IKamisama } from "./interfaces/IKamisama.sol";

import { Ownable } from "solady/auth/Ownable.sol";

/**
 * @title KamisamaFactory
 * @author 0xAtum
 * @notice Factory for creating Kamisama collections
 */
contract KamisamaFactory is IKamisamaFactory, Ownable {
  mapping(uint32 => address) public generatedCollections;
  address public immutable COLLECTION_TEMPLATE;
  address public immutable VRF_WRAPPER_V2;
  address public override treasury;
  uint32 public collectionCount;

  constructor(
    address _owner,
    address _treasury,
    address _collectionTemplate,
    address _vrfWrapperV2
  ) {
    _initializeOwner(_owner);
    COLLECTION_TEMPLATE = _collectionTemplate;
    VRF_WRAPPER_V2 = _vrfWrapperV2;
    treasury = _treasury;
  }

  function cloneCollection(
    uint256 _cost,
    uint256 _maxSupply,
    string calldata _name,
    string calldata _symbol,
    string calldata _collectionURI
  ) external onlyOwner {
    address collection = LibClone.clone(0, COLLECTION_TEMPLATE);
    IKamisama(collection).initialize(
      _cost, _maxSupply, VRF_WRAPPER_V2, _name, _symbol, _collectionURI
    );

    generatedCollections[collectionCount++] = collection;
    emit CollectionCreated(collectionCount, collection);
  }
}
