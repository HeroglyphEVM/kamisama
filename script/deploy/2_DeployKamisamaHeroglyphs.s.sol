// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../BaseScript.sol";
import { KamisamaHeroglyphs } from "src/KamisamaHeroglyphs.sol";
import { IIdentityRouter } from "src/vendor/IIdentityRouter.sol";
import "../utils/KamisamaHelper.sol";

contract DeployKamisamaHeroglyphs is BaseScript {
    address private constant IDENTITY_ROUTER = 0x8725d36c417BE5Bc43523d59dF61223361a60cc7;

    function run() external override {
        KamisamaConfig memory config =
            abi.decode(vm.parseJson(_getConfig(CONFIG_FILE), string.concat(".", _getNetwork())), (KamisamaConfig));

        _loadContracts(false);
        _loadOtherContractNetwork(true, MAINNET);

        address kamisama = contractsOtherNetworks[MAINNET][KAMISAMA];

        (address deployedContract_,) = _tryDeployContract(
            KAMISAMA_HEROGLYPHS,
            0,
            type(KamisamaHeroglyphs).creationCode,
            abi.encode(
                _getDeployerAddress(),
                config.gasPool,
                config.heroglyphsRelayExtension,
                config.identityRouter,
                config.heroglyphsRelayer,
                config.lzEndpoint,
                config.lzEndpointIDLinked
            )
        );

        KamisamaHeroglyphs kamisamaHeroglyphs = KamisamaHeroglyphs(payable(deployedContract_));
        bool isDeployerOwner = kamisamaHeroglyphs.owner() == _getDeployerAddress();

        if (!_isTestnet() && isDeployerOwner) {
            IIdentityRouter.RouterConfig memory routerConfig;
            PreviousBlockProducer memory blockProducerInfo;
            string memory validatorName;

            for (uint256 i = 0; i < config.pastBlockProducer.length; i++) {
                blockProducerInfo = config.pastBlockProducer[i];
                routerConfig = IIdentityRouter(IDENTITY_ROUTER).getRouterConfig(
                    blockProducerInfo.validatorName, blockProducerInfo.validatorIndex
                );
                validatorName = routerConfig.childName;

                if (bytes(validatorName).length == 0) {
                    validatorName = config.pastBlockProducer[i].validatorName;
                }

                vm.broadcast(_getDeployerPrivateKey());
                kamisamaHeroglyphs.addValidator(validatorName);
            }

            if (kamisama != address(0)) return;

            vm.startBroadcast(_getDeployerPrivateKey());
            kamisamaHeroglyphs.setPeer(config.lzEndpointIDLinked, bytes32(abi.encode(kamisama)));
            kamisamaHeroglyphs.setDelegate(config.owner);
            kamisamaHeroglyphs.transferOwnership(config.owner);
            vm.stopBroadcast();
        }
    }
}
