// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IDealTokenFactory} from "../src/interfaces/IDealTokenFactory.sol";
import {DealToken} from "../src/dealTokenFactory/DealToken.sol";
import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {IStakedPipelineUSD} from "../src/interfaces/IStakedPipelineUSD.sol";
import {RateLimiterUpgradeable} from "../src/depositManager/RateLimiterUpgradeable.sol";
import {MinterUpgradeable} from "../src/minter/MinterUpgradeable.sol";
import {PocketUpgradeable} from "../src/pocket/PocketUpgradeable.sol";
import {WhitelistAccessedUpgradeable} from "../src/whitelist/WhitelistAccessedUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract MinterTest is PipelineTestSetUp {
    uint256 constant YEAR = 31557600;
    uint256 constant SENIOR_TRANCHE = 1_000_000_000;

    uint256 lps;

    function test_setUp() public view {
        assertEq(minter.authority(), address(authority));
        assertEq(minter.plUsd(), address(plUsd));
        assertEq(minter.stakedPlUsd(), address(sPlUsd));
        assertEq(minter.loanRegistry(), address(loanRegistry));
        assertEq(minter.pocket(), address(pocket));
        assertEq(minter.usdc(), address(usdc));
        assertEq(minter.treasury(), treasury);
        assertEq(minter.factory(), address(dealTokenFactory));
        assertEq(minter.rateLimitConfig().txLimit, minterRateLimitConfig.txLimit);
        assertEq(minter.bankCash(), 0);
        assertEq(minter.custodians().length, 0);
    }

    function test_setters() public {
        address other = makeAddr("other");
        address[] memory custodians = new address[](2);
        custodians[0] = makeAddr("custodianA");
        custodians[1] = makeAddr("custodianB");

        vm.startPrank(admin);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.TreasurySet(other);
        minter.setTreasury(other);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.FactorySet(other);
        minter.setFactory(other);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.PocketSet(other);
        minter.setPocket(other);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.CustodiansSet(custodians);
        minter.setCustodians(custodians);

        vm.stopPrank();

        assertEq(minter.treasury(), other);
        assertEq(minter.factory(), other);
        assertEq(minter.pocket(), other);
        assertEq(minter.custodians(), custodians);
    }

    function test_settersReverts() public {
        address[] memory custodians = new address[](1);

        vm.startPrank(admin);

        vm.expectRevert(MinterUpgradeable.MinterZeroAddress.selector);
        minter.setTreasury(address(0));
        vm.expectRevert(MinterUpgradeable.MinterSameValue.selector);
        minter.setTreasury(treasury);

        vm.expectRevert(MinterUpgradeable.MinterZeroAddress.selector);
        minter.setPocket(address(0));
        vm.expectRevert(MinterUpgradeable.MinterSameValue.selector);
        minter.setPocket(address(pocket));

        vm.expectRevert(MinterUpgradeable.MinterSameValue.selector);
        minter.setFactory(address(dealTokenFactory));

        vm.expectRevert(MinterUpgradeable.MinterZeroAddress.selector);
        minter.setCustodians(custodians);

        vm.stopPrank();
    }

    function test_recordWireInStakesForLp() public {
        address lp = _newLp();

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.WireInRecorded(0, lp, 500, 7, _h(1), _h(200));

        vm.prank(mintCaller);
        uint256 id = minter.recordWireIn(lp, 500, 7, _h(1), _h(200));

        assertEq(minter.bankCash(), 500);
        assertEq(sPlUsd.balanceOf(lp), 500);
        assertEq(plUsd.balanceOf(address(sPlUsd)), 500);
        assertEq(plUsd.balanceOf(address(minter)), 0);
        assertTrue(minter.refHashSeen(_h(1)));

        MinterUpgradeable.WireIn memory wire = minter.wireIn(id);
        assertEq(uint8(wire.status), uint8(MinterUpgradeable.WireInStatus.Direct));
        assertEq(wire.receiver, lp);
        assertEq(wire.amount, 500);
        assertEq(wire.valueDate, 7);
        assertEq(wire.lpRef, _h(200));
        _assertBacked();
    }

    function test_recordWireInEscrows() public {
        uint256 id = _escrow(500, 1);

        assertEq(plUsd.balanceOf(address(minter)), 500);
        assertEq(minter.bankCash(), 500);
        assertEq(uint8(minter.wireIn(id).status), uint8(MinterUpgradeable.WireInStatus.Escrowed));
        _assertBacked();
    }

    function test_recordWireInReverts() public {
        address stranger = makeAddr("stranger");

        vm.prank(mintCaller);
        vm.expectRevert(MinterUpgradeable.MinterInvalidAmount.selector);
        minter.recordWireIn(address(minter), 0, 0, _h(1), bytes32(0));

        vm.prank(mintCaller);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterReceiverNotAllowed.selector, stranger));
        minter.recordWireIn(stranger, 500, 0, _h(1), bytes32(0));

        _escrow(500, 1);

        vm.prank(mintCaller);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterRefHashSeen.selector, _h(1)));
        minter.recordWireIn(address(minter), 500, 0, _h(1), bytes32(0));
    }

    function test_mintingCallsRefuseZeroRef() public {
        uint256 loanId = _loanReadyToRepay();
        ILoanRegistry.RepaymentData memory repaymentData = _repaymentData();

        vm.startPrank(mintCaller);

        vm.expectRevert(MinterUpgradeable.MinterMissingRef.selector);
        minter.recordWireIn(address(minter), 10, 0, bytes32(0), bytes32(0));

        vm.expectRevert(MinterUpgradeable.MinterMissingRef.selector);
        minter.repay(loanId, repaymentData, 0, bytes32(0), 0);

        vm.expectRevert(MinterUpgradeable.MinterMissingRef.selector);
        minter.recordIncome(10, 0, bytes32(0));

        vm.stopPrank();
    }

    function test_mintBudget() public {
        vm.startPrank(admin);
        minter.decreaseTxLimit(1_000);
        minter.decreaseWindowLimit(1_500);
        vm.stopPrank();

        vm.prank(mintCaller);
        vm.expectRevert(RateLimiterUpgradeable.RateLimiterExceedsTxLimit.selector);
        minter.recordWireIn(address(minter), 1_001, 0, _h(1), bytes32(0));

        _escrow(1_000, 2);

        vm.prank(mintCaller);
        vm.expectRevert(RateLimiterUpgradeable.RateLimiterExceedsWindowLimit.selector);
        minter.recordWireIn(address(minter), 1_000, 0, _h(3), bytes32(0));

        skip(1 days);
        _escrow(1_000, 4);
    }

    function test_assignWireIn() public {
        uint256 id = _escrow(500, 1);
        address lp = _newLp();

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.WireInAssigned(id, lp, _h(7));

        vm.prank(minterOps);
        minter.assignWireIn(id, lp, _h(7));

        assertEq(sPlUsd.balanceOf(lp), 500);
        assertEq(plUsd.balanceOf(address(minter)), 0);

        MinterUpgradeable.WireIn memory wire = minter.wireIn(id);
        assertEq(uint8(wire.status), uint8(MinterUpgradeable.WireInStatus.Assigned));
        assertEq(wire.receiver, lp);
        assertEq(wire.lpRef, _h(7));

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterWrongWireStatus.selector, id));
        minter.assignWireIn(id, lp, _h(7));
    }

    function test_returnWireIn() public {
        uint256 id = _escrow(500, 1);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.WireInReturned(id, 500, _h(8));

        vm.prank(minterOps);
        minter.returnWireIn(id, _h(8));

        assertEq(plUsd.balanceOf(address(minter)), 0);
        assertEq(plUsd.totalSupply(), 0);
        assertEq(minter.bankCash(), 0);

        MinterUpgradeable.WireIn memory wire = minter.wireIn(id);
        assertEq(uint8(wire.status), uint8(MinterUpgradeable.WireInStatus.Returned));
        assertEq(wire.returnRef, _h(8));

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterWrongWireStatus.selector, id));
        minter.returnWireIn(id, _h(9));

        (, uint256 directId) = _wireInLp(500, 2);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterWrongWireStatus.selector, directId));
        minter.returnWireIn(directId, _h(10));
    }

    function test_bankCashNeverBelowZero() public {
        uint256 id = _escrow(500, 1);
        _disburse(_drawLoan(), 500, 2);
        assertEq(minter.bankCash(), 0);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterInsufficientBankCash.selector, 500, 0));
        minter.returnWireIn(id, _h(3));
    }

    function test_disburse() public {
        _escrow(500, 1);
        uint256 loanId = _drawLoan();
        _registerDeal(loanId);

        vm.expectCall(address(dealTokenFactory), abi.encodeCall(IDealTokenFactory.syncDebt, (loanId)));
        vm.expectEmit(address(minter));
        emit MinterUpgradeable.CashDisbursed(loanId, 0, 300, 5, _h(2));

        vm.prank(minterOps);
        uint256 entryId = minter.disburse(loanId, 300, 5, _h(2));

        assertEq(minter.bankCash(), 200);
        assertEq(loanRegistry.outstanding(loanId), 300);
        assertEq(DealToken(dealTokenFactory.deal(loanId).debt).balanceOf(capitalWallet), 300);

        MinterUpgradeable.CashEntry memory entry = minter.cashEntry(entryId);
        assertEq(entry.delta, -300);
        assertEq(uint8(entry.reason), uint8(MinterUpgradeable.CashReason.Disbursed));
        assertEq(entry.loanId, loanId);
        assertEq(entry.valueDate, 5);
        assertEq(entry.refHash, _h(2));
        assertFalse(entry.reversed);
        _assertBacked();
    }

    function test_disburseRejectsMoreThanBankCash() public {
        _escrow(100, 1);
        uint256 loanId = _drawLoan();

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterInsufficientBankCash.selector, 101, 100));
        minter.disburse(loanId, 101, 0, _h(2));
    }

    function test_disburseSurvivesFailingSyncDebt() public {
        _escrow(500, 1);
        uint256 loanId = _drawLoan();

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.SyncLagging(loanId);

        _disburse(loanId, 300, 2);

        assertEq(loanRegistry.outstanding(loanId), 300);
    }

    function test_disburseWithoutFactory() public {
        vm.prank(admin);
        minter.setFactory(address(0));

        _escrow(500, 1);
        uint256 loanId = _drawLoan();

        vm.expectCall(address(dealTokenFactory), abi.encodeCall(IDealTokenFactory.syncDebt, (loanId)), 0);
        _disburse(loanId, 300, 2);

        assertEq(loanRegistry.outstanding(loanId), 300);
    }

    function test_reverseDisburse() public {
        _escrow(500, 1);
        uint256 loanId = _drawLoan();
        uint256 entryId = _disburse(loanId, 300, 2);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterWrongEntry.selector, entryId));
        minter.reverseDisburse(loanId, 299, _h(3), entryId);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.CashDisbursementReversed(loanId, entryId + 1, entryId, 300, _h(3));

        vm.prank(minterOps);
        minter.reverseDisburse(loanId, 300, _h(3), entryId);

        assertEq(minter.bankCash(), 500);
        assertEq(loanRegistry.outstanding(loanId), 0);
        assertTrue(minter.cashEntry(entryId).reversed);

        MinterUpgradeable.CashEntry memory reversal = minter.cashEntry(entryId + 1);
        assertEq(reversal.delta, 300);
        assertEq(uint8(reversal.reason), uint8(MinterUpgradeable.CashReason.DisbursementReversed));
        assertEq(reversal.original, entryId);
        assertEq(reversal.loanId, loanId);

        vm.prank(minterOps);
        vm.expectRevert(MinterUpgradeable.MinterAlreadyReversed.selector);
        minter.reverseDisburse(loanId, 300, _h(4), entryId);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterWrongEntry.selector, entryId + 1));
        minter.reverseDisburse(loanId, 300, _h(5), entryId + 1);
        _assertBacked();
    }

    function test_reverseDisburseNamedEntry() public {
        _escrow(500, 1);
        uint256 loanId = _drawLoan();
        uint256 first = _disburse(loanId, 100, 2);
        _disburse(loanId, 50, 3);

        vm.prank(minterOps);
        minter.reverseDisburse(loanId, 100, _h(4), first);

        ILoanRegistry.Disbursement[] memory list = loanRegistry.disbursements(loanId);
        assertEq(list[0].remaining, 0);
        assertEq(list[1].remaining, 50);
        assertEq(loanRegistry.outstanding(loanId), 50);
    }

    function test_repayLiveLoan() public {
        uint256 loanId = _loanReadyToRepay();
        uint256 vaultBefore = plUsd.balanceOf(address(sPlUsd));
        uint256 bankBefore = minter.bankCash();
        uint256 expectedFeeShares =
            Math.mulDiv(6_000_000, sPlUsd.totalSupply() + 1, sPlUsd.totalAssets() + 50_000_000 + 1);

        vm.expectCall(address(dealTokenFactory), abi.encodeCall(IDealTokenFactory.syncDebt, (loanId)));
        vm.expectEmit(address(minter));
        emit MinterUpgradeable.CashRepaid(loanId, 0, 0, 100_000_000, 50_000_000, expectedFeeShares, 0, _h(3));

        uint256 repaymentId = _repay(loanId, 3);

        assertEq(minter.bankCash(), bankBefore + 100_000_000);
        assertEq(plUsd.balanceOf(address(sPlUsd)), vaultBefore + 56_000_000);
        assertEq(plUsd.balanceOf(address(minter)), 0);
        assertEq(sPlUsd.balanceOf(treasury), expectedFeeShares);
        assertApproxEqAbs(sPlUsd.previewRedeem(expectedFeeShares), 6_000_000, 1);
        assertEq(loanRegistry.outstanding(loanId), SENIOR_TRANCHE - 44_000_000);

        MinterUpgradeable.Repayment memory record = minter.repayment(loanId, repaymentId);
        assertEq(record.cash, 100_000_000);
        assertEq(record.principal, 44_000_000);
        assertEq(record.interestMinted, 50_000_000);
        assertEq(record.feeShares, expectedFeeShares);
        assertFalse(record.carvedOut);
        assertFalse(record.reversed);
        _assertBacked();
    }

    function test_repayCarvedOutLoan() public {
        uint256 loanId = _loanReadyToRepay();
        _carveOut(loanId);

        uint256 repaymentId = _repay(loanId, 3);

        assertEq(plUsd.balanceOf(address(pocket)), SENIOR_TRANCHE + 50_000_000);
        assertEq(plUsd.balanceOf(address(sPlUsd)), 6_000_000);

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(loanId);
        assertEq(pocketData.held, SENIOR_TRANCHE - 44_000_000);
        assertEq(pocketData.releasedTotal, 94_000_000);

        MinterUpgradeable.Repayment memory record = minter.repayment(loanId, repaymentId);
        assertTrue(record.carvedOut);
        assertEq(record.principal, 44_000_000);
        _assertBacked();
    }

    function test_repayCountsAgainstBudget() public {
        uint256 loanId = _loanReadyToRepay();
        ILoanRegistry.RepaymentData memory repaymentData = _repaymentData();

        vm.prank(admin);
        minter.decreaseTxLimit(55_999_999);

        vm.prank(mintCaller);
        vm.expectRevert(RateLimiterUpgradeable.RateLimiterExceedsTxLimit.selector);
        minter.repay(loanId, repaymentData, 0, _h(3), 0);
    }

    function test_repayRejectsEquityAboveReceipts() public {
        uint256 loanId = _loanReadyToRepay();
        ILoanRegistry.RepaymentData memory repaymentData;
        repaymentData.equityDistributed = 1;

        vm.prank(mintCaller);
        vm.expectRevert(MinterUpgradeable.MinterInvalidAmount.selector);
        minter.repay(loanId, repaymentData, 0, _h(3), 0);
    }

    function test_reverseRepay() public {
        uint256 loanId = _loanReadyToRepay();
        uint256 vaultBefore = plUsd.balanceOf(address(sPlUsd));
        uint256 sharesBefore = sPlUsd.totalSupply();
        uint256 bankBefore = minter.bankCash();
        uint256 repaymentId = _repay(loanId, 3);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.CashRepaymentReversed(loanId, repaymentId, 100_000_000, _h(4));

        vm.prank(minterOps);
        minter.reverseRepay(loanId, repaymentId, _h(4));

        assertEq(minter.bankCash(), bankBefore);
        assertEq(plUsd.balanceOf(address(sPlUsd)), vaultBefore);
        assertEq(sPlUsd.balanceOf(treasury), 0);
        assertEq(sPlUsd.totalSupply(), sharesBefore);
        assertEq(plUsd.balanceOf(address(minter)), 0);
        assertEq(loanRegistry.outstanding(loanId), SENIOR_TRANCHE);
        assertTrue(minter.repayment(loanId, repaymentId).reversed);
        assertEq(minter.unabsorbedTotal(), 0);
        _assertBacked();

        vm.prank(minterOps);
        vm.expectRevert(MinterUpgradeable.MinterAlreadyReversed.selector);
        minter.reverseRepay(loanId, repaymentId, _h(5));

        vm.prank(minterOps);
        vm.expectRevert(
            abi.encodeWithSelector(MinterUpgradeable.MinterNonExistentRepayment.selector, loanId, repaymentId + 1)
        );
        minter.reverseRepay(loanId, repaymentId + 1, _h(6));
    }

    function test_reverseRepayCarvedOut() public {
        uint256 loanId = _loanReadyToRepay();
        _carveOut(loanId);
        uint256 repaymentId = _repay(loanId, 3);

        vm.prank(minterOps);
        minter.reverseRepay(loanId, repaymentId, _h(4));

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(loanId);
        assertEq(pocketData.held, SENIOR_TRANCHE);
        assertEq(pocketData.releasedTotal, 0);
        assertEq(plUsd.balanceOf(address(pocket)), SENIOR_TRANCHE);
        assertEq(plUsd.balanceOf(address(sPlUsd)), 0);
        assertEq(minter.unabsorbedTotal(), 0);
        _assertBacked();
    }

    function test_reverseRepayCountsUncovered() public {
        uint256 loanId = _loanReadyToRepay();
        uint256 repaymentId = _repay(loanId, 3);

        uint256 vaultBalance = plUsd.balanceOf(address(sPlUsd));
        vm.prank(minterOps);
        minter.correctVaultMint(vaultBalance - 20_000_000, _h(6));
        uint256 unabsorbedBefore = minter.unabsorbedTotal();

        vm.prank(minterOps);
        minter.reverseRepay(loanId, repaymentId, _h(4));

        assertEq(minter.unabsorbedTotal() - unabsorbedBefore, 36_000_000);
        assertEq(plUsd.balanceOf(address(sPlUsd)), 0);
    }

    function test_wireOut() public {
        _wireInLp(500, 1);
        address lp = _newLp();
        deal(address(plUsd), lp, 300, true);

        vm.startPrank(lp);
        plUsd.approve(address(minter), 300);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.WireOutRequested(0, lp, 300);

        uint256 id = minter.requestWireOut(300);
        vm.stopPrank();

        assertEq(plUsd.balanceOf(lp), 0);
        assertEq(plUsd.balanceOf(address(minter)), 300);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterAmountMismatch.selector, 299, 300));
        minter.settleWireOut(id, 299, 0, _h(2));

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.WireOutSettled(id, 300, 3, _h(2));

        vm.prank(minterOps);
        minter.settleWireOut(id, 300, 3, _h(2));

        assertEq(plUsd.balanceOf(address(minter)), 0);
        assertEq(minter.bankCash(), 200);

        MinterUpgradeable.WireOut memory wire = minter.wireOut(id);
        assertEq(uint8(wire.status), uint8(MinterUpgradeable.WireOutStatus.Settled));
        assertEq(wire.lp, lp);
        assertEq(wire.refHash, _h(2));

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterWrongWireStatus.selector, id));
        minter.cancelWireOut(id);
    }

    function test_cancelWireOut() public {
        address lp = _newLp();
        deal(address(plUsd), lp, 300, true);

        vm.startPrank(lp);
        plUsd.approve(address(minter), 300);
        uint256 id = minter.requestWireOut(300);
        vm.stopPrank();

        vm.prank(whitelistAdmin);
        whitelistRegistry.disallow(lp);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, lp));
        minter.cancelWireOut(id);

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(lp);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.WireOutCancelled(id);

        vm.prank(minterOps);
        minter.cancelWireOut(id);

        assertEq(plUsd.balanceOf(lp), 300);
        assertEq(uint8(minter.wireOut(id).status), uint8(MinterUpgradeable.WireOutStatus.Cancelled));
    }

    function test_requestWireOutNotAllowed() public {
        address lp = makeAddr("frozenLp");
        deal(address(plUsd), lp, 300, true);

        vm.startPrank(lp);
        plUsd.approve(address(minter), 300);
        vm.expectRevert(abi.encodeWithSelector(WhitelistAccessedUpgradeable.WhitelistAccessedNoAccess.selector, lp));
        minter.requestWireOut(300);
        vm.stopPrank();
    }

    function test_usdcToBankRamp() public {
        _wireInLp(500, 1);
        _fundCustody(1_000);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.RampOpened(0, MinterUpgradeable.RampDirection.UsdcToBank, 400, _h(2));

        vm.prank(minterOps);
        uint256 id = minter.openRamp(MinterUpgradeable.RampDirection.UsdcToBank, 400, _h(2));
        assertEq(minter.inFlight(), 400);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.LossAbsorbed(10, 10);
        vm.expectEmit(address(minter));
        emit MinterUpgradeable.RampClosed(id, 390, 10, _h(3));

        vm.prank(minterOps);
        minter.closeRamp(id, 390, _h(3));

        assertEq(minter.inFlight(), 0);
        assertEq(minter.bankCash(), 890);
        assertEq(plUsd.balanceOf(address(sPlUsd)), 490);
        assertEq(minter.unabsorbedTotal(), 0);

        MinterUpgradeable.Ramp memory rampData = minter.ramp(id);
        assertTrue(rampData.closed);
        assertEq(rampData.received, 390);

        MinterUpgradeable.CashEntry memory entry = minter.cashEntry(0);
        assertEq(entry.delta, -10);
        assertEq(uint8(entry.reason), uint8(MinterUpgradeable.CashReason.Expense));
    }

    function test_usdcToBankRampNeedsCustody() public {
        _fundCustody(100);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterInsufficientCustody.selector, 101, 100));
        minter.openRamp(MinterUpgradeable.RampDirection.UsdcToBank, 101, _h(2));
    }

    function test_bankToUsdcRamp() public {
        _wireInLp(500, 1);

        vm.prank(minterOps);
        uint256 id = minter.openRamp(MinterUpgradeable.RampDirection.BankToUsdc, 400, _h(2));

        assertEq(minter.bankCash(), 100);
        assertEq(minter.inFlight(), 400);
        _assertBacked();

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterReceivedExceedsAmount.selector, 401, 400));
        minter.closeRamp(id, 401, _h(3));

        vm.prank(minterOps);
        minter.closeRamp(id, 400, _h(3));

        assertEq(minter.bankCash(), 100);
        assertEq(minter.inFlight(), 0);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterRampClosed.selector, id));
        minter.closeRamp(id, 400, _h(4));
    }

    function test_recordIncome() public {
        vm.expectEmit(address(minter));
        emit MinterUpgradeable.CashRecorded(MinterUpgradeable.CashReason.Income, 0, 700, 4, _h(1));

        vm.prank(mintCaller);
        minter.recordIncome(700, 4, _h(1));

        assertEq(minter.bankCash(), 700);
        assertEq(plUsd.balanceOf(address(sPlUsd)), 700);
        assertEq(uint8(minter.cashEntry(0).reason), uint8(MinterUpgradeable.CashReason.Income));
        _assertBacked();
    }

    function test_recordExpense() public {
        _wireInLp(500, 1);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.CashRecorded(MinterUpgradeable.CashReason.Expense, 0, -40, 0, _h(2));

        vm.prank(minterOps);
        minter.recordExpense(40, 0, _h(2));

        assertEq(minter.bankCash(), 460);
        assertEq(plUsd.balanceOf(address(sPlUsd)), 460);
        _assertBacked();
    }

    function test_absorbBeyondVaultIsUnabsorbed() public {
        _wireInLp(100, 1);

        vm.prank(mintCaller);
        minter.recordIncome(100, 0, _h(2));

        vm.prank(minterOps);
        minter.correctVaultMint(150, _h(3));

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.LossAbsorbed(100, 50);

        vm.prank(minterOps);
        minter.recordExpense(100, 0, _h(4));

        assertEq(plUsd.balanceOf(address(sPlUsd)), 0);
        assertEq(minter.unabsorbedTotal(), 50);
        assertEq(minter.poolState().unabsorbedTotal, 50);
    }

    function test_recordCorrection() public {
        _escrow(100, 1);
        uint256 entryId = _disburse(_drawLoan(), 10, 2);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.CashRecorded(
            MinterUpgradeable.CashReason.Correction, entryId + 1, 25, uint64(vm.getBlockTimestamp()), _h(3)
        );

        vm.prank(minterOps);
        minter.recordCorrection(25, _h(3), entryId);

        assertEq(minter.bankCash(), 115);

        MinterUpgradeable.CashEntry memory correction = minter.cashEntry(entryId + 1);
        assertEq(correction.delta, 25);
        assertEq(uint8(correction.reason), uint8(MinterUpgradeable.CashReason.Correction));
        assertEq(correction.original, entryId);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterInsufficientBankCash.selector, 116, 115));
        minter.recordCorrection(-116, _h(3), entryId);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterNonExistentCashEntry.selector, 99));
        minter.recordCorrection(1, _h(3), 99);
    }

    function test_correctVaultMint() public {
        _wireInLp(500, 1);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.MintCorrected(120, _h(2));

        vm.prank(minterOps);
        minter.correctVaultMint(120, _h(2));

        assertEq(plUsd.balanceOf(address(sPlUsd)), 380);
        assertEq(minter.bankCash(), 500);
    }

    function test_poolState() public {
        _wireInLp(1_000, 1);
        address custodianWallet = _fundCustody(300);
        _disburse(_drawLoan(), 200, 2);

        vm.prank(minterOps);
        minter.openRamp(MinterUpgradeable.RampDirection.BankToUsdc, 100, _h(3));

        MinterUpgradeable.PoolState memory pool = minter.poolState();
        assertEq(pool.custody.length, 1);
        assertEq(pool.custody[0].custodian, custodianWallet);
        assertEq(pool.custody[0].balance, 300);
        assertFalse(pool.readFailed);
        assertEq(pool.bankCash, 700);
        assertEq(pool.inFlight, 100);
        assertEq(pool.outstandingTotal, 200);
        assertEq(pool.unabsorbedTotal, 0);
        assertEq(pool.totalAssets, 1_300);
        assertEq(minter.totalAssets(), 1_300);

        vm.expectEmit(address(minter));
        emit MinterUpgradeable.Snapshot(vm.getBlockNumber(), pool);

        minter.snapshot();
    }

    function test_poolStateReadFailure() public {
        address custodianWallet = _fundCustody(300);
        vm.mockCallRevert(address(usdc), abi.encodeCall(IERC20.balanceOf, (custodianWallet)), "");

        MinterUpgradeable.PoolState memory pool = minter.poolState();
        assertTrue(pool.readFailed);
        assertEq(pool.custody[0].balance, 0);
        assertEq(pool.totalAssets, 0);

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterInsufficientCustody.selector, 1, 0));
        minter.openRamp(MinterUpgradeable.RampDirection.UsdcToBank, 1, _h(2));
    }

    function test_pauses() public {
        uint256 id = _escrow(500, 1);
        uint256 loanId = _drawLoan();
        ILoanRegistry.RepaymentData memory repaymentData = _repaymentData();

        vm.prank(minterOps);
        minter.pause();
        assertTrue(minter.paused());

        vm.startPrank(mintCaller);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minter.recordWireIn(address(minter), 1, 0, _h(2), bytes32(0));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minter.recordIncome(1, 0, _h(3));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minter.repay(loanId, repaymentData, 0, _h(4), 0);
        vm.stopPrank();

        vm.startPrank(minterOps);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minter.assignWireIn(id, minterOps, bytes32(0));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minter.disburse(loanId, 1, 0, _h(5));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minter.openRamp(MinterUpgradeable.RampDirection.BankToUsdc, 1, _h(6));
        vm.stopPrank();

        vm.prank(mintCaller);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minter.requestWireOut(1);

        vm.prank(minterOps);
        minter.returnWireIn(id, _h(7));
        assertEq(minter.bankCash(), 0);

        vm.prank(minterOps);
        minter.unpause();
        assertFalse(minter.paused());
    }

    function test_zeroAmountsRevert() public {
        vm.startPrank(minterOps);
        vm.expectRevert(MinterUpgradeable.MinterInvalidAmount.selector);
        minter.disburse(0, 0, 0, _h(1));
        vm.expectRevert(MinterUpgradeable.MinterInvalidAmount.selector);
        minter.openRamp(MinterUpgradeable.RampDirection.BankToUsdc, 0, _h(1));
        vm.expectRevert(MinterUpgradeable.MinterInvalidAmount.selector);
        minter.recordExpense(0, 0, _h(1));
        vm.expectRevert(MinterUpgradeable.MinterInvalidAmount.selector);
        minter.correctVaultMint(0, _h(1));
        vm.stopPrank();

        vm.prank(mintCaller);
        vm.expectRevert(MinterUpgradeable.MinterInvalidAmount.selector);
        minter.recordIncome(0, 0, _h(1));

        vm.expectRevert(MinterUpgradeable.MinterInvalidAmount.selector);
        minter.requestWireOut(0);
    }

    function test_principalOnlyRepayment() public {
        uint256 loanId = _loanReadyToRepay();
        uint256 vaultBefore = plUsd.balanceOf(address(sPlUsd));
        uint256 windowMintBefore = minter.windowCumulativeMint();

        ILoanRegistry.RepaymentData memory repaymentData;
        repaymentData.offtakerReceived = 44_000_000;
        repaymentData.seniorPrincipalRepaid = 44_000_000;

        vm.prank(mintCaller);
        uint256 repaymentId = minter.repay(loanId, repaymentData, 0, _h(3), 0);

        assertEq(minter.bankCash(), 44_000_000);
        assertEq(plUsd.balanceOf(address(sPlUsd)), vaultBefore);
        assertEq(sPlUsd.balanceOf(treasury), 0);
        assertEq(minter.windowCumulativeMint(), windowMintBefore);
        assertEq(minter.repayment(loanId, repaymentId).feeShares, 0);
        _assertBacked();

        vm.prank(minterOps);
        minter.reverseRepay(loanId, repaymentId, _h(4));

        assertEq(minter.bankCash(), 0);
        assertEq(plUsd.balanceOf(address(sPlUsd)), vaultBefore);
        assertEq(loanRegistry.outstanding(loanId), SENIOR_TRANCHE);
        _assertBacked();
    }

    function test_principalOnlyRecoveryOnCarvedOutLoan() public {
        uint256 loanId = _loanReadyToRepay();
        _carveOut(loanId);

        ILoanRegistry.RepaymentData memory repaymentData;
        repaymentData.offtakerReceived = 44_000_000;
        repaymentData.seniorPrincipalRepaid = 44_000_000;

        vm.prank(mintCaller);
        uint256 repaymentId = minter.repay(loanId, repaymentData, 0, _h(3), 0);

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(loanId);
        assertEq(pocketData.held, SENIOR_TRANCHE - 44_000_000);
        assertEq(pocketData.releasedTotal, 44_000_000);
        assertEq(plUsd.balanceOf(address(pocket)), SENIOR_TRANCHE);
        _assertBacked();

        vm.prank(minterOps);
        minter.reverseRepay(loanId, repaymentId, _h(4));

        pocketData = pocket.pocket(loanId);
        assertEq(pocketData.held, SENIOR_TRANCHE);
        assertEq(pocketData.releasedTotal, 0);
        _assertBacked();
    }

    function test_nonMintingCallsAcceptZeroRef() public {
        _escrow(500, 1);
        uint256 loanId = _drawLoan();

        _disburseWithRef(loanId, 100, bytes32(0));
        _disburseWithRef(loanId, 100, bytes32(0));

        assertEq(loanRegistry.outstanding(loanId), 200);
        assertFalse(minter.refHashSeen(bytes32(0)));
    }

    function test_absorbRejectsOverreport() public {
        _wireInLp(500, 1);
        vm.mockCall(address(sPlUsd), abi.encodeCall(IStakedPipelineUSD.pull, (40)), abi.encode(uint256(41)));

        vm.prank(minterOps);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterPulledMoreThanRequested.selector, 40, 41));
        minter.recordExpense(40, 0, _h(2));
    }

    function test_viewsRevertForUnknownRecords() public {
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterNonExistentWireIn.selector, 0));
        minter.wireIn(0);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterNonExistentWireOut.selector, 0));
        minter.wireOut(0);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterNonExistentRamp.selector, 0));
        minter.ramp(0);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterNonExistentCashEntry.selector, 0));
        minter.cashEntry(0);
        vm.expectRevert(abi.encodeWithSelector(MinterUpgradeable.MinterNonExistentRepayment.selector, 0, 0));
        minter.repayment(0, 0);
    }

    function _h(uint256 n) private pure returns (bytes32) {
        return bytes32(n);
    }

    function _newLp() private returns (address lp) {
        lp = makeAddr(string.concat("lp", vm.toString(++lps)));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(lp);
    }

    function _registerDeal(uint256 loanId) private {
        vm.prank(loanRegistryManager);
        dealTokenFactory.registerDeal(loanId);
    }

    function _escrow(uint256 amount, uint256 refN) private returns (uint256 id) {
        vm.prank(mintCaller);
        return minter.recordWireIn(address(minter), amount, 0, _h(refN), bytes32(0));
    }

    function _wireInLp(uint256 amount, uint256 refN) private returns (address lp, uint256 id) {
        lp = _newLp();

        vm.prank(mintCaller);
        id = minter.recordWireIn(lp, amount, 0, _h(refN), _h(200));
    }

    function _drawLoan() private returns (uint256 loanId) {
        ILoanRegistry.ImmutableLoanData memory economics = ILoanRegistry.ImmutableLoanData({
            borrowerRef: _h(9),
            originalFacilitySize: SENIOR_TRANCHE + 200_000_000,
            originalSeniorTranche: SENIOR_TRANCHE,
            originalEquityTranche: 200_000_000,
            originalOfftakerPrice: SENIOR_TRANCHE + 200_000_000,
            seniorInterestRate: 100_000,
            originationDate: uint64(vm.getBlockTimestamp()),
            originalMaturityDate: uint64(vm.getBlockTimestamp() + YEAR)
        });

        vm.prank(loanRegistryManager);
        return loanRegistry.drawLoan("metadataURI", economics);
    }

    function _disburse(uint256 loanId, uint256 amount, uint256 refN) private returns (uint256 entryId) {
        vm.prank(minterOps);
        return minter.disburse(loanId, amount, 0, _h(refN));
    }

    function _disburseWithRef(uint256 loanId, uint256 amount, bytes32 refHash) private returns (uint256 entryId) {
        vm.prank(minterOps);
        return minter.disburse(loanId, amount, 0, refHash);
    }

    function _repaymentData() private pure returns (ILoanRegistry.RepaymentData memory) {
        return ILoanRegistry.RepaymentData({
            offtakerReceived: 100_000_000,
            seniorPrincipalRepaid: 44_000_000,
            seniorInterest: 50_000_000,
            equityDistributed: 0,
            mgmtFee: 1_000_000,
            perfFee: 2_000_000,
            oetAlloc: 3_000_000
        });
    }

    function _loanReadyToRepay() private returns (uint256 loanId) {
        _wireInLp(SENIOR_TRANCHE, 1);
        loanId = _drawLoan();
        _disburse(loanId, SENIOR_TRANCHE, 2);
        skip(YEAR);
    }

    function _carveOut(uint256 loanId) private {
        vm.startPrank(loanRegistryManager);
        loanRegistry.setDefault(loanId);
        loanRegistry.cure(loanId);
        vm.stopPrank();

        vm.roll(vm.getBlockNumber() + 1);
    }

    function _repay(uint256 loanId, uint256 refN) private returns (uint256 repaymentId) {
        ILoanRegistry.RepaymentData memory repaymentData = _repaymentData();

        vm.prank(mintCaller);
        return minter.repay(loanId, repaymentData, 0, _h(refN), 0);
    }

    function _fundCustody(uint256 amount) private returns (address custodianWallet) {
        custodianWallet = makeAddr("custodianWallet");
        deal(address(usdc), custodianWallet, amount);

        address[] memory custodians = new address[](1);
        custodians[0] = custodianWallet;

        vm.prank(admin);
        minter.setCustodians(custodians);
    }

    function _assertBacked() private view {
        assertEq(plUsd.totalSupply(), minter.totalAssets());
    }
}
