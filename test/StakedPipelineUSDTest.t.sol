// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {StakedPipelineUSD} from "../src/StakedPipelineUSD.sol";
import {PocketUpgradeable} from "../src/pocket/PocketUpgradeable.sol";
import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract StakedPipelineUSDTest is PipelineTestSetUp {
    uint256 constant UNIT = 1e6;

    address public user = makeAddr("user");

    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(user);

        deal(address(plUsd), user, 1_000_000_000, true);

        vm.roll(100);
    }

    function test_setUp() public view {
        assertEq(sPlUsd.authority(), address(authority));
        assertEq(sPlUsd.asset(), address(plUsd));
        assertEq(sPlUsd.pocket(), address(pocket));
    }

    function test_notWhitelistedWithdrawalRecipient(address recipient) public {
        vm.assume(!whitelistRegistry.isAllowed(recipient) && recipient != address(0));

        uint256 depositAmount = plUsd.balanceOf(user);

        vm.prank(user);
        plUsd.approve(address(sPlUsd), depositAmount);

        vm.prank(user);
        uint256 amount = sPlUsd.deposit(depositAmount, user);

        vm.prank(user);
        sPlUsd.transfer(recipient, amount);

        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, recipient)
        );
        sPlUsd.redeem(amount, recipient, recipient);

        vm.prank(recipient);
        sPlUsd.transfer(user, amount);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, recipient)
        );
        sPlUsd.redeem(amount, recipient, user);
    }

    function test_pauses() public {
        uint256 depositAmount = plUsd.balanceOf(user);

        vm.prank(user);
        plUsd.approve(address(sPlUsd), depositAmount);

        vm.prank(user);
        uint256 shares = sPlUsd.deposit(depositAmount, user);

        vm.prank(pauser);
        sPlUsd.pause();
        assert(sPlUsd.paused());

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        sPlUsd.deposit(1, user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        sPlUsd.mint(1, user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        sPlUsd.withdraw(1, user, user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        sPlUsd.redeem(shares, user, user);

        vm.prank(pauser);
        sPlUsd.unpause();
        assert(!sPlUsd.paused());

        vm.prank(user);
        sPlUsd.redeem(shares, user, user);
    }

    function test_balanceHistory() public {
        uint256 shares = _stake(user, 100 * UNIT);
        address other = makeAddr("other");

        vm.roll(110);
        vm.prank(user);
        sPlUsd.transfer(other, shares / 4);

        vm.roll(120);
        vm.prank(user);
        sPlUsd.redeem(shares / 4, user, user);

        assertEq(sPlUsd.balanceAt(user, 99), 0);
        assertEq(sPlUsd.balanceAt(user, 100), shares);
        assertEq(sPlUsd.balanceAt(user, 109), shares);
        assertEq(sPlUsd.balanceAt(user, 110), shares - shares / 4);
        assertEq(sPlUsd.balanceAt(user, 120), shares / 2);
        assertEq(sPlUsd.balanceAt(user, 1_000), shares / 2);
        assertEq(sPlUsd.balanceAt(other, 109), 0);
        assertEq(sPlUsd.balanceAt(other, 110), shares / 4);
        assertEq(sPlUsd.totalSupplyAt(99), 0);
        assertEq(sPlUsd.totalSupplyAt(110), shares);
        assertEq(sPlUsd.totalSupplyAt(120), shares - shares / 4);
    }

    function test_balanceHistoryKeepsTheLastChangeInABlock() public {
        _stake(user, 100 * UNIT);
        _stake(user, 50 * UNIT);

        assertEq(sPlUsd.balanceAt(user, 100), sPlUsd.balanceOf(user));
        assertEq(sPlUsd.balanceAt(user, 100), 150 * UNIT);
        assertEq(sPlUsd.balanceAt(user, 99), 0);
        assertEq(sPlUsd.totalSupplyAt(100), 150 * UNIT);
    }

    function test_balanceHistoryBeforeUpgrade() public {
        address legacy = makeAddr("legacy");
        address untouched = makeAddr("untouched");
        deal(address(sPlUsd), legacy, 1_000, true);
        deal(address(sPlUsd), untouched, 500, true);

        vm.roll(200);
        vm.prank(legacy);
        sPlUsd.transfer(untouched, 400);

        assertEq(sPlUsd.balanceAt(legacy, 150), 1_000);
        assertEq(sPlUsd.balanceAt(legacy, 200), 600);
        assertEq(sPlUsd.balanceAt(untouched, 150), 500);
        assertEq(sPlUsd.balanceAt(untouched, 200), 900);
        assertEq(sPlUsd.totalSupplyAt(150), 1_500);

        address dormant = makeAddr("dormant");
        deal(address(sPlUsd), dormant, 77, true);
        assertEq(sPlUsd.balanceAt(dormant, 150), 77);
    }

    function test_carveOut() public {
        uint256 shares = _stake(user, 100 * UNIT);

        vm.roll(150);
        vm.prank(pauser);
        sPlUsd.pause();

        vm.expectEmit(address(sPlUsd));
        emit StakedPipelineUSD.CarvedOut(7, 30 * UNIT, 30 * UNIT, 150);

        vm.prank(address(loanRegistry));
        uint256 moved = sPlUsd.carveOut(7, 30 * UNIT);

        assertEq(moved, 30 * UNIT);
        assertEq(plUsd.balanceOf(address(pocket)), 30 * UNIT);
        assertEq(sPlUsd.totalAssets(), 70 * UNIT);
        assertEq(sPlUsd.balanceAt(user, 150), shares);
        _assertOpened(7, 30 * UNIT, 150, shares);
    }

    function test_carveOutCapsAtTotalAssets() public {
        uint256 shares = _stake(user, 10 * UNIT);

        vm.prank(address(loanRegistry));
        uint256 moved = sPlUsd.carveOut(1, 25 * UNIT);

        assertEq(moved, 10 * UNIT);
        assertEq(sPlUsd.totalAssets(), 0);
        _assertOpened(1, 10 * UNIT, 100, shares);
    }

    function test_carveOutFreezesShares() public {
        uint256 shares = _stake(user, 100 * UNIT);
        address other = makeAddr("other");
        _stake(other, 10 * UNIT);

        vm.roll(150);
        vm.prank(user);
        sPlUsd.redeem(shares / 10, user, user);
        uint256 atSnapshot = sPlUsd.balanceOf(user);

        vm.prank(address(loanRegistry));
        sPlUsd.carveOut(7, 30 * UNIT);

        assertEq(sPlUsd.balanceAt(user, 150), atSnapshot);

        bytes4 frozen = StakedPipelineUSD.StakedPipelineUSDCarveOutBlock.selector;

        vm.startPrank(user);
        vm.expectRevert(frozen);
        sPlUsd.redeem(UNIT, user, user);
        vm.expectRevert(frozen);
        sPlUsd.withdraw(UNIT, user, user);
        vm.expectRevert(frozen);
        sPlUsd.transfer(other, UNIT);
        sPlUsd.approve(other, UNIT);
        vm.stopPrank();

        deal(address(plUsd), other, 2 * UNIT, true);

        vm.startPrank(other);
        vm.expectRevert(frozen);
        sPlUsd.transferFrom(user, other, UNIT);
        plUsd.approve(address(sPlUsd), 2 * UNIT);
        vm.expectRevert(frozen);
        sPlUsd.deposit(UNIT, other);
        vm.expectRevert(frozen);
        sPlUsd.mint(UNIT, other);
        vm.stopPrank();

        vm.prank(address(minter));
        vm.expectRevert(frozen);
        sPlUsd.burnShares(user, UNIT);

        vm.prank(address(loanRegistry));
        sPlUsd.carveOut(8, UNIT);

        vm.roll(151);
        vm.prank(user);
        sPlUsd.redeem(UNIT, user, user);

        assertEq(sPlUsd.balanceAt(user, 150), atSnapshot);
        assertEq(sPlUsd.balanceOf(user), atSnapshot - UNIT);
    }

    function test_carveOutNotConfigured() public {
        StakedPipelineUSD implementation = new StakedPipelineUSD();
        bytes memory data = abi.encodeCall(StakedPipelineUSD.initialize, (IERC20(address(plUsd)), address(authority)));
        StakedPipelineUSD bare = StakedPipelineUSD(address(new ERC1967Proxy(address(implementation), data)));

        vm.prank(admin);
        vm.expectRevert(StakedPipelineUSD.StakedPipelineUSDNotConfigured.selector);
        bare.carveOut(0, 1);
    }

    function test_pull() public {
        _stake(user, 10 * UNIT);

        vm.prank(pauser);
        sPlUsd.pause();

        vm.expectEmit(address(sPlUsd));
        emit StakedPipelineUSD.Pulled(4 * UNIT, 4 * UNIT);

        vm.prank(address(minter));
        assertEq(sPlUsd.pull(4 * UNIT), 4 * UNIT);

        vm.prank(address(minter));
        assertEq(sPlUsd.pull(20 * UNIT), 6 * UNIT);

        assertEq(plUsd.balanceOf(address(minter)), 10 * UNIT);
        assertEq(sPlUsd.totalAssets(), 0);
    }

    function test_burnShares() public {
        uint256 shares = _stake(user, 100 * UNIT);

        vm.roll(130);
        vm.prank(pauser);
        sPlUsd.pause();

        vm.expectEmit(address(sPlUsd));
        emit IERC4626.Withdraw(address(minter), address(minter), user, 50 * UNIT, shares / 2);
        vm.expectEmit(address(sPlUsd));
        emit StakedPipelineUSD.SharesBurned(user, shares / 2, 50 * UNIT);

        vm.prank(address(minter));
        uint256 assets = sPlUsd.burnShares(user, shares / 2);

        assertEq(assets, 50 * UNIT);
        assertEq(sPlUsd.balanceOf(user), shares - shares / 2);
        assertEq(plUsd.balanceOf(address(minter)), 50 * UNIT);
        assertEq(sPlUsd.balanceAt(user, 129), shares);
        assertEq(sPlUsd.balanceAt(user, 130), shares - shares / 2);
        assertEq(sPlUsd.totalSupplyAt(130), shares - shares / 2);
    }

    function test_setPocket() public {
        address newPocket = makeAddr("newPocket");

        vm.expectEmit(address(sPlUsd));
        emit StakedPipelineUSD.PocketSet(newPocket);

        vm.prank(admin);
        sPlUsd.setPocket(newPocket);
        assertEq(sPlUsd.pocket(), newPocket);

        vm.startPrank(admin);
        vm.expectRevert(StakedPipelineUSD.StakedPipelineUSDZeroAddress.selector);
        sPlUsd.setPocket(address(0));
        vm.expectRevert(StakedPipelineUSD.StakedPipelineUSDSameValue.selector);
        sPlUsd.setPocket(newPocket);
        vm.stopPrank();
    }

    function test_loanDefaultCarvesOut() public {
        uint256 shares = _stake(user, 100 * UNIT);

        ILoanRegistry.ImmutableLoanData memory economics = ILoanRegistry.ImmutableLoanData({
            borrowerRef: bytes32(0),
            originalFacilitySize: 40 * UNIT,
            originalSeniorTranche: 40 * UNIT,
            originalEquityTranche: 0,
            originalOfftakerPrice: 40 * UNIT,
            seniorInterestRate: 100_000,
            originationDate: uint64(vm.getBlockTimestamp()),
            originalMaturityDate: uint64(vm.getBlockTimestamp() + 365 days)
        });

        vm.prank(loanRegistryManager);
        uint256 loanId = loanRegistry.drawLoan("metadataURI", economics);

        vm.prank(address(minter));
        loanRegistry.disburse(loanId, 30 * UNIT);

        vm.roll(150);
        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId);

        assertEq(plUsd.balanceOf(address(pocket)), 30 * UNIT);
        assertEq(sPlUsd.totalAssets(), 70 * UNIT);
        _assertOpened(loanId, 30 * UNIT, 150, shares);

        vm.prank(user);
        vm.expectRevert(StakedPipelineUSD.StakedPipelineUSDCarveOutBlock.selector);
        sPlUsd.redeem(UNIT, user, user);
    }

    function _stake(address lp, uint256 amount) private returns (uint256 shares) {
        if (!whitelistRegistry.isAllowed(lp)) {
            vm.prank(whitelistAdmin);
            whitelistRegistry.allow(lp);
        }
        deal(address(plUsd), lp, amount, true);

        vm.startPrank(lp);
        plUsd.approve(address(sPlUsd), amount);
        shares = sPlUsd.deposit(amount, lp);
        vm.stopPrank();
    }

    function _assertOpened(uint256 loanId, uint256 amount, uint256 snapshotBlock, uint256 supplyAtSnapshot)
        private
        view
    {
        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(loanId);
        assertEq(pocketData.held, amount);
        assertEq(pocketData.snapshotBlock, snapshotBlock);
        assertEq(pocketData.supplyAtSnapshot, supplyAtSnapshot);
    }
}
