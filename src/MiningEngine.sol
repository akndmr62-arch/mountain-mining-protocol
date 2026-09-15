// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IMiningPass} from "../interfaces/IMiningPass.sol";

interface IMiningVault {
    function pendingReward(uint256 tokenId) external view returns (uint256);
    function claimReward(uint256 tokenId, address caller) external returns (uint256 reward, address miner);
    function disburseReward(uint256 tokenId) external;
}

/// @title MiningEngine
/// @notice Deterministic reward calculator/orchestrator with no token mint authority.
contract MiningEngine is ReentrancyGuard {
    error InvalidAddress();
    error NotMining(uint256 tokenId);
    error UnauthorizedMiner(address caller, address miner);

    IMiningPass public immutable miningPass;
    IMiningVault public immutable miningVault;

    event ClaimAndRelease(uint256 indexed tokenId, address indexed miner, uint256 reward);

    constructor(address miningPass_, address miningVault_) {
        if (miningPass_ == address(0) || miningVault_ == address(0)) {
            revert InvalidAddress();
        }
        miningPass = IMiningPass(miningPass_);
        miningVault = IMiningVault(miningVault_);
    }

    /// @notice Deterministic pending reward using the global emission constant and MiningPass power.
    function pendingReward(uint256 tokenId) public view returns (uint256) {
        return miningVault.pendingReward(tokenId);
    }

    /// @notice Claims reward and releases the NFT back to the authoritative miner atomically.
    function claimAndRelease(uint256 tokenId) external nonReentrant returns (uint256 reward) {
        IMiningPass.MiningPosition memory position = miningPass.getMiningPosition(tokenId);
        if (!position.active || position.miner == address(0)) {
            revert NotMining(tokenId);
        }
        if (position.miner != msg.sender) {
            revert UnauthorizedMiner(msg.sender, position.miner);
        }

        (reward,) = miningVault.claimReward(tokenId, msg.sender);
        miningPass.releaseFromMining(tokenId);
        miningVault.disburseReward(tokenId);

        emit ClaimAndRelease(tokenId, msg.sender, reward);
    }
}
