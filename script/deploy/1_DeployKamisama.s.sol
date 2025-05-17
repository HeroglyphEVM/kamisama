// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../BaseScript.sol";
import { Kamisama } from "src/Kamisama.sol";
import "../utils/KamisamaHelper.sol";

contract DeployKamisama is BaseScript {
    function run() external override {
        KamisamaConfig memory config =
            abi.decode(vm.parseJson(_getConfig(CONFIG_FILE), string.concat(".", _getNetwork())), (KamisamaConfig));

        _loadContracts(false);
        _loadOtherContractNetwork(true, ARBITRUM);

        (address deployedContract_,) = _tryDeployContract(
            KAMISAMA,
            0,
            type(Kamisama).creationCode,
            abi.encode(config.cost, _getDeployerAddress(), config.treasury, config.lzEndpoint)
        );

        address kamisamaHeroglyphs = contractsOtherNetworks[ARBITRUM][KAMISAMA_HEROGLYPHS];
        Kamisama kamisama = Kamisama(payable(deployedContract_));
        bool isDeployerOwner = kamisama.owner() == _getDeployerAddress();

        if (!_isTestnet() && kamisamaHeroglyphs != address(0) && isDeployerOwner) {
            vm.startBroadcast(_getDeployerPrivateKey());
            kamisama.reveals(0, "ipfs://bafybeiaandyftyy6bjv5ndrckvvdflq7jtlgodif3hhicax6kalcqx3edq/");
            kamisama.setPeer(config.lzEndpointIDLinked, bytes32(abi.encode(kamisamaHeroglyphs)));
            kamisama.setDelegate(config.owner);
            kamisama.transferOwnership(config.owner);
            vm.stopBroadcast();
        }
    }
}
