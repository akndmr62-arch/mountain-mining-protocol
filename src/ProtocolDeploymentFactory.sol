// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MiningPass} from "./MiningPass.sol";
import {MiningMinter} from "./MiningMinter.sol";
import {MiningVault} from "./MiningVault.sol";
import {MountainToken} from "./MountainToken.sol";
import {MiningEngine} from "./MiningEngine.sol";

/// @title ProtocolDeploymentFactory
/// @notice Immutable deployment helper that resolves constructor dependency cycles using CREATE2 + CREATE.
contract ProtocolDeploymentFactory {
    error DeploymentAddressMismatch(address expected, address actual);

    struct Deployment {
        address miningPass;
        address miningMinter;
        address miningVault;
        address mountainToken;
        address miningEngine;
    }

    event ProtocolDeployed(
        bytes32 indexed salt,
        address indexed deployer,
        address miningPass,
        address miningMinter,
        address miningVault,
        address mountainToken,
        address miningEngine
    );

    function deployProtocol(bytes32 salt) external returns (Deployment memory deployed) {
        (Deployment memory predicted, address deployerAddress) = predictProtocol(salt);
        ImmutableProtocolDeployer deployer = new ImmutableProtocolDeployer{salt: salt}();

        if (address(deployer) != deployerAddress) {
            revert DeploymentAddressMismatch(deployerAddress, address(deployer));
        }

        deployed = deployer.deploy(predicted);

        emit ProtocolDeployed(
            salt,
            deployerAddress,
            deployed.miningPass,
            deployed.miningMinter,
            deployed.miningVault,
            deployed.mountainToken,
            deployed.miningEngine
        );
    }

    function predictProtocol(bytes32 salt) public view returns (Deployment memory predicted, address deployerAddress) {
        bytes32 deployerBytecodeHash = keccak256(type(ImmutableProtocolDeployer).creationCode);
        deployerAddress = _computeCreate2Address(address(this), salt, deployerBytecodeHash);

        predicted.miningPass = _computeCreateAddress(deployerAddress, 1);
        predicted.miningMinter = _computeCreateAddress(deployerAddress, 2);
        predicted.miningVault = _computeCreateAddress(deployerAddress, 3);
        predicted.mountainToken = _computeCreateAddress(deployerAddress, 4);
        predicted.miningEngine = _computeCreateAddress(deployerAddress, 5);
    }

    function _computeCreate2Address(address deployer, bytes32 salt, bytes32 bytecodeHash) internal pure returns (address) {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash)))
            )
        );
    }

    function _computeCreateAddress(address deployer, uint8 nonce) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(nonce))))));
    }
}

/// @title ImmutableProtocolDeployer
/// @notice One-shot deployer that uses CREATE nonces to instantiate the protocol with immutable constructor wiring.
contract ImmutableProtocolDeployer {
    error AlreadyDeployed();
    error DeploymentAddressMismatch(address expected, address actual);
    error WiringMismatch();

    bool public deployed;

    function deploy(ProtocolDeploymentFactory.Deployment memory expected)
        external
        returns (ProtocolDeploymentFactory.Deployment memory actual)
    {
        if (deployed) {
            revert AlreadyDeployed();
        }
        deployed = true;

        MiningPass miningPass = new MiningPass(expected.miningEngine, expected.miningMinter);
        MiningMinter miningMinter = new MiningMinter();
        MiningVault miningVault = new MiningVault(address(miningPass), expected.miningEngine, expected.mountainToken);
        MountainToken mountainToken = new MountainToken(address(miningVault));
        MiningEngine miningEngine = new MiningEngine(address(miningPass), address(miningVault));

        actual = ProtocolDeploymentFactory.Deployment({
            miningPass: address(miningPass),
            miningMinter: address(miningMinter),
            miningVault: address(miningVault),
            mountainToken: address(mountainToken),
            miningEngine: address(miningEngine)
        });

        _assertAddress(expected.miningPass, actual.miningPass);
        _assertAddress(expected.miningMinter, actual.miningMinter);
        _assertAddress(expected.miningVault, actual.miningVault);
        _assertAddress(expected.mountainToken, actual.mountainToken);
        _assertAddress(expected.miningEngine, actual.miningEngine);

        if (
            miningPass.miningEngine() != actual.miningEngine
                || miningPass.miningMinter() != actual.miningMinter
                || address(miningVault.miningPass()) != actual.miningPass
                || miningVault.miningEngine() != actual.miningEngine
                || address(miningVault.mountainToken()) != actual.mountainToken
                || address(miningEngine.miningPass()) != actual.miningPass
                || address(miningEngine.miningVault()) != actual.miningVault
        ) {
            revert WiringMismatch();
        }
    }

    function _assertAddress(address expected, address actual) internal pure {
        if (expected != actual) {
            revert DeploymentAddressMismatch(expected, actual);
        }
    }
}
