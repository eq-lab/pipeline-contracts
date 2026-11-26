// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {VerifiedRequestsQueueUpgradeable} from "../src/requestsQueue/VerifiedRequestsQueueUpgradeable.sol";
import {WithdrawalQueueUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueUpgradeable.sol";
import {WithdrawalQueueShutdownUpgradeable} from "../src/withdrawalQueue/WithdrawalQueueShutdownUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineWithdrawalQueueTest is PipelineTestSetUp {
    address public user = makeAddr("user");

    function setUp() public override {
        super.setUp();

        deal(address(plUsd), user, type(uint256).max / 2);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(user);

        vm.prank(tokenHolder);
        usdc.approve(address(withdrawalQueue), type(uint256).max);
    }

    function test_setUp() public view {
        assertEq(address(withdrawalQueue.plUsd()), address(plUsd));
        assertEq(address(withdrawalQueue.usdc()), address(usdc));
        assertEq(withdrawalQueue.assetHolder(), tokenHolder);
        assertEq(withdrawalQueue.authority(), address(authority));
        assertEq(withdrawalQueue.verifier(), withdrawalVerifier);
        assertEq(withdrawalQueue.rate(), withdrawalQueue.RATE_ONE());

        uint256 conversionAmount = 1e18;
        assertEq(withdrawalQueue.convertToShares(conversionAmount), conversionAmount);
        assertEq(withdrawalQueue.convertToAssets(conversionAmount), conversionAmount);
    }

    function testFuzz_requestWithdrawal(uint256 withdrawalAmount) public {
        uint256 userBalanceBefore = plUsd.balanceOf(user);
        vm.assume(withdrawalAmount <= userBalanceBefore && withdrawalAmount != 0);

        uint256 queueBalanceBefore = plUsd.balanceOf(address(withdrawalQueue));
        uint256 nextRequestId = withdrawalQueue.nextRequestId();
        (uint256 queuedBefore, uint256 claimedBefore) = withdrawalQueue.queueMetadata();

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), withdrawalAmount);

        vm.prank(user);
        (uint256 requestId, uint256 queued) = withdrawalQueue.requestWithdrawal(withdrawalAmount);

        assertEq(requestId, nextRequestId);
        assertEq(queued, queuedBefore + withdrawalAmount);

        assertEq(plUsd.balanceOf(user), userBalanceBefore - withdrawalAmount);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), queueBalanceBefore + withdrawalAmount);

        (uint256 queuedAfter, uint256 claimedAfter) = withdrawalQueue.queueMetadata();
        assertEq(withdrawalQueue.nextRequestId(), requestId + 1);
        assertEq(queuedAfter, queuedBefore + withdrawalAmount);
        assertEq(claimedAfter, claimedBefore);

        VerifiedRequestsQueueUpgradeable.Request memory request = withdrawalQueue.requests(requestId);
        assertEq(request.user, user);
        assertEq(request.amount, withdrawalAmount);
        assert(!request.claimed);
        assertEq(request.timestamp, block.timestamp);
        assertEq(withdrawalQueue.withdrawalRequestQueued(requestId), queuedAfter);
    }

    function testFuzz_increaseClaimableAmount(uint256 amount) public {
        uint256 claimableBefore = withdrawalQueue.claimableAmount();
        vm.assume(amount <= type(uint256).max - claimableBefore && amount != 0);

        deal(address(usdc), tokenHolder, amount);

        assertEq(withdrawalQueue.claimableAmount(), claimableBefore + amount);
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

        VerifiedRequestsQueueUpgradeable.Request memory request = withdrawalQueue.requests(requestId);
        assert(request.claimed);
    }

    function test_pauses() public {
        vm.prank(queueManager);
        withdrawalQueue.pause();
        assert(withdrawalQueue.paused());

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        withdrawalQueue.requestWithdrawal(1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        withdrawalQueue.claimWithdrawal(0, "");

        vm.prank(queueManager);
        withdrawalQueue.unpause();
        assert(!withdrawalQueue.paused());
    }

    function testFuzz_setAssetHolder(address newAssetHolder) public {
        vm.assume(newAssetHolder != address(0) && newAssetHolder != withdrawalQueue.assetHolder());

        vm.prank(queueManager);
        withdrawalQueue.setAssetHolder(newAssetHolder);

        assertEq(withdrawalQueue.assetHolder(), newAssetHolder);
    }

    function testFuzz_setRate(uint256 newRate, uint256 convertAmount) public {
        uint256 one = withdrawalQueue.RATE_ONE();
        vm.assume(convertAmount < type(uint128).max && newRate <= one && newRate != 0);

        vm.expectEmit(address(withdrawalQueue));
        emit WithdrawalQueueShutdownUpgradeable.RateSet(newRate);

        vm.prank(queueManager);
        withdrawalQueue.setRate(newRate);

        assertEq(withdrawalQueue.rate(), newRate);
        assertEq(withdrawalQueue.convertToAssets(convertAmount), Math.mulDiv(convertAmount, newRate, one));
        assertEq(withdrawalQueue.convertToShares(convertAmount), Math.mulDiv(convertAmount, one, newRate));
    }

    function test_setRate_canBeCalledRepeatedly() public {
        uint256 one = withdrawalQueue.RATE_ONE();
        uint256[5] memory rates = [one / 4, one / 8, one / 2, one, one / 3];

        for (uint256 i; i < rates.length; ++i) {
            vm.expectEmit(address(withdrawalQueue));
            emit WithdrawalQueueShutdownUpgradeable.RateSet(rates[i]);

            vm.prank(queueManager);
            withdrawalQueue.setRate(rates[i]);

            assertEq(withdrawalQueue.rate(), rates[i]);
        }

        vm.prank(queueManager);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalQueueShutdownUpgradeable.WithdrawalQueueShutdownInvalidRate.selector)
        );
        withdrawalQueue.setRate(one + 1);

        vm.prank(queueManager);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalQueueShutdownUpgradeable.WithdrawalQueueShutdownInvalidRate.selector)
        );
        withdrawalQueue.setRate(0);

        assertEq(withdrawalQueue.rate(), one / 3);
    }

    function test_queuedRequestPaysRateInForceAtClaim() public {
        uint256 one = withdrawalQueue.RATE_ONE();
        uint256 shares = 100_000_000;

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), shares);

        vm.prank(user);
        (uint256 requestId,) = withdrawalQueue.requestWithdrawal(shares);
        bytes memory signature = _createSignature(requestId, user, shares, withdrawalVerifierPrivateKey);

        deal(address(usdc), tokenHolder, shares / 2);
        assert(!withdrawalQueue.isClaimable(requestId));

        vm.prank(queueManager);
        withdrawalQueue.setRate(one / 2);
        assert(withdrawalQueue.isClaimable(requestId));

        vm.prank(queueManager);
        withdrawalQueue.setRate(one);
        assert(!withdrawalQueue.isClaimable(requestId));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueTooEarly.selector));
        withdrawalQueue.claimWithdrawal(requestId, signature);

        vm.prank(queueManager);
        withdrawalQueue.setRate(one / 4);

        vm.prank(user);
        assertEq(withdrawalQueue.claimWithdrawal(requestId, signature), shares / 4);

        assertEq(usdc.balanceOf(user), shares / 4);
        assertEq(usdc.balanceOf(tokenHolder), shares / 4);
        (, uint256 totalClaimed) = withdrawalQueue.queueMetadata();
        assertEq(totalClaimed, shares);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), 0);
    }

    function test_claimWithdrawal_revertsForDisallowedUser() public {
        uint256 amount = 400_000_000;
        deal(address(usdc), tokenHolder, amount);

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), amount);

        vm.prank(user);
        (uint256 requestId,) = withdrawalQueue.requestWithdrawal(amount);
        bytes memory signature = _createSignature(requestId, user, amount, withdrawalVerifierPrivateKey);

        vm.prank(whitelistAdmin);
        whitelistRegistry.disallow(user);

        assert(!withdrawalQueue.isClaimable(requestId));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueUserFrozen.selector, user));
        withdrawalQueue.claimWithdrawal(requestId, signature);

        assert(!withdrawalQueue.requests(requestId).claimed);
        (, uint256 totalClaimed) = withdrawalQueue.queueMetadata();
        assertEq(totalClaimed, 0);
        assertEq(usdc.balanceOf(user), 0);
        assertEq(usdc.balanceOf(tokenHolder), amount);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), amount);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(user);

        assert(withdrawalQueue.isClaimable(requestId));

        vm.prank(user);
        assertEq(withdrawalQueue.claimWithdrawal(requestId, signature), amount);

        assertEq(usdc.balanceOf(user), amount);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), 0);
    }

    function test_claimWithdrawal_allowsDisallowedUserWhenWhitelistDisabled() public {
        uint256 amount = 400_000_000;
        deal(address(usdc), tokenHolder, amount);

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), amount);

        vm.prank(user);
        (uint256 requestId,) = withdrawalQueue.requestWithdrawal(amount);
        bytes memory signature = _createSignature(requestId, user, amount, withdrawalVerifierPrivateKey);

        vm.prank(whitelistAdmin);
        whitelistRegistry.disallow(user);

        vm.prank(whitelistAdmin);
        plUsd.disableWhitelist();

        assert(withdrawalQueue.isClaimable(requestId));

        vm.prank(user);
        assertEq(withdrawalQueue.claimWithdrawal(requestId, signature), amount);
        assertEq(usdc.balanceOf(user), amount);
    }

    function test_frozenRequestKeepsReserveButDoesNotBlockOthers() public {
        uint256 frozenAmount = 300_000_000;
        uint256 otherAmount = 200_000_000;

        address other = makeAddr("other");
        deal(address(plUsd), other, otherAmount);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(other);

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), frozenAmount);

        vm.prank(user);
        (uint256 frozenId,) = withdrawalQueue.requestWithdrawal(frozenAmount);

        vm.prank(other);
        plUsd.approve(address(withdrawalQueue), otherAmount);

        vm.prank(other);
        (uint256 otherId,) = withdrawalQueue.requestWithdrawal(otherAmount);

        bytes memory frozenSignature = _createSignature(frozenId, user, frozenAmount, withdrawalVerifierPrivateKey);
        bytes memory otherSignature = _createSignature(otherId, other, otherAmount, withdrawalVerifierPrivateKey);

        vm.prank(whitelistAdmin);
        whitelistRegistry.disallow(user);

        deal(address(usdc), tokenHolder, otherAmount);
        assert(!withdrawalQueue.isClaimable(otherId));

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueTooEarly.selector));
        withdrawalQueue.claimWithdrawal(otherId, otherSignature);

        deal(address(usdc), tokenHolder, otherAmount + frozenAmount);
        assert(withdrawalQueue.isClaimable(otherId));

        vm.prank(other);
        assertEq(withdrawalQueue.claimWithdrawal(otherId, otherSignature), otherAmount);
        assertEq(usdc.balanceOf(other), otherAmount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueUserFrozen.selector, user));
        withdrawalQueue.claimWithdrawal(frozenId, frozenSignature);

        assertEq(usdc.balanceOf(tokenHolder), frozenAmount);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), frozenAmount);
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
        withdrawalQueue.setRate(one * 3 / 4);

        vm.prank(user);
        (uint256 postShutdownRequestId,) = withdrawalQueue.requestWithdrawal(withdrawalAmount);

        _claimWithAssertions(user, preShutdownRequestId, withdrawalAmount);
        _claimWithAssertions(user, postShutdownRequestId, withdrawalAmount);
    }

    function testFuzz_reverts(uint256 invalidRate) public {
        uint256 one = withdrawalQueue.RATE_ONE();
        vm.assume(invalidRate > one);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsQueueZeroAmount.selector)
        );
        withdrawalQueue.requestWithdrawal(0);

        vm.prank(queueManager);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueZeroAddress.selector));
        withdrawalQueue.setAssetHolder(address(0));

        vm.prank(queueManager);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueSameValue.selector));
        withdrawalQueue.setAssetHolder(tokenHolder);

        uint256 amount = 1_000;

        vm.prank(user);
        plUsd.approve(address(withdrawalQueue), amount);

        vm.prank(user);
        (uint256 requestId,) = withdrawalQueue.requestWithdrawal(amount);

        bytes memory signature = _createSignature(requestId, user, amount, withdrawalVerifierPrivateKey);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueUpgradeable.WithdrawalQueueTooEarly.selector));
        withdrawalQueue.claimWithdrawal(requestId, signature);

        deal(address(usdc), tokenHolder, amount);

        address wrongClaimant = makeAddr("wrongClaimant");

        vm.prank(wrongClaimant);
        vm.expectRevert(abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsInvalidSender.selector));
        withdrawalQueue.claimWithdrawal(requestId, signature);

        vm.prank(user);
        withdrawalQueue.claimWithdrawal(requestId, signature);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsQueueAlreadyClaimed.selector)
        );
        withdrawalQueue.claimWithdrawal(requestId, signature);

        vm.prank(queueManager);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalQueueShutdownUpgradeable.WithdrawalQueueShutdownInvalidRate.selector)
        );
        withdrawalQueue.setRate(invalidRate);

        vm.prank(queueManager);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalQueueShutdownUpgradeable.WithdrawalQueueShutdownInvalidRate.selector)
        );
        withdrawalQueue.setRate(0);
    }

    function _claimWithAssertions(address sender, uint256 requestId, uint256 withdrawalAmount) private {
        uint256 senderBalanceBefore = usdc.balanceOf(sender);
        uint256 tokenHolderBalanceBefore = usdc.balanceOf(address(tokenHolder));
        uint256 nextIdBefore = withdrawalQueue.nextRequestId();
        (uint256 queuedBefore, uint256 claimedBefore) = withdrawalQueue.queueMetadata();

        uint256 plSenderBalanceBefore = plUsd.balanceOf(sender);
        uint256 plQueueBalanceBefore = plUsd.balanceOf(address(withdrawalQueue));

        bytes memory signature = _createSignature(requestId, user, withdrawalAmount, withdrawalVerifierPrivateKey);

        vm.prank(sender);
        uint256 claimedAmount = withdrawalQueue.claimWithdrawal(requestId, signature);

        assert(!withdrawalQueue.isClaimable(requestId));

        assertEq(withdrawalQueue.convertToAssets(withdrawalAmount), claimedAmount);

        assertEq(usdc.balanceOf(sender), senderBalanceBefore + claimedAmount);
        assertEq(usdc.balanceOf(address(tokenHolder)), tokenHolderBalanceBefore - claimedAmount);

        assertEq(plUsd.balanceOf(sender), plSenderBalanceBefore);
        assertEq(plUsd.balanceOf(address(withdrawalQueue)), plQueueBalanceBefore - withdrawalAmount);

        (uint256 queuedAfter, uint256 claimedAfter) = withdrawalQueue.queueMetadata();
        assertEq(withdrawalQueue.nextRequestId(), nextIdBefore);
        assertEq(queuedBefore, queuedAfter);
        assertEq(claimedAfter, claimedBefore + withdrawalAmount);
    }

    function _createSignature(uint256 requestId, address claimant, uint256 amount, uint256 privateKey)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 structHash =
            keccak256(abi.encode(withdrawalQueue.VERIFIED_REQUESTS_TYPEHASH(), requestId, claimant, amount));

        bytes32 domainSeparator = withdrawalQueue.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
