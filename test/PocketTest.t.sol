// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {PocketUpgradeable} from "../src/pocket/PocketUpgradeable.sol";
import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PocketTest is PipelineTestSetUp {
    uint256 constant LOAN = 3;

    uint256 stakers;

    function setUp() public override {
        super.setUp();
        vm.roll(100);
    }

    function test_setUp() public view {
        assertEq(pocket.authority(), address(authority));
        assertEq(pocket.stakedPlUsd(), address(sPlUsd));
        assertEq(pocket.plUsd(), address(plUsd));
    }

    function test_defaultOpensPocket() public {
        _stake(600);
        _stake(400);

        vm.expectEmit(address(pocket));
        emit PocketUpgradeable.PocketOpened(LOAN, 500, 200, 1_000);

        assertEq(_default(500), 500);

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(LOAN);
        assertEq(pocketData.snapshotBlock, 200);
        assertEq(pocketData.supplyAtSnapshot, 1_000);
        assertEq(pocketData.held, 500);
        assertEq(sPlUsd.totalAssets(), 500);
        _assertBacked();
    }

    function test_recoveriesClaimedBySnapshotHolders() public {
        address a = _stake(600);
        address b = _stake(400);
        _default(500);

        vm.roll(201);
        address c = makeAddr("c");
        vm.prank(b);
        sPlUsd.transfer(c, 400);
        address late = _stake(1_000);

        assertEq(_recover(200, 50), 200);
        _assertBacked();

        assertEq(pocket.claimable(LOAN, a), 150);

        vm.expectEmit(address(pocket));
        emit PocketUpgradeable.Claimed(LOAN, a, 150);

        assertEq(_claim(a), 150);
        assertEq(_claim(b), 100);
        assertEq(_claim(c), 0);
        assertEq(_claim(late), 0);
        assertEq(plUsd.balanceOf(a), 150);
        assertEq(plUsd.balanceOf(b), 100);

        _recover(100, 0);

        assertEq(_claim(a), 60);
        assertEq(_claim(a), 0);
        assertEq(pocket.claimed(LOAN, a), 210);
        assertEq(pocket.pocket(LOAN).held, 200);
        assertEq(pocket.pocket(LOAN).claimedTotal, 310);
        _assertBacked();
    }

    function test_releaseCapsPrincipalAtHeld() public {
        _stake(300);
        assertEq(_default(500), 300);

        vm.expectEmit(address(pocket));
        emit PocketUpgradeable.Released(LOAN, 450, 300, 10);

        assertEq(_recover(450, 10), 300);

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(LOAN);
        assertEq(pocketData.held, 0);
        assertEq(pocketData.releasedTotal, 310);
        _assertBacked();
    }

    function test_burnFromHeldOnly() public {
        _stake(1_000);
        _default(500);
        _recover(200, 0);

        uint256 balanceBefore = plUsd.balanceOf(address(pocket));
        uint256 totalSupplyBefore = plUsd.totalSupply();

        vm.expectEmit(address(pocket));
        emit PocketUpgradeable.Burned(LOAN, 400, 300);

        vm.prank(address(loanRegistry));
        assertEq(pocket.burn(LOAN, 400), 300);

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(LOAN);
        assertEq(pocketData.held, 0);
        assertEq(pocketData.burnedTotal, 300);
        assertEq(pocketData.releasedTotal, 200);
        assertEq(plUsd.balanceOf(address(pocket)), balanceBefore - 300);
        assertEq(plUsd.totalSupply(), totalSupplyBefore - 300);
        _assertBacked();
    }

    function test_unrelease() public {
        _stake(1_000);
        _default(500);
        uint256 released = _recover(200, 50);
        uint256 totalSupplyBefore = plUsd.totalSupply();

        vm.expectEmit(address(pocket));
        emit PocketUpgradeable.Unreleased(LOAN, released, 50);

        vm.prank(address(minter));
        pocket.unrelease(LOAN, released, 50);

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(LOAN);
        assertEq(pocketData.held, 500);
        assertEq(pocketData.releasedTotal, 0);
        assertEq(plUsd.balanceOf(address(pocket)), 500);
        assertEq(plUsd.totalSupply(), totalSupplyBefore - 50);
        _assertBacked();
    }

    function test_unreleaseRefusedOnceClaimed() public {
        address a = _stake(1_000);
        _default(500);
        _recover(200, 50);
        _claim(a);

        vm.prank(address(minter));
        vm.expectRevert(abi.encodeWithSelector(PocketUpgradeable.PocketAlreadyClaimed.selector, LOAN));
        pocket.unrelease(LOAN, 200, 50);

        vm.prank(address(minter));
        vm.expectRevert(abi.encodeWithSelector(PocketUpgradeable.PocketExceedsReleased.selector, LOAN, 500, 250));
        pocket.unrelease(LOAN, 500, 0);
    }

    function test_unreleaseRefusedAfterPartialClaim() public {
        address a = _stake(500);
        address b = _stake(500);
        _default(500);
        _recover(50, 0);
        _recover(50, 0);
        _claim(a);

        vm.prank(address(minter));
        vm.expectRevert(abi.encodeWithSelector(PocketUpgradeable.PocketAlreadyClaimed.selector, LOAN));
        pocket.unrelease(LOAN, 50, 0);

        assertEq(_claim(b), 50);

        vm.prank(address(loanRegistry));
        assertEq(pocket.burn(LOAN, 400), 400);
        _assertBacked();
    }

    function test_oneLoanOnePocket() public {
        _stake(1_000);
        _default(500);

        vm.prank(address(loanRegistry));
        vm.expectRevert(abi.encodeWithSelector(PocketUpgradeable.PocketAlreadyOpened.selector, LOAN));
        sPlUsd.carveOut(LOAN, 100);
    }

    function test_notOpened() public {
        address lp = _stake(1_000);
        bytes memory notOpened = abi.encodeWithSelector(PocketUpgradeable.PocketNotOpened.selector, LOAN);

        vm.prank(address(minter));
        vm.expectRevert(notOpened);
        pocket.release(LOAN, 1, 0);

        vm.prank(address(minter));
        vm.expectRevert(notOpened);
        pocket.unrelease(LOAN, 0, 0);

        vm.prank(address(loanRegistry));
        vm.expectRevert(notOpened);
        pocket.burn(LOAN, 1);

        vm.prank(lp);
        vm.expectRevert(notOpened);
        pocket.claim(LOAN);

        vm.expectRevert(notOpened);
        pocket.claimable(LOAN, lp);

        vm.expectRevert(notOpened);
        pocket.pocket(LOAN);
    }

    function test_claimPausedAndWhitelisted() public {
        address a = _stake(1_000);
        _default(500);
        _recover(100, 0);

        vm.prank(pauser);
        pocket.pause();

        vm.prank(a);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        pocket.claim(LOAN);

        _recover(100, 0);

        vm.prank(pauser);
        pocket.unpause();

        vm.prank(whitelistAdmin);
        whitelistRegistry.disallow(a);

        vm.prank(a);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, a));
        pocket.claim(LOAN);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(a);

        assertEq(_claim(a), 200);
    }

    function test_emptySnapshotPaysNothing() public {
        assertEq(_default(500), 0);
        _recover(0, 50);

        vm.roll(201);
        address lp = _stake(1_000);

        assertEq(pocket.pocket(LOAN).supplyAtSnapshot, 0);
        assertEq(pocket.claimable(LOAN, lp), 0);
        assertEq(_claim(lp), 0);
    }

    function test_largeAmounts() public {
        uint256 big = 1e30;
        address a = _stake(big);
        _default(big);
        _recover(big, 0);

        assertEq(pocket.claimable(LOAN, a), big);
    }

    function testFuzz_claimsAreProRataAndBacked(uint256 stakeA, uint256 stakeB, uint256 principal, uint256 interest)
        public
    {
        stakeA = bound(stakeA, 1, 1e30);
        stakeB = bound(stakeB, 1, 1e30);

        address a = _stake(stakeA);
        address b = _stake(stakeB);
        uint256 moved = _default(stakeA + stakeB);

        principal = bound(principal, 0, moved);
        interest = bound(interest, 0, 1e30);
        _recover(principal, interest);

        uint256 releasedTotal = principal + interest;
        uint256 paidA = _claim(a);
        uint256 paidB = _claim(b);

        assertEq(paidA, Math.mulDiv(releasedTotal, stakeA, stakeA + stakeB));
        assertEq(paidB, Math.mulDiv(releasedTotal, stakeB, stakeA + stakeB));
        assertLe(paidA + paidB, releasedTotal);
        _assertBacked();
    }

    function _stake(uint256 amount) private returns (address lp) {
        lp = makeAddr(string.concat("lp", vm.toString(++stakers)));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(lp);

        deal(address(plUsd), lp, amount, true);

        vm.startPrank(lp);
        plUsd.approve(address(sPlUsd), amount);
        sPlUsd.deposit(amount, lp);
        vm.stopPrank();
    }

    function _default(uint256 amount) private returns (uint256 moved) {
        vm.roll(200);
        vm.prank(address(loanRegistry));
        return sPlUsd.carveOut(LOAN, amount);
    }

    function _recover(uint256 principal, uint256 interest) private returns (uint256 released) {
        if (interest != 0) {
            deal(address(plUsd), address(pocket), plUsd.balanceOf(address(pocket)) + interest, true);
        }

        vm.prank(address(minter));
        return pocket.release(LOAN, principal, interest);
    }

    function _claim(address holder) private returns (uint256 paid) {
        vm.prank(holder);
        return pocket.claim(LOAN);
    }

    function _assertBacked() private view {
        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(LOAN);
        assertEq(plUsd.balanceOf(address(pocket)), pocketData.held + pocketData.releasedTotal - pocketData.claimedTotal);
    }
}
