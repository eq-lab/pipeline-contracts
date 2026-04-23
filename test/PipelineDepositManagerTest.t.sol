// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {RateLimiterUpgradeable} from "../src/depositManager/RateLimiterUpgradeable.sol";
import {DepositManagerUpgradeable} from "../src/depositManager/DepositManagerUpgradeable.sol";
import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineDepositManagerTest is PipelineTestSetUp {
    address public user = makeAddr("user");

    uint256 usdcAmount = 1_000_000_000_000;

    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(address(0));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(user);

        deal(address(usdc), user, usdcAmount);
    }

    function test_setUp() public view {
        assertEq(depositManager.authority(), address(authority));
        assertEq(depositManager.custodian(), address(custodian));
        assertEq(depositManager.usdc(), address(usdc));
        assertEq(depositManager.plUsd(), address(plUsd));

        assertEq(depositManager.minDeposit(), minDeposit);

        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfig = depositManager.rateLimitConfig();
        assertEq(rateLimitConfig.txLimit, rateLimitConfigDefault.txLimit);
        assertEq(rateLimitConfig.windowLimit, rateLimitConfigDefault.windowLimit);
        assertEq(rateLimitConfig.window, rateLimitConfigDefault.window);
        assertEq(rateLimitConfig.shift, rateLimitConfigDefault.shift);
    }

    function test_deposit(uint256 amount) public {
        vm.assume(amount >= minDeposit && amount <= usdcAmount);

        uint256 userUsdcBalanceBefore = usdc.balanceOf(user);
        uint256 userPlUsdBalanceBefore = plUsd.balanceOf(user);
        uint256 custodianUsdcBalanceBefore = usdc.balanceOf(custodian);

        vm.prank(user);
        usdc.approve(address(depositManager), amount);

        vm.prank(user);
        depositManager.deposit(amount);

        assertEq(usdc.balanceOf(address(depositManager)), 0);
        assertEq(plUsd.balanceOf(address(depositManager)), 0);

        assertEq(usdc.balanceOf(user), userUsdcBalanceBefore - amount);
        assertEq(plUsd.balanceOf(address(user)), userPlUsdBalanceBefore + amount);

        assertEq(usdc.balanceOf(custodian), custodianUsdcBalanceBefore + amount);

        assertEq(depositManager.lastMintTimestamp(), block.timestamp);
    }

    function test_rateLimits() public {
        uint256 currentWindowCumulativeMint = depositManager.windowCumulativeMint();
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfig = depositManager.rateLimitConfig();

        deal(address(usdc), user, rateLimitConfig.windowLimit * 2);
        vm.prank(user);
        usdc.approve(address(depositManager), rateLimitConfig.windowLimit * 2);

        uint256 loops = (rateLimitConfig.windowLimit - currentWindowCumulativeMint) / rateLimitConfig.txLimit;
        assertNotEq(loops, 0);

        for (uint256 i; i < loops;) {
            vm.prank(user);
            depositManager.deposit(rateLimitConfig.txLimit);

            assertEq(depositManager.lastMintTimestamp(), block.timestamp);
            assertEq(
                depositManager.windowCumulativeMint(), currentWindowCumulativeMint + rateLimitConfig.txLimit * (i + 1)
            );

            unchecked {
                ++i;
            }
        }

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterExceedsWindowLimit.selector));
        depositManager.deposit(rateLimitConfig.txLimit);

        uint256 currentWindowIndex = (block.timestamp + rateLimitConfig.shift) / rateLimitConfig.window;
        uint256 nextWindowTimestamp = (currentWindowIndex + 1) * rateLimitConfig.window - rateLimitConfig.shift;

        vm.warp(nextWindowTimestamp - 1);
        assertNotEq(depositManager.windowCumulativeMint(), 0);

        skip(1);
        assertEq(depositManager.windowCumulativeMint(), 0);

        vm.prank(user);
        depositManager.deposit(rateLimitConfig.txLimit);
    }

    function test_nonWhitelistedUserRevert(address nonWhitelisted) public {
        vm.assume(!whitelistRegistry.isAllowed(nonWhitelisted));

        uint256 minDeposit = depositManager.minDeposit();
        deal(address(usdc), nonWhitelisted, minDeposit);

        vm.prank(nonWhitelisted);
        usdc.approve(address(depositManager), minDeposit);

        vm.prank(nonWhitelisted);
        vm.expectRevert(
            abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, nonWhitelisted)
        );
        depositManager.deposit(minDeposit);
    }

    function test_depositReverts(uint256 amount) public {
        vm.assume(amount < depositManager.minDeposit() && amount != 0);

        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfig = depositManager.rateLimitConfig();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterExceedsTxLimit.selector));
        depositManager.deposit(rateLimitConfig.txLimit + amount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerZeroAmount.selector));
        depositManager.deposit(0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerLessThanMinAmount.selector));
        depositManager.deposit(amount);
    }

    function test_setMinDeposit(uint256 newMinDeposit) public {
        vm.assume(newMinDeposit != depositManager.minDeposit());

        vm.prank(depositManagerManager);
        depositManager.setMinDeposit(newMinDeposit);

        assertEq(depositManager.minDeposit(), newMinDeposit);
    }

    function test_setMinDepositReverts() public {
        uint256 newMinDeposit = depositManager.minDeposit();

        vm.prank(depositManagerManager);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerSameValue.selector));
        depositManager.setMinDeposit(newMinDeposit);
    }

    function test_setCustodian(address newCustodian) public {
        vm.assume(newCustodian != depositManager.custodian() && newCustodian != address(0));

        vm.prank(depositManagerManager);
        depositManager.setCustodian(newCustodian);

        assertEq(depositManager.custodian(), newCustodian);
    }

    function test_setCustodianReverts() public {
        address newCustodian = depositManager.custodian();

        vm.prank(depositManagerManager);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerSameValue.selector));
        depositManager.setCustodian(newCustodian);

        vm.prank(depositManagerManager);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerZeroAddress.selector));
        depositManager.setCustodian(address(0));
    }

    function test_increaseTxLimit(uint256 newTxLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newTxLimit > rateLimitConfigBefore.txLimit);

        vm.prank(depositManagerManager);
        depositManager.increaseTxLimit(newTxLimit);

        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfig = depositManager.rateLimitConfig();
        assertEq(rateLimitConfig.txLimit, newTxLimit);
        assertEq(rateLimitConfig.windowLimit, rateLimitConfigBefore.windowLimit);
        assertEq(rateLimitConfig.window, rateLimitConfigBefore.window);
        assertEq(rateLimitConfig.shift, rateLimitConfigBefore.shift);
    }

    function test_increaseTxLimitReverts(uint256 newTxLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newTxLimit <= rateLimitConfigBefore.txLimit);

        vm.prank(depositManagerManager);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterWrongValue.selector));
        depositManager.increaseTxLimit(newTxLimit);
    }

    function test_decreaseTxLimit(uint256 newTxLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newTxLimit < rateLimitConfigBefore.txLimit);

        vm.prank(depositManagerManager);
        depositManager.decreaseTxLimit(newTxLimit);

        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfig = depositManager.rateLimitConfig();
        assertEq(rateLimitConfig.txLimit, newTxLimit);
        assertEq(rateLimitConfig.windowLimit, rateLimitConfigBefore.windowLimit);
        assertEq(rateLimitConfig.window, rateLimitConfigBefore.window);
        assertEq(rateLimitConfig.shift, rateLimitConfigBefore.shift);
    }

    function test_decreaseTxLimitReverts(uint256 newTxLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newTxLimit >= rateLimitConfigBefore.txLimit);

        vm.prank(depositManagerManager);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterWrongValue.selector));
        depositManager.decreaseTxLimit(newTxLimit);
    }

    function test_increaseWindowLimit(uint256 newWindowLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newWindowLimit > rateLimitConfigBefore.windowLimit);

        vm.prank(depositManagerManager);
        depositManager.increaseWindowLimit(newWindowLimit);

        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfig = depositManager.rateLimitConfig();
        assertEq(rateLimitConfig.windowLimit, newWindowLimit);
        assertEq(rateLimitConfig.txLimit, rateLimitConfigBefore.txLimit);
        assertEq(rateLimitConfig.window, rateLimitConfigBefore.window);
        assertEq(rateLimitConfig.shift, rateLimitConfigBefore.shift);
    }

    function test_increaseWindowLimitReverts(uint256 newWindowLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newWindowLimit <= rateLimitConfigBefore.windowLimit);

        vm.prank(depositManagerManager);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterWrongValue.selector));
        depositManager.increaseWindowLimit(newWindowLimit);
    }

    function test_decreaseWindowLimit(uint256 newWindowLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newWindowLimit < rateLimitConfigBefore.windowLimit);

        vm.prank(depositManagerManager);
        depositManager.decreaseWindowLimit(newWindowLimit);

        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfig = depositManager.rateLimitConfig();
        assertEq(rateLimitConfig.windowLimit, newWindowLimit);
        assertEq(rateLimitConfig.txLimit, rateLimitConfigBefore.txLimit);
        assertEq(rateLimitConfig.window, rateLimitConfigBefore.window);
        assertEq(rateLimitConfig.shift, rateLimitConfigBefore.shift);
    }

    function test_decreaseWindowLimitReverts(uint256 newWindowLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newWindowLimit >= rateLimitConfigBefore.windowLimit);

        vm.prank(depositManagerManager);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterWrongValue.selector));
        depositManager.decreaseWindowLimit(newWindowLimit);
    }
}
