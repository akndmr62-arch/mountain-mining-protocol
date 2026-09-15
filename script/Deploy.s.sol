// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ProtocolDeploymentFactory} from "../src/ProtocolDeploymentFactory.sol";

contract Deploy is Script {
    function run() external {
        bytes32 salt = vm.envOr("MMP_PROTOCOL_SALT", bytes32("MMP_PROTOCOL_V1"));
        address providedFactory = vm.envOr("MMP_FACTORY_ADDRESS", address(0));

        vm.startBroadcast();

        ProtocolDeploymentFactory factory =
            providedFactory == address(0) ? new ProtocolDeploymentFactory() : ProtocolDeploymentFactory(providedFactory);

        (ProtocolDeploymentFactory.Deployment memory predicted, address deployerAddress) = factory.predictProtocol(salt);
        ProtocolDeploymentFactory.Deployment memory deployed = factory.deployProtocol(salt);

        require(predicted.miningPass == deployed.miningPass, "miningPass mismatch");
        require(predicted.miningMinter == deployed.miningMinter, "miningMinter mismatch");
        require(predicted.miningVault == deployed.miningVault, "miningVault mismatch");
        require(predicted.mountainToken == deployed.mountainToken, "mountainToken mismatch");
        require(predicted.miningEngine == deployed.miningEngine, "miningEngine mismatch");

        vm.stopBroadcast();

        console2.log("Factory:", address(factory));
        console2.log("Deployer:", deployerAddress);
        console2.log("MiningPass:", deployed.miningPass);
        console2.log("MiningMinter:", deployed.miningMinter);
        console2.log("MiningVault:", deployed.miningVault);
        console2.log("MountainToken:", deployed.mountainToken);
        console2.log("MiningEngine:", deployed.miningEngine);
    }
}
