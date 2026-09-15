// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import {MiningPass} from "../src/MiningPass.sol";
import {MiningVault} from "../src/MiningVault.sol";
import {MiningEngine} from "../src/MiningEngine.sol";
import {MountainToken} from "../src/MountainToken.sol";

contract MiningVaultHarness is MiningVault {
    constructor(address miningPass_, address miningEngine_, address mountainToken_)
        MiningVault(miningPass_, miningEngine_, mountainToken_)
    {}

    function setTotalEmittedForTest(uint256 value) external {
        totalEmitted = value;
    }
}

contract MiningProtocolTest is Test {
    uint256 internal constant MAX_EMISSION = 1_000_000_000 ether;
    uint256 internal constant MAX_MINING_DURATION = 630_720_000;
    uint256 internal constant WEIGHTED_POWER = 486_000;
    uint256 internal constant REWARD_DENOMINATOR = WEIGHTED_POWER * MAX_MINING_DURATION;

    MiningPass internal miningPass;
    MiningVaultHarness internal miningVault;
    MiningEngine internal miningEngine;
    MountainToken internal mountainToken;

    address internal minter = address(0xC0FFEE);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal attacker = address(0xBAD);

    function setUp() external {
        uint64 nonce = vm.getNonce(address(this));
        address predictedToken = vm.computeCreateAddress(address(this), nonce + 2);
        address predictedEngine = vm.computeCreateAddress(address(this), nonce + 3);

        miningPass = new MiningPass(predictedEngine, minter);
        miningVault = new MiningVaultHarness(address(miningPass), predictedEngine, predictedToken);
        mountainToken = new MountainToken(address(miningVault));
        miningEngine = new MiningEngine(address(miningPass), address(miningVault));
    }

    function testConstantsAndInitialSupply() external view {
        assertEq(miningVault.MAX_EMISSION(), MAX_EMISSION);
        assertEq(miningVault.MAX_MINING_DURATION(), MAX_MINING_DURATION);
        assertEq(miningVault.TOTAL_WEIGHTED_POWER(), WEIGHTED_POWER);
        assertEq(miningVault.REWARD_DENOMINATOR(), REWARD_DENOMINATOR);
        assertEq(mountainToken.totalSupply(), MAX_EMISSION);
        assertEq(mountainToken.balanceOf(address(miningVault)), MAX_EMISSION);
    }

    function testAllClassRewardsAtOneDay() external {
        _assertRewardsByClassAtElapsed(1 days);
    }

    function testAllClassRewardsAtThirtyDays() external {
        _assertRewardsByClassAtElapsed(30 days);
    }

    function testAllClassRewardsAtOneYear() external {
        _assertRewardsByClassAtElapsed(365 days);
    }

    function testAllClassRewardsAtTwentyYears() external {
        _assertRewardsByClassAtElapsed(MAX_MINING_DURATION);
    }

    function testZeroElapsedTime() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Stone);
        vm.prank(alice);
        miningPass.mine(tokenId);

        assertEq(miningEngine.pendingReward(tokenId), 0);

        vm.prank(alice);
        uint256 reward = miningEngine.claimAndRelease(tokenId);
        assertEq(reward, 0);
        assertEq(mountainToken.balanceOf(alice), 0);
        assertEq(miningPass.ownerOf(tokenId), alice);
    }

    function testOneSecondReward() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Mithril);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + 1);
        assertEq(miningEngine.pendingReward(tokenId), _rewardFor(64, 1));
    }

    function testPendingRewardClampedAfterTwentyYears() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Diamond);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + MAX_MINING_DURATION);
        uint256 atBoundary = miningEngine.pendingReward(tokenId);

        vm.warp(block.timestamp + 400 days);
        uint256 afterBoundary = miningEngine.pendingReward(tokenId);

        assertEq(atBoundary, afterBoundary);
    }

    function testRewardGrowthIsMonotonic() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Steel);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + 1);
        uint256 r1 = miningEngine.pendingReward(tokenId);
        vm.warp(block.timestamp + 1 days);
        uint256 r2 = miningEngine.pendingReward(tokenId);
        vm.warp(block.timestamp + 30 days);
        uint256 r3 = miningEngine.pendingReward(tokenId);
        vm.warp(block.timestamp + 365 days);
        uint256 r4 = miningEngine.pendingReward(tokenId);

        assertLe(r1, r2);
        assertLe(r2, r3);
        assertLe(r3, r4);
    }

    function testUnauthorizedClaimReverts() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Iron);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + 10 days);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(MiningEngine.UnauthorizedMiner.selector, attacker, alice));
        miningEngine.claimAndRelease(tokenId);
    }

    function testWrongMinerCannotClaim() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Obsidian);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + 2 days);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(MiningEngine.UnauthorizedMiner.selector, bob, alice));
        miningEngine.claimAndRelease(tokenId);
    }

    function testDoubleClaimIsImpossible() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Titanium);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + 20 days);
        vm.prank(alice);
        miningEngine.claimAndRelease(tokenId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MiningEngine.NotMining.selector, tokenId));
        miningEngine.claimAndRelease(tokenId);
    }

    function testInactiveTokenCannotClaimAndReturnsZeroPending() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Stone);
        assertEq(miningEngine.pendingReward(tokenId), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MiningEngine.NotMining.selector, tokenId));
        miningEngine.claimAndRelease(tokenId);
    }

    function testNonexistentTokenReverts() external {
        vm.expectRevert(abi.encodeWithSelector(MiningPass.ERC721NonexistentToken.selector, 999_999));
        miningEngine.pendingReward(999_999);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MiningPass.ERC721NonexistentToken.selector, 999_999));
        miningEngine.claimAndRelease(999_999);
    }

    function testClaimPaysMinerOnlyAndRestoresOwnership() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Mithril);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + 365 days);
        uint256 expected = _rewardFor(64, 365 days);

        vm.prank(alice);
        uint256 reward = miningEngine.claimAndRelease(tokenId);

        assertEq(reward, expected);
        assertEq(mountainToken.balanceOf(alice), expected);
        assertEq(mountainToken.balanceOf(bob), 0);
        assertEq(miningPass.ownerOf(tokenId), alice);
        assertFalse(miningPass.isMining(tokenId));
    }

    function testCustodyInvariantWhileActive() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Steel);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + 77 days);
        assertTrue(miningPass.isMining(tokenId));
        assertEq(miningPass.ownerOf(tokenId), address(miningPass));
        assertEq(miningPass.miningOwner(tokenId), alice);
    }

    function testGlobalEmissionCapClampsPayout() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Mithril);
        vm.prank(alice);
        miningPass.mine(tokenId);

        uint256 nearCap = MAX_EMISSION - 7;
        miningVault.setTotalEmittedForTest(nearCap);

        vm.warp(block.timestamp + MAX_MINING_DURATION);
        vm.prank(alice);
        uint256 reward = miningEngine.claimAndRelease(tokenId);

        assertEq(reward, 7);
        assertEq(miningVault.totalEmitted(), MAX_EMISSION);
        assertEq(mountainToken.balanceOf(alice), 7);
    }

    function testExhaustedEmissionProducesZeroRewardButAllowsRelease() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Mithril);
        vm.prank(alice);
        miningPass.mine(tokenId);

        miningVault.setTotalEmittedForTest(MAX_EMISSION);
        vm.warp(block.timestamp + MAX_MINING_DURATION);

        assertEq(miningEngine.pendingReward(tokenId), 0);

        vm.prank(alice);
        uint256 reward = miningEngine.claimAndRelease(tokenId);
        assertEq(reward, 0);
        assertEq(mountainToken.balanceOf(alice), 0);
        assertEq(miningVault.totalEmitted(), MAX_EMISSION);
        assertEq(miningPass.ownerOf(tokenId), alice);
    }

    function testExhaustedEmissionZeroElapsedStillAllowsZeroRewardRelease() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Stone);
        vm.prank(alice);
        miningPass.mine(tokenId);

        miningVault.setTotalEmittedForTest(MAX_EMISSION);
        assertEq(miningEngine.pendingReward(tokenId), 0);

        vm.prank(alice);
        uint256 reward = miningEngine.claimAndRelease(tokenId);
        assertEq(reward, 0);
        assertEq(mountainToken.balanceOf(alice), 0);
        assertEq(miningPass.ownerOf(tokenId), alice);
    }

    function testNoRewardGrowthPastTwentyYearBoundary() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Iron);
        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.warp(block.timestamp + MAX_MINING_DURATION);
        uint256 rewardAtBoundary = miningEngine.pendingReward(tokenId);
        vm.warp(block.timestamp + 365 days);
        uint256 rewardAfter = miningEngine.pendingReward(tokenId);

        assertEq(rewardAtBoundary, rewardAfter);
    }

    function testFullCapacityTwentyYearMathInvariantUnderCap() external view {
        uint256[7] memory capacities = [uint256(40_000), 25_000, 15_000, 10_000, 6_000, 3_000, 1_000];
        uint256[7] memory powers = [uint256(1), 2, 4, 8, 16, 32, 64];

        uint256 total;
        for (uint256 i = 0; i < capacities.length; i++) {
            total += capacities[i] * _rewardFor(powers[i], MAX_MINING_DURATION);
        }

        assertLe(total, MAX_EMISSION);
    }

    function testClassShareOfTotalEmissionMatchesWeightedPower() external view {
        uint256[7] memory capacities = [uint256(40_000), 25_000, 15_000, 10_000, 6_000, 3_000, 1_000];
        uint256[7] memory powers = [uint256(1), 2, 4, 8, 16, 32, 64];

        uint256 classWeightedPower;
        uint256 sumWeightedPower;
        for (uint256 i = 0; i < capacities.length; i++) {
            classWeightedPower = capacities[i] * powers[i];
            sumWeightedPower += classWeightedPower;
        }
        assertEq(sumWeightedPower, WEIGHTED_POWER);
    }

    function testFuzzElapsedTimeClampsToTwentyYears(uint8 classSeed, uint256 extraSeconds) external {
        MiningPass.MiningClass classId = MiningPass.MiningClass(uint8(bound(classSeed, 0, uint8(MiningPass.MiningClass.Mithril))));
        uint256 power = _classPower(classId);
        uint256 tokenId = _mintTo(alice, classId);

        vm.prank(alice);
        miningPass.mine(tokenId);

        uint256 boundedExtra = bound(extraSeconds, MAX_MINING_DURATION + 1, type(uint64).max);
        vm.warp(block.timestamp + boundedExtra);

        uint256 expected = _rewardFor(power, MAX_MINING_DURATION);
        assertEq(miningEngine.pendingReward(tokenId), expected);
    }

    function testFuzzPendingRewardMatchesFormulaUnderBoundedElapsed(uint8 classSeed, uint256 elapsedSeconds) external {
        MiningPass.MiningClass classId = MiningPass.MiningClass(uint8(bound(classSeed, 0, uint8(MiningPass.MiningClass.Mithril))));
        uint256 power = _classPower(classId);
        uint256 tokenId = _mintTo(alice, classId);

        vm.prank(alice);
        miningPass.mine(tokenId);

        uint256 boundedElapsed = bound(elapsedSeconds, 0, MAX_MINING_DURATION);
        vm.warp(block.timestamp + boundedElapsed);

        assertEq(miningEngine.pendingReward(tokenId), _rewardFor(power, boundedElapsed));
    }

    function _assertRewardsByClassAtElapsed(uint256 elapsed) internal {
        MiningPass.MiningClass[7] memory classes = [
            MiningPass.MiningClass.Stone,
            MiningPass.MiningClass.Obsidian,
            MiningPass.MiningClass.Iron,
            MiningPass.MiningClass.Steel,
            MiningPass.MiningClass.Titanium,
            MiningPass.MiningClass.Diamond,
            MiningPass.MiningClass.Mithril
        ];
        uint256[7] memory powers = [uint256(1), 2, 4, 8, 16, 32, 64];

        for (uint256 i = 0; i < classes.length; i++) {
            address miner = address(uint160(0x1000 + i));
            uint256 tokenId = _mintTo(miner, classes[i]);
            vm.prank(miner);
            miningPass.mine(tokenId);
            uint256 startedAt = miningPass.miningStartedAt(tokenId);
            vm.warp(startedAt + elapsed);

            assertEq(miningEngine.pendingReward(tokenId), _rewardFor(powers[i], elapsed));
        }
    }

    function _classPower(MiningPass.MiningClass classId) internal pure returns (uint256) {
        if (classId == MiningPass.MiningClass.Stone) return 1;
        if (classId == MiningPass.MiningClass.Obsidian) return 2;
        if (classId == MiningPass.MiningClass.Iron) return 4;
        if (classId == MiningPass.MiningClass.Steel) return 8;
        if (classId == MiningPass.MiningClass.Titanium) return 16;
        if (classId == MiningPass.MiningClass.Diamond) return 32;
        return 64;
    }

    function _rewardFor(uint256 power, uint256 elapsed) internal pure returns (uint256) {
        uint256 effectiveElapsed = elapsed > MAX_MINING_DURATION ? MAX_MINING_DURATION : elapsed;
        return (power * effectiveElapsed * MAX_EMISSION) / REWARD_DENOMINATOR;
    }

    function _mintTo(address to, MiningPass.MiningClass classId) internal returns (uint256 tokenId) {
        vm.prank(minter);
        tokenId = miningPass.mintMiningPass(to, classId, MiningPass.DistributionPhase.PublicSale);
    }
}
