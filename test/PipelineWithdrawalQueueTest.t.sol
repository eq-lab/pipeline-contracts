// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {WithdrawalQueueUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueUpgradeable.sol";
import {WithdrawalQueueShutdownUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueShutdownUpgradeable.sol";
import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineWithdrawalQueueTest is PipelineTestSetUp {
    address public user = makeAddr("user");

    function setUp() public override {
        super.setUp();

        deal(address(plUsd), user, type(uint256).max / 2);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(user, type(uint256).max);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(address(0));

        vm.prank(tokenHolder);
        usdc.approve(address(withdrawalQueue), type(uint256).max);
    }

    function test_setUp() public view {
        assertEq(address(withdrawalQueue.fromToken()), address(plUsd));
        assertEq(address(withdrawalQueue.intoToken()), address(usdc));
        assertEq(withdrawalQueue.intoTokenHolder(), tokenHolder);
        assertEq(withdrawalQueue.authority(), address(authority));

        uint256 conversionAmount = 1e18;
        assertEq(withdrawalQueue.convertInto(conversionAmount), conversionAmount);
        assertEq(withdrawalQueue.convertFrom(conversionAmount), conversionAmount);
    }

    function testFuzz_requestWithdrawal(uint256 withdrawalAmount) public {
        uint256 userBalanceBefore = plUsd.balanceOf(user);
        vm.assume(withdrawalAmount <= userBalanceBefore && withdrawalAmount != 0);

        uint256 queueBalanceBefore = plUsd.balanceOf(address(withdrawalQueue));
        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadataBefore = withdrawalQueue.queueMetadata();

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), withdrawalAmount);

        vm.prank(user);
        (uint256 requestId, uint256 queued) = withdrawalQueue.requestWithdrawal(withdrawalAmount);

        assertEq(requestId, metadataBefore.nextWithdrawalIndex);
        assertEq(queued, metadataBefore.queued + withdrawalAmount);

        assertEq(plUsd.balanceOf(user), userBalanceBefore - withdrawalAmount);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), queueBalanceBefore + withdrawalAmount);

        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadata = withdrawalQueue.queueMetadata();
        assertEq(metadata.nextWithdrawalIndex, metadataBefore.nextWithdrawalIndex + 1);
        assertEq(metadata.queued, metadataBefore.queued + withdrawalAmount);
        assertEq(metadata.claimed, metadataBefore.claimed);

        WithdrawalQueueUpgradeable.WithdrawalRequest memory request =
            withdrawalQueue.withdrawalRequests(metadataBefore.nextWithdrawalIndex);
        assertEq(request.withdrawer, user);
        assertEq(request.amount, withdrawalAmount);
        assert(!request.claimed);
        assertEq(request.queued, metadata.queued);
        assertEq(request.timestamp, block.timestamp);
    }

    function testFuzz_increaseClaimable(uint256 amount) public {
        uint256 claimableBefore = withdrawalQueue.claimable();
        vm.assume(amount <= type(uint256).max - claimableBefore && amount != 0);

        deal(address(usdc), tokenHolder, amount);

        assertEq(withdrawalQueue.claimable(), claimableBefore + amount);
    }

    function testFuzz_claimWithdrawal(uint256 withdrawalAmount) public {
        vm.assume(withdrawalAmount <= plUsd.balanceOf(user) && withdrawalAmount != 0);

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), withdrawalAmount);

        vm.prank(user);
        (uint256 requestId,) = withdrawalQueue.requestWithdrawal(withdrawalAmount);

        assert(!withdrawalQueue.isClaimable(requestId));
        deal(address(usdc), tokenHolder, withdrawalAmount);
        assert(withdrawalQueue.isClaimable(requestId));

        _claimWithAssertions(user, requestId, withdrawalAmount);

        WithdrawalQueueUpgradeable.WithdrawalRequest memory request = withdrawalQueue.withdrawalRequests(requestId);
        assert(request.claimed);
    }

    function testFuzz_changeIntoTokenHolder(address newTokenHolder) public {
        vm.assume(newTokenHolder != address(0) && newTokenHolder != withdrawalQueue.intoTokenHolder());

        vm.prank(queueManager);
        withdrawalQueue.changeIntoTokenHolder(newTokenHolder);

        assertEq(withdrawalQueue.intoTokenHolder(), newTokenHolder);
    }

    function testFuzz_setShutdown(uint256 shutdownRate, uint256 convertAmount) public {
        uint256 one = withdrawalQueue.RATE_ONE();
        vm.assume(convertAmount < type(uint128).max && shutdownRate < one && shutdownRate != 0);

        vm.prank(queueManager);
        withdrawalQueue.setShutdownRate(shutdownRate);

        assertEq(withdrawalQueue.convertInto(convertAmount), Math.mulDiv(convertAmount, shutdownRate, one));
        assertEq(withdrawalQueue.convertFrom(convertAmount), Math.mulDiv(convertAmount, one, shutdownRate));
    }

    function testFuzz_shutdownClaim(uint256 withdrawalAmount) public {
        vm.assume(withdrawalAmount >= 1_000_000 && withdrawalAmount <= plUsd.balanceOf(user) / 2);

        deal(address(usdc), tokenHolder, 2 * withdrawalAmount);

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), 2 * withdrawalAmount);

        vm.prank(user);
        (uint256 preShutdownRequestId,) = withdrawalQueue.requestWithdrawal(withdrawalAmount);

        uint256 one = withdrawalQueue.RATE_ONE();
        vm.prank(queueManager);
        withdrawalQueue.setShutdownRate(one * 3 / 4);

        vm.prank(user);
        (uint256 postShutdownRequestId,) = withdrawalQueue.requestWithdrawal(withdrawalAmount);

        _claimWithAssertions(user, preShutdownRequestId, withdrawalAmount);
        _claimWithAssertions(user, postShutdownRequestId, withdrawalAmount);
    }

    function test_reverts(uint256 shutdownRate) public {
        uint256 one = withdrawalQueue.RATE_ONE();
        vm.assume(shutdownRate >= one);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueZeroAmount.selector));
        withdrawalQueue.requestWithdrawal(0);

        vm.prank(queueManager);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueZeroAddress.selector));
        withdrawalQueue.changeIntoTokenHolder(address(0));

        vm.prank(queueManager);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueSameValue.selector));
        withdrawalQueue.changeIntoTokenHolder(tokenHolder);

        uint256 amount = 1_000;

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), amount);

        vm.prank(user);
        (uint256 requestId,) = withdrawalQueue.requestWithdrawal(amount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueTooEarly.selector));
        withdrawalQueue.claimWithdrawal(requestId);

        deal(address(usdc), tokenHolder, amount);

        address wrongClaimant = makeAddr("wrongClaimant");
        vm.prank(wrongClaimant);
        vm.expectRevert(
            abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, wrongClaimant)
        );
        withdrawalQueue.claimWithdrawal(requestId);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(wrongClaimant, type(uint256).max);

        vm.prank(wrongClaimant);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueWrongClaimant.selector));
        withdrawalQueue.claimWithdrawal(requestId);

        vm.prank(user);
        withdrawalQueue.claimWithdrawal(requestId);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueAlreadyClaimed.selector));
        withdrawalQueue.claimWithdrawal(requestId);

        vm.prank(queueManager);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalQueueShutdownUpgradeable.WithdrawalQueueShutdownInvalidRate.selector)
        );
        withdrawalQueue.setShutdownRate(shutdownRate);

        vm.prank(queueManager);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalQueueShutdownUpgradeable.WithdrawalQueueShutdownInvalidRate.selector)
        );
        withdrawalQueue.setShutdownRate(0);

        vm.prank(queueManager);
        withdrawalQueue.setShutdownRate(one / 2);

        vm.prank(queueManager);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalQueueShutdownUpgradeable.WithdrawalQueueShutdownAlreadyInShutdown.selector)
        );
        withdrawalQueue.setShutdownRate(one / 2);
    }

    function _claimWithAssertions(address sender, uint256 requestId, uint256 withdrawalAmount) private {
        uint256 senderBalanceBefore = usdc.balanceOf(sender);
        uint256 tokenHolderBalanceBefore = usdc.balanceOf(address(tokenHolder));
        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadataBefore = withdrawalQueue.queueMetadata();

        uint256 plSenderBalanceBefore = plUsd.balanceOf(sender);
        uint256 plQueueBalanceBefore = plUsd.balanceOf(address(withdrawalQueue));

        vm.prank(sender);
        uint256 claimedAmount = withdrawalQueue.claimWithdrawal(requestId);

        assert(!withdrawalQueue.isClaimable(requestId));

        assertEq(withdrawalQueue.convertInto(withdrawalAmount), claimedAmount);

        assertEq(usdc.balanceOf(sender), senderBalanceBefore + claimedAmount);
        assertEq(usdc.balanceOf(address(tokenHolder)), tokenHolderBalanceBefore - claimedAmount);

        assertEq(plUsd.balanceOf(sender), plSenderBalanceBefore);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), plQueueBalanceBefore - withdrawalAmount);

        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadata = withdrawalQueue.queueMetadata();
        assertEq(metadata.nextWithdrawalIndex, metadataBefore.nextWithdrawalIndex);
        assertEq(metadata.queued, metadataBefore.queued);
        assertEq(metadata.claimed, metadataBefore.claimed + withdrawalAmount);
    }
}
