// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {WithdrawalQueueUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueUpgradeable.sol";
import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

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

        vm.prank(tokenHolder);
        usdc.approve(address(withdrawalQueue), type(uint256).max);
    }

    function test_setUp() public view {
        assertEq(address(withdrawalQueue.fromToken()), address(plUsd));
        assertEq(address(withdrawalQueue.intoToken()), address(usdc));
        assertEq(withdrawalQueue.intoTokenHolder(), tokenHolder);
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

        uint256 claimableBefore = withdrawalQueue.claimable();

        vm.prank(queueManager);
        usdc.approve(address(withdrawalQueue), amount);

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

        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 tokenHolderBalanceBefore = usdc.balanceOf(address(tokenHolder));
        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadataBefore = withdrawalQueue.queueMetadata();

        uint256 plUserBalanceBefore = plUsd.balanceOf(user);
        uint256 plQueueBalanceBefore = plUsd.balanceOf(address(withdrawalQueue));

        vm.prank(user);
        uint256 claimedAmount = withdrawalQueue.claimWithdrawal(requestId);

        assert(!withdrawalQueue.isClaimable(requestId));

        assertEq(claimedAmount, withdrawalAmount);

        assertEq(usdc.balanceOf(user), userBalanceBefore + withdrawalAmount);
        assertEq(usdc.balanceOf(address(tokenHolder)), tokenHolderBalanceBefore - withdrawalAmount);

        assertEq(plUsd.balanceOf(user), plUserBalanceBefore);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), plQueueBalanceBefore - withdrawalAmount);

        WithdrawalQueueUpgradeable.WithdrawalQueueMetadata memory metadata = withdrawalQueue.queueMetadata();
        assertEq(metadata.nextWithdrawalIndex, metadataBefore.nextWithdrawalIndex);
        assertEq(metadata.queued, metadataBefore.queued);
        assertEq(metadata.claimed, metadataBefore.claimed + withdrawalAmount);

        WithdrawalQueueUpgradeable.WithdrawalRequest memory request = withdrawalQueue.withdrawalRequests(requestId);
        assert(request.claimed);
    }

    function test_changeIntoTokenHolder(address newTokenHolder) public {
        vm.assume(newTokenHolder != address(0) && newTokenHolder != withdrawalQueue.intoTokenHolder());

        vm.prank(queueManager);
        withdrawalQueue.changeIntoTokenHolder(newTokenHolder);

        assertEq(withdrawalQueue.intoTokenHolder(), newTokenHolder);
    }

    function test_reverts() public {
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
    }
}
