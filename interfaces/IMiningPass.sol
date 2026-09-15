// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IMiningPass {
    struct MiningPosition {
        address miner;
        uint64 startTime;
        uint64 power;
        bool active;
        uint256 nonce;
    }

    function getMiningPosition(uint256 tokenId) external view returns (MiningPosition memory);
}
