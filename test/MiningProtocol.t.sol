// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import {MiningPass} from "../src/MiningPass.sol";

contract MiningProtocolTest is Test {
    MiningPass internal miningPass;

    address internal vault = address(0xE11);
    address internal distributor = address(0xC0FFEE);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal attacker = address(0xBAD);

    function setUp() external {
        miningPass = new MiningPass(vault, distributor);
    }

    function testMintAndOwnership() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Stone);

        assertEq(miningPass.ownerOf(tokenId), alice);
        assertEq(uint256(miningPass.miningClass(tokenId)), uint256(MiningPass.MiningClass.Stone));
        assertEq(miningPass.totalMinted(), 1);
    }

    function testStartMining() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Obsidian);

        vm.prank(alice);
        miningPass.mine(tokenId);

        assertEq(miningPass.ownerOf(tokenId), address(miningPass));
        assertTrue(miningPass.isMining(tokenId));
        assertEq(miningPass.miningStartedAt(tokenId), block.timestamp);
        assertEq(miningPass.miningOwner(tokenId), alice);
    }

    function testCannotMineTwice() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Iron);

        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MiningPass.AlreadyMining.selector, tokenId));
        miningPass.mine(tokenId);
    }

    function testNonexistentTokenCannotMine() external {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MiningPass.ERC721NonexistentToken.selector, 999_999));
        miningPass.mine(999_999);
    }

    function testNonOwnerCannotStartMining() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Steel);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(MiningPass.NotTokenOwner.selector, tokenId, attacker));
        miningPass.mine(tokenId);
    }

    function testNFTHeldByProtocolWhileMining() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Titanium);

        vm.prank(alice);
        miningPass.mine(tokenId);

        assertEq(miningPass.ownerOf(tokenId), address(miningPass));
    }

    function testUnauthorizedReleaseReverts() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Diamond);

        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(MiningPass.UnauthorizedCaller.selector, attacker));
        miningPass.releaseFromMining(tokenId);
    }

    function testReleaseWhenInactiveReverts() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Diamond);

        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSelector(MiningPass.NotMining.selector, tokenId));
        miningPass.releaseFromMining(tokenId);
    }

    function testAuthorizedReleaseReturnsNFTAndClearsState() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Mithril);

        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.prank(vault);
        miningPass.releaseFromMining(tokenId);

        assertEq(miningPass.ownerOf(tokenId), alice);
        assertFalse(miningPass.isMining(tokenId));
        assertEq(miningPass.miningStartedAt(tokenId), 0);
        assertEq(miningPass.miningOwner(tokenId), address(0));
    }

    function testTransferAfterMiningRelease() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Stone);

        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.prank(vault);
        miningPass.releaseFromMining(tokenId);

        vm.prank(alice);
        miningPass.transferFrom(alice, bob, tokenId);

        assertEq(miningPass.ownerOf(tokenId), bob);
    }

    function testCannotTransferOrApproveWhileMining() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Obsidian);

        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.prank(alice);
        vm.expectRevert();
        miningPass.transferFrom(alice, bob, tokenId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MiningPass.TokenInMining.selector, tokenId));
        miningPass.approve(bob, tokenId);
    }

    function testMiningTimestampRemainsConstant() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Iron);

        vm.prank(alice);
        miningPass.mine(tokenId);

        uint256 startedAt = miningPass.miningStartedAt(tokenId);

        vm.warp(block.timestamp + 30 days);

        assertEq(miningPass.miningStartedAt(tokenId), startedAt);
        assertEq(miningPass.miningOwner(tokenId), alice);
        assertEq(miningPass.ownerOf(tokenId), address(miningPass));
    }

    function testMultipleNFTStatesAreIsolated() external {
        uint256 aliceToken = _mintTo(alice, MiningPass.MiningClass.Steel);
        uint256 bobToken = _mintTo(bob, MiningPass.MiningClass.Diamond);

        vm.prank(alice);
        miningPass.mine(aliceToken);

        assertTrue(miningPass.isMining(aliceToken));
        assertFalse(miningPass.isMining(bobToken));
        assertEq(miningPass.miningOwner(aliceToken), alice);
        assertEq(miningPass.ownerOf(bobToken), bob);

        vm.prank(bob);
        miningPass.mine(bobToken);

        assertTrue(miningPass.isMining(aliceToken));
        assertTrue(miningPass.isMining(bobToken));
        assertEq(miningPass.miningOwner(bobToken), bob);
    }

    function testSafeTransferToCustodyBypassIsBlocked() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Stone);

        vm.prank(alice);
        vm.expectRevert(MiningPass.CustodyTransferNotAllowed.selector);
        miningPass.safeTransferFrom(alice, address(miningPass), tokenId);
    }

    function testCannotTransferOutOfCustodyBypass() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Obsidian);

        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.prank(attacker);
        vm.expectRevert();
        miningPass.transferFrom(address(miningPass), attacker, tokenId);
    }

    function testSetApprovalForAllCannotBypassCustody() external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Steel);
        address operator = address(0x0B3);

        vm.prank(alice);
        miningPass.setApprovalForAll(operator, true);

        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.prank(operator);
        vm.expectRevert();
        miningPass.transferFrom(address(miningPass), operator, tokenId);
    }

    function testFuzz_MiningSessionStateStable(uint96 warpBy) external {
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Titanium);

        vm.prank(alice);
        miningPass.mine(tokenId);

        uint256 startedAt = miningPass.miningStartedAt(tokenId);
        address miner = miningPass.miningOwner(tokenId);

        uint256 boundedWarp = bound(uint256(warpBy), 1, 3650 days);
        vm.warp(block.timestamp + boundedWarp);

        assertTrue(miningPass.isMining(tokenId));
        assertEq(miningPass.miningStartedAt(tokenId), startedAt);
        assertEq(miningPass.miningOwner(tokenId), miner);
        assertEq(miningPass.ownerOf(tokenId), address(miningPass));
    }

    function testFuzz_ActiveInvariantHolds(uint8 classSeed, uint96 warpBy) external {
        MiningPass.MiningClass classId = MiningPass.MiningClass(uint8(bound(classSeed, 0, uint8(MiningPass.MiningClass.Mithril))));
        uint256 tokenId = _mintTo(alice, classId);

        vm.prank(alice);
        miningPass.mine(tokenId);
        vm.warp(block.timestamp + bound(uint256(warpBy), 1, 1800 days));

        assertTrue(miningPass.isMining(tokenId));
        assertEq(miningPass.ownerOf(tokenId), address(miningPass));
        assertGt(miningPass.miningStartedAt(tokenId), 0);
        assertTrue(miningPass.miningOwner(tokenId) != address(0));
    }

    function testFuzz_ReleaseResetsStateAndRestoresOwner(uint8 classSeed, uint96 warpBy) external {
        MiningPass.MiningClass classId = MiningPass.MiningClass(uint8(bound(classSeed, 0, uint8(MiningPass.MiningClass.Mithril))));
        uint256 tokenId = _mintTo(alice, classId);

        vm.prank(alice);
        miningPass.mine(tokenId);
        vm.warp(block.timestamp + bound(uint256(warpBy), 1, 1800 days));

        vm.prank(vault);
        miningPass.releaseFromMining(tokenId);

        assertFalse(miningPass.isMining(tokenId));
        assertEq(miningPass.miningStartedAt(tokenId), 0);
        assertEq(miningPass.miningOwner(tokenId), address(0));
        assertEq(miningPass.ownerOf(tokenId), alice);
    }

    function testFuzz_UnauthorizedCannotRelease(address caller) external {
        vm.assume(caller != vault && caller != address(0));
        uint256 tokenId = _mintTo(alice, MiningPass.MiningClass.Obsidian);

        vm.prank(alice);
        miningPass.mine(tokenId);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(MiningPass.UnauthorizedCaller.selector, caller));
        miningPass.releaseFromMining(tokenId);
    }

    function _mintTo(address to, MiningPass.MiningClass classId) internal returns (uint256 tokenId) {
        vm.prank(distributor);
        tokenId = miningPass.mintMiningPass(to, classId, MiningPass.DistributionPhase.PublicSale);
    }
}
