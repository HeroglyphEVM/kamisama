// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../BaseScript.sol";
import { KamisamaHeroglyphs } from "src/KamisamaHeroglyphs.sol";
import "../utils/KamisamaHelper.sol";

contract DeployKamisamaHeroglyphs is BaseScript {
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
                config.heroglyphsRelayer,
                config.lzEndpoint,
                config.lzEndpointIDLinked
            )
        );

        KamisamaHeroglyphs kamisamaHeroglyphs = KamisamaHeroglyphs(payable(deployedContract_));
        bool isDeployerOwner = kamisamaHeroglyphs.owner() == _getDeployerAddress();

        if (!_isTestnet() && kamisama != address(0) && isDeployerOwner) {
            vm.startBroadcast(_getDeployerPrivateKey());
            kamisamaHeroglyphs.setPeer(config.lzEndpointIDLinked, bytes32(abi.encode(kamisama)));
            kamisamaHeroglyphs.setDelegate(config.owner);
            kamisamaHeroglyphs.transferOwnership(config.owner);
            vm.stopBroadcast();
        }
    }
}
