// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import {ProtocolDeploymentFactory, ImmutableProtocolDeployer} from "../src/ProtocolDeploymentFactory.sol";
import {MiningPass} from "../src/MiningPass.sol";
import {MiningVault} from "../src/MiningVault.sol";
import {MountainToken} from "../src/MountainToken.sol";
import {MiningEngine} from "../src/MiningEngine.sol";

contract DeploymentFactoryTest is Test {
    uint256 private constant MAX_SUPPLY = 1_000_000_000 ether;

    function testPredictRespectsNonceOrder() external {
        ProtocolDeploymentFactory factory = new ProtocolDeploymentFactory();
        bytes32 salt = keccak256("MMP_DEPLOYMENT_NONCE_ORDER");

        (ProtocolDeploymentFactory.Deployment memory predicted, address deployerAddress) = factory.predictProtocol(salt);

        assertEq(predicted.miningPass, vm.computeCreateAddress(deployerAddress, 1));
        assertEq(predicted.miningMinter, vm.computeCreateAddress(deployerAddress, 2));
        assertEq(predicted.miningVault, vm.computeCreateAddress(deployerAddress, 3));
        assertEq(predicted.mountainToken, vm.computeCreateAddress(deployerAddress, 4));
        assertEq(predicted.miningEngine, vm.computeCreateAddress(deployerAddress, 5));
    }

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
        assertEq(mountainToken.balanceOf(deployed.miningVault), MAX_SUPPLY);
        assertEq(mountainToken.totalSupply(), MAX_SUPPLY);
    }

    function testSecondDeployWithSameSaltReverts() external {
        ProtocolDeploymentFactory factory = new ProtocolDeploymentFactory();
        bytes32 salt = keccak256("MMP_DEPLOYMENT_TEST_DUP");

        factory.deployProtocol(salt);
        vm.expectRevert();
        factory.deployProtocol(salt);
    }

    function testImmutableProtocolDeployerCannotDeployTwice() external {
        ProtocolDeploymentFactory factory = new ProtocolDeploymentFactory();
        bytes32 salt = keccak256("MMP_IMMUTABLE_DEPLOYER_ONESHOT");

        (ProtocolDeploymentFactory.Deployment memory predicted, address deployerAddress) = factory.predictProtocol(salt);
        factory.deployProtocol(salt);

        vm.expectRevert(ImmutableProtocolDeployer.AlreadyDeployed.selector);
        ImmutableProtocolDeployer(deployerAddress).deploy(predicted);
    }

    function testMountainTokenHasNoPostDeploymentMintPath() external {
        ProtocolDeploymentFactory factory = new ProtocolDeploymentFactory();
        ProtocolDeploymentFactory.Deployment memory deployed = factory.deployProtocol(keccak256("MMP_NO_MINT_PATH"));
        MountainToken mountainToken = MountainToken(deployed.mountainToken);

        uint256 supplyBefore = mountainToken.totalSupply();
        (bool ok,) = address(mountainToken).call(abi.encodeWithSignature("mint(address,uint256)", address(this), 1));

        assertFalse(ok);
        assertEq(mountainToken.totalSupply(), supplyBefore);
        assertEq(mountainToken.totalSupply(), MAX_SUPPLY);
    }

    function testFactoryAndDeployerExposeNoAdminSetters() external {
        ProtocolDeploymentFactory factory = new ProtocolDeploymentFactory();
        bytes32 salt = keccak256("MMP_NO_SETTER_SURFACE");
        (, address deployerAddress) = factory.predictProtocol(salt);
        factory.deployProtocol(salt);

        (bool ownerOnFactory,) = address(factory).call(abi.encodeWithSignature("owner()"));
        (bool ownerOnDeployer,) = deployerAddress.call(abi.encodeWithSignature("owner()"));
        (bool setEngineOnFactory,) =
            address(factory).call(abi.encodeWithSignature("setMiningEngine(address)", address(1)));
        (bool setVaultOnFactory,) = address(factory).call(abi.encodeWithSignature("setMiningVault(address)", address(1)));
        (bool setPassOnFactory,) = address(factory).call(abi.encodeWithSignature("setMiningPass(address)", address(1)));
        (bool setTokenOnFactory,) = address(factory).call(abi.encodeWithSignature("setToken(address)", address(1)));
        (bool setEngineOnDeployer,) =
            deployerAddress.call(abi.encodeWithSignature("setMiningEngine(address)", address(1)));
        (bool setVaultOnDeployer,) = deployerAddress.call(abi.encodeWithSignature("setMiningVault(address)", address(1)));
        (bool setPassOnDeployer,) = deployerAddress.call(abi.encodeWithSignature("setMiningPass(address)", address(1)));
        (bool setTokenOnDeployer,) = deployerAddress.call(abi.encodeWithSignature("setToken(address)", address(1)));

        assertFalse(ownerOnFactory);
        assertFalse(ownerOnDeployer);
        assertFalse(setEngineOnFactory);
        assertFalse(setVaultOnFactory);
        assertFalse(setPassOnFactory);
        assertFalse(setTokenOnFactory);
        assertFalse(setEngineOnDeployer);
        assertFalse(setVaultOnDeployer);
        assertFalse(setPassOnDeployer);
        assertFalse(setTokenOnDeployer);
    }
}
