// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {IPocket} from "../src/interfaces/IPocket.sol";
import {IStakedPipelineUSD} from "../src/interfaces/IStakedPipelineUSD.sol";
import {PipelineLoanRegistry} from "../src/PipelineLoanRegistry.sol";
import {LoanRegistryUpgradeable} from "../src/loanRegistry/LoanRegistryUpgradeable.sol";
import {PocketUpgradeable} from "../src/pocket/PocketUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract LoanRegistryTest is PipelineTestSetUp {
    uint256 constant ONE = 1_000_000;
    uint256 constant YEAR = 31557600;

    uint256 constant SENIOR_TRANCHE = 1_000_000_000;
    uint256 constant EQUITY_TRANCHE = 200_000_000;
    uint256 constant FACILITY = 1_200_000_000;
    uint32 constant RATE = 100_000;
    bytes32 constant BORROWER_REF = bytes32(uint256(7));
    string constant METADATA_URI = "metadataURI";

    address staker = makeAddr("staker");

    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(staker);
    }

    function test_setUp() public view {
        assertEq(loanRegistry.authority(), address(authority));
        assertEq(loanRegistry.name(), "Loan registry name");
        assertEq(loanRegistry.symbol(), "Loan registry symbol");
        assertEq(loanRegistry.nextLoanId(), 0);
        assertEq(loanRegistry.capitalWallet(), capitalWallet);
        assertEq(loanRegistry.stakedPlUsd(), address(sPlUsd));
        assertEq(loanRegistry.pocket(), address(pocket));
        assertEq(loanRegistry.maxFeeBps(), maxFeeBps);
        assertEq(loanRegistry.maxResidual(), maxResidual);
        assertEq(loanRegistry.outstandingTotal(), 0);
        assertEq(loanRegistry.unabsorbedTotal(), 0);
    }

    function test_drawLoan() public {
        ILoanRegistry.ImmutableLoanData memory economics = _economics();

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanDrawn(0, METADATA_URI);
        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.StatusUpdated(0, ILoanRegistry.LoanStatus.Approved);

        vm.prank(loanRegistryManager);
        uint256 loanId = loanRegistry.drawLoan(METADATA_URI, economics);

        assertEq(loanId, 0);
        assertEq(loanRegistry.nextLoanId(), 1);
        assertEq(loanRegistry.ownerOf(loanId), capitalWallet);
        assertEq(loanRegistry.tokenURI(loanId), METADATA_URI);

        ILoanRegistry.ImmutableLoanData memory stored = loanRegistry.immutableLoanData(loanId);
        assertEq(stored.borrowerRef, BORROWER_REF);
        assertEq(stored.originalFacilitySize, FACILITY);
        assertEq(stored.originalSeniorTranche, SENIOR_TRANCHE);
        assertEq(stored.originalEquityTranche, EQUITY_TRANCHE);
        assertEq(stored.originalOfftakerPrice, FACILITY);
        assertEq(stored.seniorInterestRate, RATE);
        assertEq(stored.originationDate, economics.originationDate);
        assertEq(stored.originalMaturityDate, economics.originalMaturityDate);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Approved));
        assertEq(loan.nextEconomicsEpochsId, 0);
        assertEq(loan.nextRepaymentId, 0);
        assertEq(loan.currentMaturityTimestamp, economics.originalMaturityDate);
        assertEq(loan.currentRate, RATE);
        assertEq(uint8(loan.closureReason), uint8(ILoanRegistry.ClosureReason.None));
        assertFalse(loan.carvedOut);
        assertEq(loan.disbursed, 0);
        assertEq(loan.metadataURI, METADATA_URI);

        assertEq(uint8(loanRegistry.status(loanId)), uint8(ILoanRegistry.LoanStatus.Approved));
        assertEq(loanRegistry.outstanding(loanId), 0);
        assertEq(_accruedInterest(loanId), 0);
    }

    function test_drawLoanReverts() public {
        ILoanRegistry.ImmutableLoanData memory economics = _economics();
        economics.originalEquityTranche += 1;

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidTranches.selector);
        loanRegistry.drawLoan(METADATA_URI, economics);

        economics = _economics();
        economics.originalMaturityDate = economics.originationDate;

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidMaturityDate.selector);
        loanRegistry.drawLoan(METADATA_URI, economics);

        economics = _economics();
        economics.originalOfftakerPrice = economics.originalFacilitySize - 1;

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidOfftakerPrice.selector);
        loanRegistry.drawLoan(METADATA_URI, economics);
    }

    function test_nonTransferrable() public {
        uint256 loanId = _drawLoan();
        address recipient = makeAddr("recipient");

        vm.prank(capitalWallet);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonTransferrable.selector);
        loanRegistry.transferFrom(capitalWallet, recipient, loanId);

        vm.prank(capitalWallet);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonTransferrable.selector);
        loanRegistry.approve(recipient, loanId);

        vm.prank(capitalWallet);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonTransferrable.selector);
        loanRegistry.setApprovalForAll(recipient, true);
    }

    function test_updateMutable() public {
        uint256 loanId = _drawAndDisburse();

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.StatusUpdated(loanId, ILoanRegistry.LoanStatus.WatchList);

        vm.prank(loanRegistryManager);
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.WatchList, "watch");

        assertEq(uint8(loanRegistry.status(loanId)), uint8(ILoanRegistry.LoanStatus.WatchList));
        assertEq(loanRegistry.tokenURI(loanId), "watch");

        vm.prank(loanRegistryManager);
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.Performing, "performing");

        assertEq(uint8(loanRegistry.status(loanId)), uint8(ILoanRegistry.LoanStatus.Performing));
        assertEq(loanRegistry.tokenURI(loanId), "performing");

        vm.recordLogs();
        vm.prank(loanRegistryManager);
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.Performing, "metadata only");

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(loanRegistry.tokenURI(loanId), "metadata only");
    }

    function test_updateMutableReverts() public {
        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        loanRegistry.updateMutable(0, ILoanRegistry.LoanStatus.Approved, "");

        uint256 loanId = _drawLoan();

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Approved
            )
        );
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.Performing, "");

        vm.prank(loanRegistryManager);
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.Approved, "approved");
        assertEq(loanRegistry.tokenURI(loanId), "approved");

        _disburse(loanId, SENIOR_TRANCHE);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Performing
            )
        );
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.Default, "");

        _setDefault(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.WatchList, "");

        uint256 closedLoanId = _drawLoan();
        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(closedLoanId, ILoanRegistry.ClosureReason.Cancelled);

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryAlreadyClosed.selector);
        loanRegistry.updateMutable(closedLoanId, ILoanRegistry.LoanStatus.Closed, "");
    }

    function test_disburse() public {
        uint256 loanId = _drawLoan();
        uint256 half = SENIOR_TRANCHE / 2;

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.Disbursed(loanId, half, half);
        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.StatusUpdated(loanId, ILoanRegistry.LoanStatus.Performing);

        _disburse(loanId, half);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Performing));
        assertEq(loan.nextEconomicsEpochsId, 1);
        assertEq(loan.disbursed, half);
        assertEq(loanRegistry.outstanding(loanId), half);
        assertEq(loanRegistry.outstandingTotal(), half);

        ILoanRegistry.EconomicsEpoch memory epoch = loanRegistry.economicsEpoch(loanId, 0);
        assertEq(epoch.accruedInterest, 0);
        assertEq(epoch.effectiveFrom, vm.getBlockTimestamp());
        assertEq(epoch.maturityDate, loan.currentMaturityTimestamp);
        assertEq(epoch.seniorInterestRate, RATE);

        vm.recordLogs();
        _disburse(loanId, half);
        assertEq(vm.getRecordedLogs().length, 1);
        assertEq(loanRegistry.outstandingTotal(), SENIOR_TRANCHE);
    }

    function test_disburseCapitalizesPriorInterest() public {
        uint256 loanId = _drawLoan();
        uint256 half = SENIOR_TRANCHE / 2;
        _disburse(loanId, half);

        skip(YEAR);
        assertEq(_accruedInterest(loanId), 50_000_000);

        _disburse(loanId, half);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(loan.nextEconomicsEpochsId, 2);
        assertEq(loan.disbursed, SENIOR_TRANCHE);
        assertEq(loanRegistry.economicsEpoch(loanId, 1).accruedInterest, 50_000_000);
        assertEq(_accruedInterest(loanId), 50_000_000);

        skip(YEAR);
        assertEq(_accruedInterest(loanId), 150_000_000);
    }

    function test_disburseReverts() public {
        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        loanRegistry.disburse(0, 1);

        uint256 loanId = _drawLoan();

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidAmount.selector);
        loanRegistry.disburse(loanId, 0);

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryDisbursementExceedsTranche.selector,
                SENIOR_TRANCHE + 1,
                SENIOR_TRANCHE
            )
        );
        loanRegistry.disburse(loanId, SENIOR_TRANCHE + 1);

        _disburse(loanId, SENIOR_TRANCHE / 2);
        _setDefault(loanId);

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.disburse(loanId, 1);

        vm.prank(loanRegistryManager);
        loanRegistry.cure(loanId);

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryCarvedOut.selector);
        loanRegistry.disburse(loanId, 1);

        uint256 closedLoanId = _drawLoan();
        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(closedLoanId, ILoanRegistry.ClosureReason.Cancelled);

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Closed
            )
        );
        loanRegistry.disburse(closedLoanId, 1);
    }

    function test_undisburse() public {
        uint256 loanId = _drawLoan();
        uint256 half = SENIOR_TRANCHE / 2;
        _disburse(loanId, half);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.Undisbursed(loanId, half, 0);

        vm.prank(address(minter));
        loanRegistry.undisburse(loanId, half);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(loan.disbursed, 0);
        assertEq(loan.nextEconomicsEpochsId, 2);
        assertEq(loanRegistry.outstanding(loanId), 0);
        assertEq(loanRegistry.outstandingTotal(), 0);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Performing));
    }

    function test_undisburseReverts() public {
        uint256 loanId = _drawLoan();

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Approved
            )
        );
        loanRegistry.undisburse(loanId, 1);

        _disburse(loanId, 300_000_000);
        _disburse(loanId, 200_000_000);

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidAmount.selector);
        loanRegistry.undisburse(loanId, 0);

        _recordPayment(loanId, _principal(400_000_000));

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryAmountExceedsOutstanding.selector, 100_000_000)
        );
        loanRegistry.undisburse(loanId, 200_000_000);

        _setDefault(loanId);
        vm.prank(loanRegistryManager);
        loanRegistry.cure(loanId);

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryCarvedOut.selector);
        loanRegistry.undisburse(loanId, 1);
    }

    function test_recordPayment() public {
        uint256 loanId = _drawAndDisburse();

        skip(YEAR);
        assertEq(_accruedInterest(loanId), 100_000_000);

        ILoanRegistry.RepaymentData memory repayment = ILoanRegistry.RepaymentData({
            offtakerReceived: 72_500_000,
            seniorPrincipalRepaid: 10_000_000,
            seniorInterest: 50_000_000,
            equityDistributed: 0,
            mgmtFee: 10_000_000,
            perfFee: 2_500_000,
            oetAlloc: 0
        });

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.PaymentRecorded(loanId, 0, repayment, SENIOR_TRANCHE - 10_000_000);

        vm.prank(address(minter));
        (uint256 repaymentId, bool carvedOut) = loanRegistry.recordPayment(loanId, repayment);
        assertEq(repaymentId, 0);
        assertFalse(carvedOut);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(loan.nextRepaymentId, 1);
        assertEq(loan.nextEconomicsEpochsId, 2);
        assertEq(loan.repaid, 10_000_000);
        assertEq(loanRegistry.economicsEpoch(loanId, 1).accruedInterest, 100_000_000);

        assertEq(loanRegistry.outstanding(loanId), SENIOR_TRANCHE - 10_000_000);
        assertEq(loanRegistry.outstandingTotal(), SENIOR_TRANCHE - 10_000_000);
        assertEq(_accruedInterest(loanId), 37_500_000);
    }

    function test_recordPaymentReverts() public {
        ILoanRegistry.RepaymentData memory repayment;

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        loanRegistry.recordPayment(0, repayment);

        uint256 loanId = _drawLoan();

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Approved
            )
        );
        loanRegistry.recordPayment(loanId, repayment);

        _disburse(loanId, SENIOR_TRANCHE / 2);
        skip(YEAR);

        repayment.offtakerReceived = 100;
        repayment.seniorPrincipalRepaid = 200;

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryWrongRepaymentData.selector);
        loanRegistry.recordPayment(loanId, repayment);

        repayment = _principal(0);
        repayment.seniorInterest = 50_000_001;
        repayment.offtakerReceived = 50_000_001;

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryInterestExceedsMax.selector, 50_000_000)
        );
        loanRegistry.recordPayment(loanId, repayment);

        repayment = ILoanRegistry.RepaymentData({
            offtakerReceived: 31_250_001,
            seniorPrincipalRepaid: 0,
            seniorInterest: 25_000_000,
            equityDistributed: 0,
            mgmtFee: 5_000_000,
            perfFee: 1_250_000,
            oetAlloc: 1
        });

        vm.prank(address(minter));
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryFeesExceedCap.selector, 6_250_000));
        loanRegistry.recordPayment(loanId, repayment);

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryRepaidExceedsDisbursed.selector,
                SENIOR_TRANCHE / 2 + 1,
                SENIOR_TRANCHE / 2
            )
        );
        loanRegistry.recordPayment(loanId, _principal(SENIOR_TRANCHE / 2 + 1));

        repayment.oetAlloc = 0;
        repayment.offtakerReceived = 31_250_000;
        _recordPayment(loanId, repayment);
    }

    function test_recordPaymentOfftakerExceedsPrice() public {
        uint256 loanId = _drawAndDisburse();
        skip(YEAR);

        ILoanRegistry.RepaymentData memory repayment = ILoanRegistry.RepaymentData({
            offtakerReceived: 1_300_000_000,
            seniorPrincipalRepaid: SENIOR_TRANCHE,
            seniorInterest: 100_000_000,
            equityDistributed: 200_000_000,
            mgmtFee: 0,
            perfFee: 0,
            oetAlloc: 0
        });

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryOfftakerExceedsPrice.selector, 1_300_000_000, FACILITY
            )
        );
        loanRegistry.recordPayment(loanId, repayment);

        repayment.equityDistributed = 100_000_000;
        repayment.offtakerReceived = FACILITY;
        _recordPayment(loanId, repayment);

        vm.prank(address(minter));
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryOfftakerExceedsPrice.selector, FACILITY + 1, FACILITY
            )
        );
        loanRegistry.recordPayment(loanId, _equity(1));
    }

    function test_recordPaymentOnDefault() public {
        uint256 loanId = _drawAndDisburse();
        skip(YEAR);
        _setDefault(loanId);

        ILoanRegistry.RepaymentData memory repayment = _principal(0);
        repayment.mgmtFee = 1;
        repayment.offtakerReceived = 1;

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonZeroOnDefault.selector);
        loanRegistry.recordPayment(loanId, repayment);

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonZeroOnDefault.selector);
        loanRegistry.recordPayment(loanId, _equity(1));

        repayment = _principal(1_000_000);
        repayment.seniorInterest = 1_000_000;
        repayment.offtakerReceived = 2_000_000;
        vm.prank(address(minter));
        (, bool carvedOut) = loanRegistry.recordPayment(loanId, repayment);
        assertTrue(carvedOut);

        assertEq(loanRegistry.outstanding(loanId), SENIOR_TRANCHE - 1_000_000);
        assertEq(uint8(loanRegistry.status(loanId)), uint8(ILoanRegistry.LoanStatus.Default));
    }

    function test_unrecordPayment() public {
        uint256 loanId = _drawAndDisburse();
        skip(YEAR);

        ILoanRegistry.RepaymentData memory repayment = _principal(10_000_000);
        repayment.seniorInterest = 40_000_000;
        repayment.offtakerReceived = 50_000_000;
        uint256 repaymentId = _recordPayment(loanId, repayment);

        assertEq(_accruedInterest(loanId), 60_000_000);
        uint256 outstandingBefore = loanRegistry.outstanding(loanId);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.PaymentUnrecorded(loanId, repaymentId, SENIOR_TRANCHE);

        vm.prank(address(minter));
        (uint256 principal, uint256 interest) = loanRegistry.unrecordPayment(loanId, repaymentId);
        assertEq(principal, 10_000_000);
        assertEq(interest, 40_000_000);

        assertEq(loanRegistry.outstanding(loanId), outstandingBefore + 10_000_000);
        assertEq(loanRegistry.outstandingTotal(), SENIOR_TRANCHE);
        assertEq(loanRegistry.mutableLoanData(loanId).repaid, 0);
        assertEq(_accruedInterest(loanId), 100_000_000);

        _recordPayment(loanId, _equity(FACILITY));
    }

    function test_unrecordPaymentReverts() public {
        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        loanRegistry.unrecordPayment(0, 0);

        uint256 loanId = _drawAndDisburse();

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentRepayment.selector);
        loanRegistry.unrecordPayment(loanId, 0);

        uint256 repaymentId = _recordPayment(loanId, _principal(1));

        vm.prank(address(minter));
        loanRegistry.unrecordPayment(loanId, repaymentId);

        vm.prank(address(minter));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryRepaymentAlreadyReversed.selector);
        loanRegistry.unrecordPayment(loanId, repaymentId);
    }

    function test_setDefault() public {
        uint256 shares = _stake(SENIOR_TRANCHE);
        uint256 loanId = _drawAndDisburse();

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.StatusUpdated(loanId, ILoanRegistry.LoanStatus.Default);
        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanDefaulted(loanId, SENIOR_TRANCHE, SENIOR_TRANCHE);

        _setDefault(loanId);

        ILoanRegistry.LoanMoney memory money = loanRegistry.loanMoney(loanId);
        assertEq(uint8(loanRegistry.status(loanId)), uint8(ILoanRegistry.LoanStatus.Default));
        assertTrue(money.carvedOut);
        assertEq(money.outstanding, SENIOR_TRANCHE);
        assertEq(loanRegistry.outstandingTotal(), SENIOR_TRANCHE);
        assertEq(loanRegistry.unabsorbedTotal(), 0);

        assertEq(plUsd.balanceOf(address(pocket)), SENIOR_TRANCHE);
        assertEq(sPlUsd.totalAssets(), 0);

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(loanId);
        assertEq(pocketData.snapshotBlock, vm.getBlockNumber());
        assertEq(pocketData.supplyAtSnapshot, shares);
        assertEq(pocketData.held, SENIOR_TRANCHE);
    }

    function test_setDefaultShortVault() public {
        _stake(SENIOR_TRANCHE - 1_000_000);
        uint256 loanId = _drawAndDisburse();

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanDefaulted(loanId, SENIOR_TRANCHE, SENIOR_TRANCHE - 1_000_000);

        _setDefault(loanId);

        assertEq(plUsd.balanceOf(address(pocket)), SENIOR_TRANCHE - 1_000_000);
        assertEq(loanRegistry.unabsorbedTotal(), 0);
    }

    function test_cureAndRedefault() public {
        _stake(SENIOR_TRANCHE / 2);
        uint256 loanId = _drawLoan();
        _disburse(loanId, SENIOR_TRANCHE / 2);
        _setDefault(loanId);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.StatusUpdated(loanId, ILoanRegistry.LoanStatus.WatchList);

        vm.prank(loanRegistryManager);
        loanRegistry.cure(loanId);

        assertEq(uint8(loanRegistry.status(loanId)), uint8(ILoanRegistry.LoanStatus.WatchList));
        assertTrue(loanRegistry.loanMoney(loanId).carvedOut);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanDefaulted(loanId, SENIOR_TRANCHE / 2, 0);

        _setDefault(loanId);

        assertEq(uint8(loanRegistry.status(loanId)), uint8(ILoanRegistry.LoanStatus.Default));
        assertEq(pocket.pocket(loanId).held, SENIOR_TRANCHE / 2);
        assertEq(plUsd.balanceOf(address(pocket)), SENIOR_TRANCHE / 2);
    }

    function test_setDefaultReverts() public {
        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        loanRegistry.setDefault(0);

        uint256 loanId = _drawLoan();

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Approved
            )
        );
        loanRegistry.setDefault(loanId);

        _disburse(loanId, SENIOR_TRANCHE);
        vm.mockCall(
            address(sPlUsd),
            abi.encodeCall(IStakedPipelineUSD.carveOut, (loanId, SENIOR_TRANCHE)),
            abi.encode(SENIOR_TRANCHE + 1)
        );

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryCounterpartOverreported.selector, SENIOR_TRANCHE, SENIOR_TRANCHE + 1
            )
        );
        loanRegistry.setDefault(loanId);

        vm.clearMockedCalls();
        _setDefault(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.setDefault(loanId);
    }

    function test_cureReverts() public {
        uint256 loanId = _drawAndDisburse();

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Performing
            )
        );
        loanRegistry.cure(loanId);
    }

    function test_writeDown() public {
        _stake(SENIOR_TRANCHE);
        uint256 loanId = _drawAndDisburse();
        _setDefault(loanId);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanWrittenDown(loanId, 3_000_000, SENIOR_TRANCHE - 3_000_000, 3_000_000, 0);

        vm.prank(loanRegistryManager);
        loanRegistry.writeDown(loanId, 3_000_000);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(loan.writtenDown, 3_000_000);
        assertEq(loan.nextEconomicsEpochsId, 2);
        assertEq(loanRegistry.outstanding(loanId), SENIOR_TRANCHE - 3_000_000);
        assertEq(loanRegistry.outstandingTotal(), SENIOR_TRANCHE - 3_000_000);
        assertEq(loanRegistry.unabsorbedTotal(), 0);

        PocketUpgradeable.PocketData memory pocketData = pocket.pocket(loanId);
        assertEq(pocketData.held, SENIOR_TRANCHE - 3_000_000);
        assertEq(pocketData.burnedTotal, 3_000_000);
        assertEq(plUsd.balanceOf(address(pocket)), SENIOR_TRANCHE - 3_000_000);
        assertEq(plUsd.totalSupply(), SENIOR_TRANCHE - 3_000_000);
    }

    function test_writeDownTracksUnabsorbed() public {
        _stake(2_000_000);
        uint256 loanId = _drawAndDisburse();
        _setDefault(loanId);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanWrittenDown(
            loanId, 3_000_000, SENIOR_TRANCHE - 3_000_000, 2_000_000, 1_000_000
        );

        vm.prank(loanRegistryManager);
        loanRegistry.writeDown(loanId, 3_000_000);

        assertEq(loanRegistry.unabsorbedTotal(), 1_000_000);
    }

    function test_writeDownReverts() public {
        uint256 loanId = _drawAndDisburse();

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Performing
            )
        );
        loanRegistry.writeDown(loanId, 1);

        _setDefault(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidAmount.selector);
        loanRegistry.writeDown(loanId, 0);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryAmountExceedsOutstanding.selector, SENIOR_TRANCHE
            )
        );
        loanRegistry.writeDown(loanId, SENIOR_TRANCHE + 1);

        vm.mockCall(address(pocket), abi.encodeCall(IPocket.burn, (loanId, 1)), abi.encode(uint256(2)));

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryCounterpartOverreported.selector, 1, 2)
        );
        loanRegistry.writeDown(loanId, 1);
    }

    function test_adjustInterest() public {
        uint256 loanId = _drawAndDisburse();
        skip(YEAR);
        uint256 base = _accruedInterest(loanId);
        bytes32 reasonHash = bytes32(uint256(1));

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.InterestAdjusted(loanId, -1_000_000, reasonHash);

        vm.prank(loanRegistryManager);
        loanRegistry.adjustInterest(loanId, -1_000_000, reasonHash);
        assertEq(_accruedInterest(loanId), base - 1_000_000);

        vm.prank(loanRegistryManager);
        loanRegistry.adjustInterest(loanId, 3_000_000, reasonHash);
        assertEq(_accruedInterest(loanId), base + 2_000_000);
        assertEq(loanRegistry.mutableLoanData(loanId).interestAdjustment, 2_000_000);

        vm.prank(loanRegistryManager);
        loanRegistry.adjustInterest(loanId, -int256(base) * 2, reasonHash);
        assertEq(_accruedInterest(loanId), 0);
    }

    function test_adjustInterestReverts() public {
        uint256 loanId = _drawLoan();

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Approved
            )
        );
        loanRegistry.adjustInterest(loanId, 1, bytes32(0));
    }

    function test_closeLoanCancelled() public {
        uint256 loanId = _drawLoan();

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.StatusUpdated(loanId, ILoanRegistry.LoanStatus.Closed);
        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.InterestSettled(loanId, 0, 0, 0);
        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanClosed(loanId, ILoanRegistry.ClosureReason.Cancelled);

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.Cancelled);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Closed));
        assertEq(uint8(loan.closureReason), uint8(ILoanRegistry.ClosureReason.Cancelled));

        uint256 otherLoanId = _drawLoan();
        _disburse(otherLoanId, 1_000);

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryOutstandingNotZero.selector);
        loanRegistry.closeLoan(otherLoanId, ILoanRegistry.ClosureReason.Cancelled);

        vm.prank(address(minter));
        loanRegistry.undisburse(otherLoanId, 1_000);

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(otherLoanId, ILoanRegistry.ClosureReason.Cancelled);
        assertEq(uint8(loanRegistry.status(otherLoanId)), uint8(ILoanRegistry.LoanStatus.Closed));
    }

    function test_closeLoanWaivesResidual() public {
        uint256 loanId = _drawAndDisburse();

        skip(1);
        _recordPayment(loanId, _principal(SENIOR_TRANCHE));
        assertEq(loanRegistry.outstanding(loanId), 0);
        assertEq(_accruedInterest(loanId), 3);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.InterestSettled(loanId, 3, 0, 3);
        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanClosed(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        assertEq(uint8(loanRegistry.status(loanId)), uint8(ILoanRegistry.LoanStatus.Closed));
        assertEq(_accruedInterest(loanId), 0);
    }

    function test_closeLoanReverts() public {
        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        loanRegistry.closeLoan(0, ILoanRegistry.ClosureReason.Cancelled);

        uint256 loanId = _drawAndDisburse();

        ILoanRegistry.ClosureReason[3] memory invalidReasons = [
            ILoanRegistry.ClosureReason.None,
            ILoanRegistry.ClosureReason.Default,
            ILoanRegistry.ClosureReason.OtherWriteDown
        ];
        for (uint256 i = 0; i < invalidReasons.length; ++i) {
            vm.prank(loanRegistryManager);
            vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidClosureReason.selector);
            loanRegistry.closeLoan(loanId, invalidReasons[i]);
        }

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryOutstandingNotZero.selector);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.ScheduledMaturity);

        skip(YEAR);
        _recordPayment(loanId, _principal(SENIOR_TRANCHE));

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryResidualExceedsMax.selector, 100_000_000, maxResidual
            )
        );
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.ScheduledMaturity);

        uint256 defaultedLoanId = _drawAndDisburse();
        _setDefault(defaultedLoanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.closeLoan(defaultedLoanId, ILoanRegistry.ClosureReason.EarlyRepayment);
    }

    function test_closeDefaulted() public {
        uint256 loanId = _drawAndDisburse();
        _setDefault(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryOutstandingNotZero.selector);
        loanRegistry.closeDefaulted(loanId, ILoanRegistry.ClosureReason.Default);

        skip(YEAR);

        vm.prank(loanRegistryManager);
        loanRegistry.writeDown(loanId, SENIOR_TRANCHE);
        assertEq(loanRegistry.outstanding(loanId), 0);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.InterestSettled(loanId, 100_000_000, 0, 100_000_000);
        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanClosed(loanId, ILoanRegistry.ClosureReason.Default);

        vm.prank(loanRegistryManager);
        loanRegistry.closeDefaulted(loanId, ILoanRegistry.ClosureReason.Default);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Closed));
        assertEq(uint8(loan.closureReason), uint8(ILoanRegistry.ClosureReason.Default));
    }

    function test_closeDefaultedReverts() public {
        uint256 loanId = _drawAndDisburse();

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Performing
            )
        );
        loanRegistry.closeDefaulted(loanId, ILoanRegistry.ClosureReason.Default);

        _setDefault(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidClosureReason.selector);
        loanRegistry.closeDefaulted(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);
    }

    function test_rollover() public {
        uint256 loanId = _drawAndDisburse();

        vm.prank(loanRegistryManager);
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.WatchList, "watch");

        uint256 maturity = loanRegistry.mutableLoanData(loanId).currentMaturityTimestamp;
        vm.warp(maturity + 1);

        uint32 newRate = 120_000;
        uint64 newMaturity = uint64(vm.getBlockTimestamp() + YEAR);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanRolledOver(loanId, newRate, newMaturity);

        vm.prank(loanRegistryManager);
        loanRegistry.rollover(loanId, newRate, newMaturity);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.WatchList));
        assertEq(loan.currentMaturityTimestamp, newMaturity);
        assertEq(loan.currentRate, newRate);
        assertEq(loan.nextEconomicsEpochsId, 2);

        uint256 firstEpochInterest = _interest(YEAR + 1, RATE, SENIOR_TRANCHE);
        ILoanRegistry.EconomicsEpoch memory epoch = loanRegistry.economicsEpoch(loanId, 1);
        assertEq(epoch.accruedInterest, firstEpochInterest);
        assertEq(epoch.effectiveFrom, vm.getBlockTimestamp());
        assertEq(epoch.maturityDate, newMaturity);
        assertEq(epoch.seniorInterestRate, newRate);

        skip(YEAR / 2);
        assertEq(_accruedInterest(loanId), firstEpochInterest + 60_000_000);
    }

    function test_rolloverReverts() public {
        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        loanRegistry.rollover(0, RATE, 0);

        uint256 loanId = _drawLoan();
        uint64 newMaturity = uint64(vm.getBlockTimestamp() + 2 * YEAR);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Approved
            )
        );
        loanRegistry.rollover(loanId, RATE, newMaturity);

        _disburse(loanId, SENIOR_TRANCHE);

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNotMatured.selector);
        loanRegistry.rollover(loanId, RATE, newMaturity);

        skip(YEAR);
        _setDefault(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.rollover(loanId, RATE, newMaturity);
    }

    function test_amendEconomicsBeforeFirstDisburse() public {
        uint256 loanId = _drawLoan();
        uint32 newRate = uint32(ONE / 5);
        uint64 newMaturity = uint64(vm.getBlockTimestamp() + 2 * YEAR);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.EconomicsAmended(loanId, newRate, newMaturity);

        vm.prank(loanRegistryManager);
        loanRegistry.amendEconomics(loanId, newRate, newMaturity);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(loan.nextEconomicsEpochsId, 0);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Approved));
        assertEq(loan.currentRate, newRate);
        assertEq(loan.currentMaturityTimestamp, newMaturity);

        _disburse(loanId, SENIOR_TRANCHE);
        ILoanRegistry.EconomicsEpoch memory epoch = loanRegistry.economicsEpoch(loanId, 0);
        assertEq(epoch.seniorInterestRate, newRate);
        assertEq(epoch.maturityDate, newMaturity);

        skip(YEAR);
        assertEq(_accruedInterest(loanId), 200_000_000);
    }

    function test_amendEconomics() public {
        uint256 loanId = _drawAndDisburse();
        skip(YEAR);
        _setDefault(loanId);

        uint32 newRate = uint32(ONE / 5);
        uint64 newMaturity = uint64(vm.getBlockTimestamp() + YEAR);

        vm.prank(loanRegistryManager);
        loanRegistry.amendEconomics(loanId, newRate, newMaturity);

        ILoanRegistry.MutableLoanData memory loan = loanRegistry.mutableLoanData(loanId);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Default));
        assertEq(loan.nextEconomicsEpochsId, 2);

        ILoanRegistry.EconomicsEpoch memory epoch = loanRegistry.economicsEpoch(loanId, 1);
        assertEq(epoch.accruedInterest, 100_000_000);
        assertEq(epoch.seniorInterestRate, newRate);
        assertEq(epoch.maturityDate, newMaturity);

        skip(YEAR / 2);
        assertEq(_accruedInterest(loanId), 200_000_000);
    }

    function test_amendEconomicsReverts() public {
        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        loanRegistry.amendEconomics(0, RATE, 0);

        uint256 loanId = _drawLoan();
        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.Cancelled);

        vm.prank(loanRegistryManager);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryAlreadyClosed.selector);
        loanRegistry.amendEconomics(loanId, RATE, 0);
    }

    function test_setters() public {
        address newAddress = makeAddr("newAddress");

        vm.startPrank(admin);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.CapitalWalletSet(newAddress);
        loanRegistry.setCapitalWallet(newAddress);
        assertEq(loanRegistry.capitalWallet(), newAddress);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.MaxFeeBpsSet(10_000);
        loanRegistry.setMaxFeeBps(10_000);
        assertEq(loanRegistry.maxFeeBps(), 10_000);

        vm.expectEmit(address(loanRegistry));
        emit LoanRegistryUpgradeable.MaxResidualSet(0);
        loanRegistry.setMaxResidual(0);
        assertEq(loanRegistry.maxResidual(), 0);

        vm.stopPrank();

        assertEq(loanRegistry.ownerOf(_drawLoan()), newAddress);
    }

    function test_settersReverts() public {
        vm.startPrank(admin);

        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryZeroAddress.selector);
        loanRegistry.setCapitalWallet(address(0));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistrySameValue.selector);
        loanRegistry.setCapitalWallet(capitalWallet);

        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryInvalidMaxFeeBps.selector);
        loanRegistry.setMaxFeeBps(10_001);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistrySameValue.selector);
        loanRegistry.setMaxFeeBps(maxFeeBps);

        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistrySameValue.selector);
        loanRegistry.setMaxResidual(maxResidual);

        vm.stopPrank();
    }

    function test_initializeRejectsZeroAddresses() public {
        PipelineLoanRegistry implementation = new PipelineLoanRegistry();

        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                PipelineLoanRegistry.initialize, (address(authority), "name", "symbol", address(0), address(pocket))
            )
        );

        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                PipelineLoanRegistry.initialize, (address(authority), "name", "symbol", address(sPlUsd), address(0))
            )
        );
    }

    function test_notConfigured() public {
        PipelineLoanRegistry implementation = new PipelineLoanRegistry();
        bytes memory data = abi.encodeCall(
            PipelineLoanRegistry.initialize, (address(authority), "name", "symbol", address(sPlUsd), address(pocket))
        );
        PipelineLoanRegistry bare = PipelineLoanRegistry(address(new ERC1967Proxy(address(implementation), data)));

        vm.startPrank(admin);

        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNotConfigured.selector);
        bare.drawLoan(METADATA_URI, _economics());

        bare.setCapitalWallet(capitalWallet);
        bare.drawLoan(METADATA_URI, _economics());

        vm.stopPrank();
    }

    function test_pauses() public {
        uint256 loanId = _drawAndDisburse();
        ILoanRegistry.ImmutableLoanData memory economics = _economics();
        ILoanRegistry.RepaymentData memory repayment;

        vm.prank(loanRegistryManager);
        loanRegistry.pause();
        assertTrue(loanRegistry.paused());

        vm.startPrank(loanRegistryManager);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.drawLoan(METADATA_URI, economics);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.updateMutable(loanId, ILoanRegistry.LoanStatus.Performing, "");

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.rollover(loanId, 0, 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.amendEconomics(loanId, 0, 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.setDefault(loanId);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.writeDown(loanId, 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.adjustInterest(loanId, 1, bytes32(0));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.cure(loanId);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.closeDefaulted(loanId, ILoanRegistry.ClosureReason.Default);

        vm.stopPrank();
        vm.startPrank(address(minter));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.disburse(loanId, 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.undisburse(loanId, 1);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.recordPayment(loanId, repayment);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        loanRegistry.unrecordPayment(loanId, 0);

        vm.stopPrank();

        vm.prank(admin);
        loanRegistry.setMaxResidual(maxResidual + 1);

        vm.prank(loanRegistryManager);
        loanRegistry.unpause();
        assertFalse(loanRegistry.paused());
    }

    function test_viewsRevertForUnknownLoans() public {
        bytes memory nonExistent =
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);

        vm.expectRevert(nonExistent);
        loanRegistry.status(0);
        vm.expectRevert(nonExistent);
        loanRegistry.outstanding(0);
        vm.expectRevert(nonExistent);
        loanRegistry.loanMoney(0);
        vm.expectRevert(nonExistent);
        loanRegistry.immutableLoanData(0);
        vm.expectRevert(nonExistent);
        loanRegistry.mutableLoanData(0);
        vm.expectRevert(nonExistent);
        loanRegistry.economicsEpoch(0, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        loanRegistry.tokenURI(0);
    }

    function test_loanMoney() public {
        uint256 loanId = _drawAndDisburse();
        skip(YEAR);

        ILoanRegistry.RepaymentData memory repayment = _principal(100_000_000);
        repayment.seniorInterest = 30_000_000;
        repayment.offtakerReceived = 130_000_000;
        _recordPayment(loanId, repayment);

        _setDefault(loanId);
        vm.prank(loanRegistryManager);
        loanRegistry.writeDown(loanId, 50_000_000);

        ILoanRegistry.LoanMoney memory money = loanRegistry.loanMoney(loanId);
        assertEq(money.disbursed, SENIOR_TRANCHE);
        assertEq(money.repaid, 100_000_000);
        assertEq(money.writtenDown, 50_000_000);
        assertEq(money.outstanding, SENIOR_TRANCHE - 150_000_000);
        assertEq(money.accruedInterest, 70_000_000);
        assertTrue(money.carvedOut);
    }

    function test_outstandingTotalAcrossLoans() public {
        uint256 firstLoanId = _drawAndDisburse();
        uint256 secondLoanId = _drawLoan();
        _disburse(secondLoanId, 300_000_000);

        _recordPayment(firstLoanId, _principal(100_000_000));
        _setDefault(secondLoanId);
        vm.prank(loanRegistryManager);
        loanRegistry.writeDown(secondLoanId, 50_000_000);

        assertEq(
            loanRegistry.outstandingTotal(),
            loanRegistry.outstanding(firstLoanId) + loanRegistry.outstanding(secondLoanId)
        );
        assertEq(loanRegistry.outstandingTotal(), SENIOR_TRANCHE - 100_000_000 + 250_000_000);
    }

    function testFuzz_accruedInterest(uint256 firstDraw, uint256 secondDraw, uint32 rate, uint64 elapsed) public {
        firstDraw = bound(firstDraw, 1, SENIOR_TRANCHE);
        secondDraw = bound(secondDraw, 0, SENIOR_TRANCHE - firstDraw);
        rate = uint32(bound(rate, 0, ONE));
        elapsed = uint64(bound(elapsed, 0, 10 * YEAR));

        uint256 loanId = _drawLoan();
        vm.prank(loanRegistryManager);
        loanRegistry.amendEconomics(loanId, rate, uint64(vm.getBlockTimestamp() + YEAR));

        _disburse(loanId, firstDraw);
        skip(elapsed);

        uint256 expected = _interest(elapsed, rate, firstDraw);
        assertEq(_accruedInterest(loanId), expected);

        if (secondDraw != 0) {
            _disburse(loanId, secondDraw);
            assertEq(_accruedInterest(loanId), expected);

            skip(elapsed);
            assertEq(_accruedInterest(loanId), expected + _interest(elapsed, rate, firstDraw + secondDraw));
        }
    }

    function _economics() private view returns (ILoanRegistry.ImmutableLoanData memory) {
        return ILoanRegistry.ImmutableLoanData({
            borrowerRef: BORROWER_REF,
            originalFacilitySize: FACILITY,
            originalSeniorTranche: SENIOR_TRANCHE,
            originalEquityTranche: EQUITY_TRANCHE,
            originalOfftakerPrice: FACILITY,
            seniorInterestRate: RATE,
            originationDate: uint64(vm.getBlockTimestamp()),
            originalMaturityDate: uint64(vm.getBlockTimestamp() + YEAR)
        });
    }

    function _stake(uint256 amount) private returns (uint256 shares) {
        deal(address(plUsd), staker, amount, true);

        vm.startPrank(staker);
        plUsd.approve(address(sPlUsd), amount);
        shares = sPlUsd.deposit(amount, staker);
        vm.stopPrank();
    }

    function _drawLoan() private returns (uint256 loanId) {
        ILoanRegistry.ImmutableLoanData memory economics = _economics();
        vm.prank(loanRegistryManager);
        return loanRegistry.drawLoan(METADATA_URI, economics);
    }

    function _drawAndDisburse() private returns (uint256 loanId) {
        loanId = _drawLoan();
        _disburse(loanId, SENIOR_TRANCHE);
    }

    function _disburse(uint256 loanId, uint256 amount) private {
        vm.prank(address(minter));
        loanRegistry.disburse(loanId, amount);
    }

    function _recordPayment(uint256 loanId, ILoanRegistry.RepaymentData memory repayment)
        private
        returns (uint256 repaymentId)
    {
        vm.prank(address(minter));
        (repaymentId,) = loanRegistry.recordPayment(loanId, repayment);
    }

    function _setDefault(uint256 loanId) private {
        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId);
    }

    function _principal(uint256 amount) private pure returns (ILoanRegistry.RepaymentData memory repayment) {
        repayment.offtakerReceived = amount;
        repayment.seniorPrincipalRepaid = amount;
    }

    function _equity(uint256 amount) private pure returns (ILoanRegistry.RepaymentData memory repayment) {
        repayment.offtakerReceived = amount;
        repayment.equityDistributed = amount;
    }

    function _accruedInterest(uint256 loanId) private view returns (uint256) {
        return loanRegistry.loanMoney(loanId).accruedInterest;
    }

    function _interest(uint256 elapsed, uint256 rate, uint256 principal) private pure returns (uint256) {
        return elapsed * rate * principal / (YEAR * ONE);
    }
}
