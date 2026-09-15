// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title MiningPass
/// @notice Skeleton only. Production logic intentionally deferred.
contract MiningPass {
    uint256 public constant MAX_TOTAL_SUPPLY = 100_000;

    struct MiningPosition {
        address miner;
        uint64 startTime;
        uint64 power;
        bool active;
        uint256 nonce;
    }
}
