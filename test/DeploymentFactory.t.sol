// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import {ProtocolDeploymentFactory} from "../src/ProtocolDeploymentFactory.sol";
import {MiningPass} from "../src/MiningPass.sol";
import {MiningVault} from "../src/MiningVault.sol";
import {MountainToken} from "../src/MountainToken.sol";
import {MiningEngine} from "../src/MiningEngine.sol";

contract DeploymentFactoryTest is Test {
    function testPredictMatchesDeployedAddressesAndWiring() external {
        ProtocolDeploymentFactory factory = new ProtocolDeploymentFactory();
        bytes32 salt = keccak256("MMP_DEPLOYMENT_TEST");

        (ProtocolDeploymentFactory.Deployment memory predicted, address deployerAddress) = factory.predictProtocol(salt);
        ProtocolDeploymentFactory.Deployment memory deployed = factory.deployProtocol(salt);

        assertEq(predicted.miningPass, deployed.miningPass);
        assertEq(predicted.miningMinter, deployed.miningMinter);
        assertEq(predicted.miningVault, deployed.miningVault);
        assertEq(predicted.mountainToken, deployed.mountainToken);
        assertEq(predicted.miningEngine, deployed.miningEngine);

        assertGt(deployerAddress.code.length, 0);

        MiningPass miningPass = MiningPass(deployed.miningPass);
        MiningVault miningVault = MiningVault(deployed.miningVault);
        MountainToken mountainToken = MountainToken(deployed.mountainToken);
        MiningEngine miningEngine = MiningEngine(deployed.miningEngine);

        assertEq(miningPass.miningEngine(), deployed.miningEngine);
        assertEq(miningPass.miningMinter(), deployed.miningMinter);
        assertEq(address(miningVault.miningPass()), deployed.miningPass);
        assertEq(miningVault.miningEngine(), deployed.miningEngine);
        assertEq(address(miningVault.mountainToken()), deployed.mountainToken);
        assertEq(address(miningEngine.miningPass()), deployed.miningPass);
        assertEq(address(miningEngine.miningVault()), deployed.miningVault);
        assertEq(mountainToken.balanceOf(deployed.miningVault), mountainToken.MAX_SUPPLY());
    }

    function testSecondDeployWithSameSaltReverts() external {
        ProtocolDeploymentFactory factory = new ProtocolDeploymentFactory();
        bytes32 salt = keccak256("MMP_DEPLOYMENT_TEST_DUP");

        factory.deployProtocol(salt);
        vm.expectRevert();
        factory.deployProtocol(salt);
    }
}
