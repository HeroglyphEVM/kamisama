// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IKamisama {
  enum ERROR_CODE {
    NAME_EMPTY,
    SYMBOL_EMPTY,
    COLLECTION_URI_EMPTY,
    MAX_SUPPLY_ZERO
  }

  error Misconfiguration(ERROR_CODE code);
  error MaxSupplyReached();
  error MintRequestNotFound();
  error MintRequestAlreadyFulfilled();
  error MintRequestNotFulfilled();
  error TokenAlreadyMinted();
  error NotEnoughNative();
  error FailedToSendNative();
  error OnlyRequestReceiver();
  error InvalidReceiver();

  event MintRequestCreated(uint256 requestId, MintRequest request);
  event MintRequestUpdated(uint256 requestId, MintRequest request);

  struct MintRequest {
    address to;
    uint256 nftId;
    uint256 result;
  }

  function initialize(
    uint256 _cost,
    uint256 _maxSupply,
    address _vrfV2PlusWrapper,
    string calldata _name,
    string calldata _symbol,
    string calldata _collectionURI
  ) external;
}
