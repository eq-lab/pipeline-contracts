// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {WithdrawalQueueUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineWithdrawalQueueTest is PipelineTestSetUp {
    address public user = makeAddr("user");

    function setUp() public override {
        super.setUp();

        deal(address(plUsd), user, 1_000_000_000);
        deal(address(usdc), queueManager, 1_000_000_000);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowUser(user, type(uint256).max);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(address(0));
    }

    function test_setUp() public view {
        assertEq(address(withdrawalQueue.fromToken()), address(plUsd));
        assertEq(address(withdrawalQueue.intoToken()), address(usdc));
        assertEq(withdrawalQueue.authority(), address(authority));
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
        assertEq(metadata.claimable, metadataBefore.claimable);
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
        uint256 managerBalanceBefore = usdc.balanceOf(queueManager);
        vm.assume(amount <= managerBalanceBefore && amount != 0);

        uint256 queueBalanceBefore = usdc.balanceOf(address(withdrawalQueue));
        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadataBefore = withdrawalQueue.queueMetadata();

        vm.prank(queueManager);
        usdc.approve(address(withdrawalQueue), amount);

        vm.prank(queueManager);
        uint256 claimable = withdrawalQueue.fundWithdrawals(amount, queueManager);

        assertEq(claimable, metadataBefore.claimable + amount);

        assertEq(usdc.balanceOf(queueManager), managerBalanceBefore - amount);
        assertEq(usdc.balanceOf(address(withdrawalQueue)), queueBalanceBefore + amount);

        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadata = withdrawalQueue.queueMetadata();
        assertEq(metadata.nextWithdrawalIndex, metadataBefore.nextWithdrawalIndex);
        assertEq(metadata.queued, metadataBefore.queued);
        assertEq(metadata.claimable, metadataBefore.claimable + amount);
        assertEq(metadata.claimed, metadataBefore.claimed);
    }

    function testFuzz_claimWithdrawal(uint256 withdrawalAmount) public {
        vm.assume(withdrawalAmount <= plUsd.balanceOf(user) && withdrawalAmount != 0);

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), withdrawalAmount);

        vm.prank(user);
        (uint256 requestId,) = withdrawalQueue.requestWithdrawal(withdrawalAmount);

        vm.prank(queueManager);
        usdc.approve(address(withdrawalQueue), withdrawalAmount);

        vm.prank(queueManager);
        withdrawalQueue.fundWithdrawals(withdrawalAmount, queueManager);

        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 queueBalanceBefore = usdc.balanceOf(address(withdrawalQueue));
        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadataBefore = withdrawalQueue.queueMetadata();

        vm.prank(user);
        uint256 claimedAmount = withdrawalQueue.claimWithdrawal(requestId);

        assertEq(claimedAmount, withdrawalAmount);

        assertEq(usdc.balanceOf(user), userBalanceBefore + withdrawalAmount);
        assertEq(usdc.balanceOf(address(withdrawalQueue)), queueBalanceBefore - withdrawalAmount);

        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadata = withdrawalQueue.queueMetadata();
        assertEq(metadata.nextWithdrawalIndex, metadataBefore.nextWithdrawalIndex);
        assertEq(metadata.queued, metadataBefore.queued);
        assertEq(metadata.claimable, metadataBefore.claimable);
        assertEq(metadata.claimed, metadataBefore.claimed + withdrawalAmount);

        WithdrawalQueueUpgradeable.WithdrawalRequest memory request = withdrawalQueue.withdrawalRequests(requestId);
        assert(request.claimed);
    }

    function test_reverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueZeroAmount.selector));
        withdrawalQueue.requestWithdrawal(0);

        vm.prank(queueManager);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueZeroAmount.selector));
        withdrawalQueue.fundWithdrawals(0, queueManager);

        uint256 amount = 1_000;

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), amount);

        vm.prank(user);
        (uint256 requestId,) = withdrawalQueue.requestWithdrawal(amount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueTooEarly.selector));
        withdrawalQueue.claimWithdrawal(requestId);

        vm.prank(queueManager);
        usdc.approve(address(withdrawalQueue), amount);

        vm.prank(queueManager);
        withdrawalQueue.fundWithdrawals(amount, queueManager);

        address wrongClaimant = makeAddr("wrongClaimant");
        vm.prank(wrongClaimant);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueWrongClaimant.selector));
        withdrawalQueue.claimWithdrawal(requestId);

        vm.prank(user);
        withdrawalQueue.claimWithdrawal(requestId);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueAlreadyClaimed.selector));
        withdrawalQueue.claimWithdrawal(requestId);
    }
}
