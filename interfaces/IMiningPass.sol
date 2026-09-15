// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IMiningPass {
    enum MiningClass {
        Stone,
        Obsidian,
        Iron,
        Steel,
        Titanium,
        Diamond,
        Mithril
    }

    struct MiningPosition {
        address miner;
        uint64 startedAt;
        bool active;
        MiningClass classId;
        uint64 power;
    }

    function mine(uint256 tokenId) external;

    function releaseFromMining(uint256 tokenId) external;

    function isMining(uint256 tokenId) external view returns (bool);

    function miningStartedAt(uint256 tokenId) external view returns (uint256);

    function miningOwner(uint256 tokenId) external view returns (address);

    function miningClass(uint256 tokenId) external view returns (MiningClass);

    function miningPower(uint256 tokenId) external view returns (uint64);

    function getMiningPosition(uint256 tokenId) external view returns (MiningPosition memory);
}
