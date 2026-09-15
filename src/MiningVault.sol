// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IMiningPass} from "../interfaces/IMiningPass.sol";

/// @title MiningVault
/// @notice Authoritative reward accounting and payout layer.
contract MiningVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error UnauthorizedCaller(address caller);
    error NotMining(uint256 tokenId);
    error UnauthorizedMiner(address caller, address miner);

    uint256 public constant MAX_EMISSION = 1_000_000_000 ether;
    uint256 public constant MAX_MINING_DURATION = 630_720_000; // 20 years
    uint256 public constant TOTAL_WEIGHTED_POWER = 486_000;
    uint256 public constant REWARD_DENOMINATOR = TOTAL_WEIGHTED_POWER * MAX_MINING_DURATION;

    IMiningPass public immutable miningPass;
    IERC20 public immutable mountainToken;
    address public immutable miningEngine;

    uint256 public totalEmitted;

    event RewardClaimed(uint256 indexed tokenId, address indexed miner, uint256 reward, uint256 elapsed);

    constructor(address miningPass_, address miningEngine_, address mountainToken_) {
        if (miningPass_ == address(0) || miningEngine_ == address(0) || mountainToken_ == address(0)) {
            revert InvalidAddress();
        }
        miningPass = IMiningPass(miningPass_);
        miningEngine = miningEngine_;
        mountainToken = IERC20(mountainToken_);
    }

    modifier onlyMiningEngine() {
        if (msg.sender != miningEngine) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    /// @notice Computes deterministic pending reward from MiningPass-authoritative state.
    function pendingReward(uint256 tokenId) public view returns (uint256) {
        IMiningPass.MiningPosition memory position = miningPass.getMiningPosition(tokenId);
        if (!position.active || position.miner == address(0)) {
            return 0;
        }

        uint256 elapsed = block.timestamp - uint256(position.startedAt);
        if (elapsed > MAX_MINING_DURATION) {
            elapsed = MAX_MINING_DURATION;
        }

        uint256 reward = Math.mulDiv(uint256(position.power) * elapsed, MAX_EMISSION, REWARD_DENOMINATOR);
        uint256 remaining = MAX_EMISSION - totalEmitted;
        if (reward > remaining) {
            return remaining;
        }
        return reward;
    }

    /// @notice Claims reward for an active mining position and pays the authoritative miner.
    /// @dev Callable only by MiningEngine to preserve atomic claim-and-release flow.
    function claimReward(uint256 tokenId, address caller)
        external
        onlyMiningEngine
        nonReentrant
        returns (uint256 reward, address miner)
    {
        IMiningPass.MiningPosition memory position = miningPass.getMiningPosition(tokenId);
        if (!position.active || position.miner == address(0)) {
            revert NotMining(tokenId);
        }
        if (caller != position.miner) {
            revert UnauthorizedMiner(caller, position.miner);
        }

        uint256 elapsed = block.timestamp - uint256(position.startedAt);
        if (elapsed > MAX_MINING_DURATION) {
            elapsed = MAX_MINING_DURATION;
        }

        reward = Math.mulDiv(uint256(position.power) * elapsed, MAX_EMISSION, REWARD_DENOMINATOR);
        uint256 remaining = MAX_EMISSION - totalEmitted;
        if (reward > remaining) {
            reward = remaining;
        }

        totalEmitted += reward;
        miner = position.miner;

        if (reward > 0) {
            mountainToken.safeTransfer(miner, reward);
        }

        emit RewardClaimed(tokenId, miner, reward, elapsed);
    }
}
