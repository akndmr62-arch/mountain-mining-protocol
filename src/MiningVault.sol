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
    error SessionAlreadyClaimed(uint256 tokenId, uint64 sessionId);
    error PendingPayoutExists(uint256 tokenId);
    error NoPendingPayout(uint256 tokenId);

    uint256 public constant MAX_EMISSION = 1_000_000_000 ether;
    uint256 public constant MAX_MINING_DURATION = 630_720_000; // 20 years
    uint256 public constant TOTAL_WEIGHTED_POWER = 486_000;
    uint256 public constant REWARD_DENOMINATOR = TOTAL_WEIGHTED_POWER * MAX_MINING_DURATION;

    IMiningPass public immutable miningPass;
    IERC20 public immutable mountainToken;
    address public immutable miningEngine;

    uint256 public totalEmitted;
    mapping(uint256 tokenId => uint64 sessionId) public lastClaimedSession;

    struct PendingPayout {
        address miner;
        uint256 reward;
        bool exists;
    }

    mapping(uint256 tokenId => PendingPayout payout) private _pendingPayouts;

    event RewardClaimed(uint256 indexed tokenId, address indexed miner, uint256 reward, uint256 elapsed);
    event RewardPaid(uint256 indexed tokenId, address indexed miner, uint256 reward);

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
    /// @dev Near the global cap this is a best-effort preview; concurrent claims can reduce actual payout before execution.
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
        uint256 remaining = totalEmitted >= MAX_EMISSION ? 0 : (MAX_EMISSION - totalEmitted);
        if (reward > remaining) {
            return remaining;
        }
        return reward;
    }

    /// @notice Computes and reserves reward for an active mining position.
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
        if (lastClaimedSession[tokenId] == position.sessionId) {
            revert SessionAlreadyClaimed(tokenId, position.sessionId);
        }
        if (_pendingPayouts[tokenId].exists) {
            revert PendingPayoutExists(tokenId);
        }

        uint256 elapsed = block.timestamp - uint256(position.startedAt);
        if (elapsed > MAX_MINING_DURATION) {
            elapsed = MAX_MINING_DURATION;
        }

        reward = Math.mulDiv(uint256(position.power) * elapsed, MAX_EMISSION, REWARD_DENOMINATOR);
        uint256 remaining = totalEmitted >= MAX_EMISSION ? 0 : (MAX_EMISSION - totalEmitted);
        if (reward > remaining) {
            reward = remaining;
        }

        totalEmitted += reward;
        lastClaimedSession[tokenId] = position.sessionId;
        miner = position.miner;

        _pendingPayouts[tokenId] = PendingPayout({miner: miner, reward: reward, exists: true});

        emit RewardClaimed(tokenId, miner, reward, elapsed);
    }

    /// @notice Transfers reserved reward to the authoritative miner.
    function disburseReward(uint256 tokenId) external onlyMiningEngine nonReentrant {
        PendingPayout memory payout = _pendingPayouts[tokenId];
        if (!payout.exists) {
            revert NoPendingPayout(tokenId);
        }

        delete _pendingPayouts[tokenId];

        if (payout.reward > 0) {
            mountainToken.safeTransfer(payout.miner, payout.reward);
        }

        emit RewardPaid(tokenId, payout.miner, payout.reward);
    }
}
