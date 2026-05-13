// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {RateLimiterUpgradeable} from "../src/depositManager/RateLimiterUpgradeable.sol";
import {DepositManagerUpgradeable} from "../src/depositManager/DepositManagerUpgradeable.sol";
import {VerifiedRequestsQueueUpgradeable} from "../src/requestsQueue/VerifiedRequestsQueueUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineDepositManagerTest is PipelineTestSetUp {
    address public user = makeAddr("user");

    uint256 usdcAmount = 1_000_000_000_000;

    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(user);

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

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount >= minDeposit && amount <= usdcAmount);

        uint256 userUsdcBalanceBefore = usdc.balanceOf(user);
        uint256 userPlUsdBalanceBefore = plUsd.balanceOf(user);
        uint256 custodianUsdcBalanceBefore = usdc.balanceOf(custodian);

        vm.prank(user);
        usdc.approve(address(depositManager), amount);

        vm.prank(user);
        uint256 requestId = depositManager.deposit(amount);

        assertEq(usdc.balanceOf(address(depositManager)), 0);
        assertEq(plUsd.balanceOf(address(depositManager)), 0);

        assertEq(usdc.balanceOf(user), userUsdcBalanceBefore - amount);
        assertEq(plUsd.balanceOf(address(user)), userPlUsdBalanceBefore);

        assertEq(usdc.balanceOf(custodian), custodianUsdcBalanceBefore + amount);

        assertEq(depositManager.lastMintTimestamp(), block.timestamp);

        VerifiedRequestsQueueUpgradeable.Request memory request = depositManager.requests(requestId);
        assertEq(request.user, user);
        assertEq(request.amount, amount);
        assertEq(request.timestamp, block.timestamp);
        assert(!request.claimed);
    }

    function testFuzz_claim(uint256 amount) public {
        vm.assume(amount >= minDeposit && amount <= usdcAmount);

        vm.prank(user);
        usdc.approve(address(depositManager), amount);

        vm.prank(user);
        uint256 requestId = depositManager.deposit(amount);

        uint256 userUsdcBalanceBefore = usdc.balanceOf(user);
        uint256 userPlUsdBalanceBefore = plUsd.balanceOf(user);
        uint256 custodianUsdcBalanceBefore = usdc.balanceOf(custodian);

        bytes memory signature = _createSignature(requestId, user, amount, depositVerifierPrivateKey);
        assert(depositManager.verifySignature(requestId, signature));

        vm.prank(user);
        uint256 mintAmount = depositManager.claim(requestId, signature);

        assertEq(mintAmount, amount);

        assertEq(usdc.balanceOf(address(depositManager)), 0);
        assertEq(plUsd.balanceOf(address(depositManager)), 0);

        assertEq(usdc.balanceOf(user), userUsdcBalanceBefore);
        assertEq(plUsd.balanceOf(address(user)), userPlUsdBalanceBefore + amount);
        assertEq(usdc.balanceOf(custodian), custodianUsdcBalanceBefore);

        VerifiedRequestsQueueUpgradeable.Request memory request = depositManager.requests(requestId);
        assert(request.claimed);
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

    function testFuzz_depositReverts(uint256 amount) public {
        vm.assume(amount < depositManager.minDeposit() && amount != 0);

        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfig = depositManager.rateLimitConfig();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterExceedsTxLimit.selector));
        depositManager.deposit(rateLimitConfig.txLimit + amount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerLessThanMinAmount.selector));
        depositManager.deposit(amount);

        vm.prank(depositManagerAdmin);
        depositManager.setMinDeposit(0);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsQueueZeroAmount.selector)
        );
        depositManager.deposit(0);
    }

    function testFuzz_claimReverts(uint256 amount) public {
        vm.assume(amount >= depositManager.minDeposit() && amount <= usdcAmount);

        vm.prank(user);
        usdc.approve(address(depositManager), amount);

        vm.prank(user);
        uint256 requestId = depositManager.deposit(amount);

        bytes memory invalidSignature = _createSignature(requestId, user, amount, 1);
        assert(!depositManager.verifySignature(requestId, invalidSignature));

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsInvalidRequestId.selector)
        );
        depositManager.claim(requestId + 1, invalidSignature);

        address wrongClaimant = makeAddr("wrongClaimant");
        vm.prank(wrongClaimant);
        vm.expectRevert(abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsInvalidSender.selector));
        depositManager.claim(requestId, invalidSignature);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsInvalidSignature.selector)
        );
        depositManager.claim(requestId, invalidSignature);

        bytes memory signature = _createSignature(requestId, user, amount, depositVerifierPrivateKey);

        vm.prank(user);
        depositManager.claim(requestId, signature);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsQueueAlreadyClaimed.selector)
        );
        depositManager.claim(requestId, signature);
    }

    function test_setMinDeposit(uint256 newMinDeposit) public {
        vm.assume(newMinDeposit != depositManager.minDeposit());

        vm.prank(depositManagerAdmin);
        depositManager.setMinDeposit(newMinDeposit);

        assertEq(depositManager.minDeposit(), newMinDeposit);
    }

    function test_setMinDepositReverts() public {
        uint256 newMinDeposit = depositManager.minDeposit();

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerSameValue.selector));
        depositManager.setMinDeposit(newMinDeposit);
    }

    function test_setCustodian(address newCustodian) public {
        vm.assume(newCustodian != depositManager.custodian() && newCustodian != address(0));

        vm.prank(depositManagerAdmin);
        depositManager.setCustodian(newCustodian);

        assertEq(depositManager.custodian(), newCustodian);
    }

    function test_setCustodianReverts() public {
        address newCustodian = depositManager.custodian();

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerSameValue.selector));
        depositManager.setCustodian(newCustodian);

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(DepositManagerUpgradeable.DepositManagerZeroAddress.selector));
        depositManager.setCustodian(address(0));
    }

    function testFuzz_setVerifier(address newVerifier) public {
        vm.assume(newVerifier != depositManager.verifier() && newVerifier != address(0));

        vm.prank(depositManagerAdmin);
        depositManager.setVerifier(newVerifier);

        assertEq(depositManager.verifier(), newVerifier);
    }

    function test_setVerifierReverts() public {
        address newVerifier = depositManager.verifier();

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsSameValue.selector));
        depositManager.setVerifier(newVerifier);

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(VerifiedRequestsQueueUpgradeable.VerifiedRequestsZeroAddress.selector));
        depositManager.setVerifier(address(0));
    }

    function test_increaseTxLimit(uint256 newTxLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newTxLimit > rateLimitConfigBefore.txLimit);

        vm.prank(depositManagerAdmin);
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

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterWrongValue.selector));
        depositManager.increaseTxLimit(newTxLimit);
    }

    function test_decreaseTxLimit(uint256 newTxLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newTxLimit < rateLimitConfigBefore.txLimit);

        vm.prank(depositManagerAdmin);
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

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterWrongValue.selector));
        depositManager.decreaseTxLimit(newTxLimit);
    }

    function test_increaseWindowLimit(uint256 newWindowLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newWindowLimit > rateLimitConfigBefore.windowLimit);

        vm.prank(depositManagerAdmin);
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

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterWrongValue.selector));
        depositManager.increaseWindowLimit(newWindowLimit);
    }

    function test_decreaseWindowLimit(uint256 newWindowLimit) public {
        RateLimiterUpgradeable.RateLimitConfig memory rateLimitConfigBefore = depositManager.rateLimitConfig();
        vm.assume(newWindowLimit < rateLimitConfigBefore.windowLimit);

        vm.prank(depositManagerAdmin);
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

        vm.prank(depositManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(RateLimiterUpgradeable.RateLimiterWrongValue.selector));
        depositManager.decreaseWindowLimit(newWindowLimit);
    }

    function _createSignature(uint256 requestId, address claimant, uint256 amount, uint256 privateKey)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 structHash =
            keccak256(abi.encode(depositManager.VERIFIED_REQUESTS_TYPEHASH(), requestId, claimant, amount));

        bytes32 domainSeparator = depositManager.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
