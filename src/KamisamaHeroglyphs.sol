// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IKamisamaHeroglyphs } from "./interfaces/IKamisamaHeroglyphs.sol";
import { TickerOperator } from "heroglyph-library/TickerOperator.sol";

import { OAppSender } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { OAppCore, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { IHeroglyphsRelayExtension } from "./vendor/IHeroglyphsRelayExtension.sol";
import { IIdentityRouter } from "./vendor/IIdentityRouter.sol";
/**
 * @title KamisamaHeroglyphs
 * @author Heroglyphs' team
 * @notice KamisamaHeroglyphs mint a free nft for validators.
 */

contract KamisamaHeroglyphs is IKamisamaHeroglyphs, TickerOperator, OAppSender {
    using OptionsBuilder for bytes;

    IHeroglyphsRelayExtension public immutable HEROGLYPHS_RELAY_EXTENSION;
    IIdentityRouter public immutable IDENTITY_ROUTER;
    uint32 public lzGasLimit;
    uint32 public lzTargetEndpointId;
    uint32 public latestMintedBlock;
    bytes public defaultLzOption;
    mapping(string validatorName => bool hasMintedKamisamaBefore) public hasMintedKamisamaBefore;

    constructor(
        address _owner,
        address _gasPool,
        address _heroglyphsRelayExtension,
        address _identityRouter,
        address _heroglyphRelay,
        address _lzEndpoint,
        uint32 _lzTargetEndpointId
    ) TickerOperator(_owner, _heroglyphRelay, _gasPool) OAppCore(_lzEndpoint, _owner) {
        lzTargetEndpointId = _lzTargetEndpointId;
        lzGasLimit = 200_000;
        defaultLzOption = OptionsBuilder.newOptions().addExecutorLzReceiveOption(lzGasLimit, 0);

        HEROGLYPHS_RELAY_EXTENSION = IHeroglyphsRelayExtension(_heroglyphsRelayExtension);
        IDENTITY_ROUTER = IIdentityRouter(_identityRouter);
    }

    /**
     * @notice onValidatorTriggered() Callback function when your ticker has been selected
     * @param //_lzEndpointSelected The selected layer zero endpoint target for this ticker
     * @param _blockNumber  // The number of the block minted
     * @param _identityReceiver // The Identity's receiver from the miner graffiti
     * @param _heroglyphFee // The fee to pay for the execution
     * @dev be sure to apply onlyRelay to this function
     * @dev TIP: Avoid using reverts; instead, use return statements, unless you need to restore your contract to its
     * initial state.
     * @dev TIP:Keep in mind that a miner may utilize your ticker more than once in their
     * graffiti. To avoid any repetition, consider utilizing blockNumber to track actions.
     */
    function onValidatorTriggered(
        uint32, /*_lzEndpointSelected*/
        uint32 _blockNumber,
        address _identityReceiver,
        uint128 _heroglyphFee
    ) external override onlyRelay {
        uint32 cachedLZTargetEndpointId = lzTargetEndpointId;
        _repayHeroglyph(_heroglyphFee);

        if (latestMintedBlock >= _blockNumber) return;
        latestMintedBlock = _blockNumber;

        IHeroglyphsRelayExtension.BlockProducerInfo memory blockProducerInfo =
            HEROGLYPHS_RELAY_EXTENSION.getBlockProducerInfo(_blockNumber);

        IIdentityRouter.RouterConfig memory routerConfig =
            IDENTITY_ROUTER.getRouterConfig(blockProducerInfo.validatorName, blockProducerInfo.validatorIndex);

        string memory identityName = routerConfig.childName;

        if (bytes(identityName).length == 0) {
            identityName = blockProducerInfo.validatorName;
        }

        if (hasMintedKamisamaBefore[identityName]) {
            emit KamisamaAlreadyMintedForIdentity(_blockNumber, identityName);
            return;
        }

        hasMintedKamisamaBefore[identityName] = true;

        bytes memory option = defaultLzOption;
        bytes memory payload = abi.encode(_blockNumber, _identityReceiver);
        MessagingFee memory fee = _quote(cachedLZTargetEndpointId, payload, option, false);

        if (!_askFeePayerToPay(address(this), uint128(fee.nativeFee))) revert NotEnoughToPayLayerZero();

        MessagingReceipt memory msgReceipt =
            _lzSend(cachedLZTargetEndpointId, payload, option, fee, payable(address(this)));

        emit KamisamaMintRequested(msgReceipt.guid, _blockNumber, _identityReceiver);
    }

    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        uint256 balance = address(this).balance;

        if (msg.value != 0 && msg.value != _nativeFee) revert NotEnoughNative(msg.value);
        if (msg.value == 0 && balance < _nativeFee) revert NotEnoughNative(balance);

        return _nativeFee;
    }

    function updateLzGasLimit(uint32 _gasLimit) external onlyOwner {
        if (_gasLimit < 50_000) revert GasLimitTooLow();

        lzGasLimit = _gasLimit;
        defaultLzOption = OptionsBuilder.newOptions().addExecutorLzReceiveOption(lzGasLimit, 0);

        emit LzGasLimitUpdated(_gasLimit);
    }

    // @dev LayerZero endpoint id should not be hardcoded.
    // https://docs.layerzero.network/v2/developers/evm/technical-reference/integration-checklist#avoid-hardcoding-layerzero-endpoint-ids
    function updateLzTargetEndpointId(uint32 _lzTargetEndpointId) external onlyOwner {
        lzTargetEndpointId = _lzTargetEndpointId;
        emit LzTargetEndpointIdUpdated(_lzTargetEndpointId);
    }

    // @dev We migrated Kamisama, so we are locking the validator name that has already minted Kamisama.
    function addValidator(string memory _validatorName) external onlyOwner {
        hasMintedKamisamaBefore[_validatorName] = true;
    }
}
