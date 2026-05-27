// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {LoanRegistryUpgradeable} from "../src/loanRegistry/LoanRegistryUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract LoanRegistryTest is PipelineTestSetUp {
    function test_setUp() public view {
        assertEq(loanRegistry.authority(), address(authority));
        assertEq(loanRegistry.name(), "Loan registry name");
        assertEq(loanRegistry.symbol(), "Loan registry symbol");
    }

    function test_drawLoan() public {
        address loanOwner = makeAddr("loanOwner");
        string memory metadataURI = "test_drawLoan_metadataURI";
        uint64 initialMaturity = uint64(block.timestamp + 100);
        string memory location = "location";
        uint32 initialCcrBps = 1_000_000;

        uint256 nextLoanId = loanRegistry.nextLoanId();

        ILoanRegistry.ImmutableLoanData memory loanData = ILoanRegistry.ImmutableLoanData({
            seniorTranche: 1_000_000_000,
            equityTranche: 1_000_000,
            offtakerPrice: 2_000_000,
            rateBps: 1_000_000,
            originationTimestamp: uint128(block.timestamp),
            originalMaturityTimestamp: uint128(block.timestamp + 100),
            facility: "facility"
        });

        vm.prank(loanRegistryManager);
        uint256 loanId = loanRegistry.drawLoan(loanOwner, metadataURI, loanData, initialCcrBps, location);

        assertEq(loanId, nextLoanId);
        assertEq(loanRegistry.nextLoanId(), loanId + 1);

        assertEq(loanRegistry.tokenURI(loanId), metadataURI);

        ILoanRegistry.ImmutableLoanData memory immutableLoanData = loanRegistry.immutableLoanData(loanId);
        assertEq(immutableLoanData.seniorTranche, loanData.seniorTranche);
        assertEq(immutableLoanData.equityTranche, loanData.equityTranche);
        assertEq(immutableLoanData.offtakerPrice, loanData.offtakerPrice);
        assertEq(immutableLoanData.rateBps, loanData.rateBps);
        assertEq(immutableLoanData.originationTimestamp, loanData.originationTimestamp);
        assertEq(immutableLoanData.originalMaturityTimestamp, loanData.originalMaturityTimestamp);
        assertEq(immutableLoanData.facility, loanData.facility);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Performing));
        assertEq(mutableLoanData.ccrBps, initialCcrBps);
        assertEq(mutableLoanData.currentMaturityDate, initialMaturity);
        assertEq(mutableLoanData.location, location);
        assertEq(uint256(mutableLoanData.closureReason), uint256(ILoanRegistry.ClosureReason.None));
    }

    function test_updateStatus() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        ILoanRegistry.LoanStatus newStatus = ILoanRegistry.LoanStatus.WatchList;
        assertNotEq(uint256(mutableDataBefore.status), uint256(newStatus));

        vm.prank(loanRegistryManager);
        loanRegistry.updateStatus(loanId, newStatus);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(newStatus));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, mutableDataBefore.location);
        assertEq(mutableLoanData.currentMaturityDate, mutableDataBefore.currentMaturityDate);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));
    }

    function test_updateStatusReverts() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.updateStatus(loanId + 1, mutableDataBefore.status);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryInapplicableStatus.selector,
                loanId,
                ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.updateStatus(loanId, ILoanRegistry.LoanStatus.Default);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryInapplicableStatus.selector, loanId, ILoanRegistry.LoanStatus.Closed
            )
        );
        loanRegistry.updateStatus(loanId, ILoanRegistry.LoanStatus.Closed);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistrySameStatus.selector, loanId));
        loanRegistry.updateStatus(loanId, mutableDataBefore.status);

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId, 0);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector,
                loanId,
                ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.updateStatus(loanId, mutableDataBefore.status);

        loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, loanId, ILoanRegistry.LoanStatus.Closed
            )
        );
        loanRegistry.updateStatus(loanId, mutableDataBefore.status);
    }

    function test_updateCCR() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        uint32 newCcrBps = 1;
        assertNotEq(mutableDataBefore.ccrBps, newCcrBps);

        vm.prank(loanRegistryManager);
        loanRegistry.updateCCR(loanId, newCcrBps);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(mutableDataBefore.status));
        assertEq(mutableLoanData.ccrBps, newCcrBps);
        assertEq(mutableLoanData.location, mutableDataBefore.location);
        assertEq(mutableLoanData.currentMaturityDate, mutableDataBefore.currentMaturityDate);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));
    }

    function test_updateCCRReverts() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.updateCCR(loanId + 1, mutableDataBefore.ccrBps + 1);

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, loanId, ILoanRegistry.LoanStatus.Closed
            )
        );
        loanRegistry.updateCCR(loanId, mutableDataBefore.ccrBps + 1);
    }

    function test_updateLocation() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        string memory newLocation = "newLocation";
        assertNotEq(mutableDataBefore.location, newLocation);

        vm.prank(loanRegistryManager);
        loanRegistry.updateLocation(loanId, newLocation);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(mutableDataBefore.status));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, newLocation);
        assertEq(mutableLoanData.currentMaturityDate, mutableDataBefore.currentMaturityDate);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));
    }

    function test_updateLocationReverts() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        string memory newLocation = "newLocation";

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.updateLocation(loanId + 1, newLocation);

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, loanId, ILoanRegistry.LoanStatus.Closed
            )
        );
        loanRegistry.updateLocation(loanId, newLocation);
    }

    function test_setDefault() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        uint32 ccrBps = 0;

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId, ccrBps);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Default));
        assertEq(mutableLoanData.ccrBps, ccrBps);
        assertEq(mutableLoanData.location, mutableLoanData.location);
        assertEq(mutableLoanData.currentMaturityDate, mutableDataBefore.currentMaturityDate);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));
    }

    function test_setDefaultReverts() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.setDefault(loanId + 1, 0);

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId, 0);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector,
                loanId,
                ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.setDefault(loanId, 0);

        loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector, loanId, ILoanRegistry.LoanStatus.Closed
            )
        );
        loanRegistry.updateStatus(loanId, mutableDataBefore.status);
    }

    function test_closeLoan() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));
        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        ILoanRegistry.ClosureReason closureReason = ILoanRegistry.ClosureReason.EarlyRepayment;

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, closureReason);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Closed));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, mutableLoanData.location);
        assertEq(mutableLoanData.currentMaturityDate, mutableDataBefore.currentMaturityDate);
        assertEq(uint256(mutableLoanData.closureReason), uint256(closureReason));
    }

    function test_closeLoanReverts() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.closeLoan(loanId + 1, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId, 0);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector,
                loanId,
                ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryAlreadyClosed.selector, loanId));
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);
    }

    function test_recordPayment() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.RepaymentData memory repaymentDataBefore = loanRegistry.repaymentData(loanId);

        ILoanRegistry.RepaymentData memory repayment = ILoanRegistry.RepaymentData({
            offtakerAmount: 1_000_000_000_000_000,
            equityDistributed: 1_000_000_000_000,
            seniorPrincipalRepaid: 2_000_000_000_000,
            seniorInterest: 3_000_000_000_000,
            mgmtFee: 4_000_000_000_000,
            perfFee: 5_000_000_000_000,
            oetAlloc: 6_000_000_000_000
        });

        vm.prank(loanRegistryManager);
        loanRegistry.recordPayment(loanId, repayment);

        ILoanRegistry.RepaymentData memory repaymentDataAfter = loanRegistry.repaymentData(loanId);

        assertEq(repaymentDataAfter.offtakerAmount, repaymentDataBefore.offtakerAmount + repayment.offtakerAmount);
        assertEq(
            repaymentDataAfter.seniorPrincipalRepaid,
            repaymentDataBefore.seniorPrincipalRepaid + repayment.seniorPrincipalRepaid
        );
        assertEq(repaymentDataAfter.seniorInterest, repaymentDataBefore.seniorInterest + repayment.seniorInterest);
        assertEq(
            repaymentDataAfter.equityDistributed, repaymentDataBefore.equityDistributed + repayment.equityDistributed
        );
        assertEq(repaymentDataAfter.mgmtFee, repaymentDataBefore.mgmtFee + repayment.mgmtFee);
        assertEq(repaymentDataAfter.perfFee, repaymentDataBefore.perfFee + repayment.perfFee);
        assertEq(repaymentDataAfter.oetAlloc, repaymentDataBefore.oetAlloc + repayment.oetAlloc);
    }

    function test_recordPaymentWrongData() public {
        ILoanRegistry.RepaymentData memory repayment = ILoanRegistry.RepaymentData({
            offtakerAmount: 1_000_000,
            equityDistributed: 1_000_000_000_000,
            seniorPrincipalRepaid: 2_000_000_000_000,
            seniorInterest: 3_000_000_000_000,
            mgmtFee: 4_000_000_000_000,
            perfFee: 5_000_000_000_000,
            oetAlloc: 6_000_000_000_000
        });

        assert(
            repayment.offtakerAmount
                < repayment.equityDistributed + repayment.seniorPrincipalRepaid + repayment.seniorInterest
        );

        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryWrongRepaymentData.selector));
        loanRegistry.recordPayment(loanId, repayment);
    }

    function test_nonTransferrable() public {
        address loanOwner = makeAddr("loanOwner");
        address recipient = makeAddr("recipient");

        uint256 loanId = _drawDefaultLoan(loanOwner);

        vm.prank(loanOwner);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonTransferrable.selector));
        loanRegistry.transferFrom(loanOwner, recipient, loanId);
    }

    function test_pauses() public {
        address loanOwner = makeAddr("loanOwner");

        vm.prank(loanRegistryManager);
        loanRegistry.pause();

        assert(loanRegistry.paused());

        ILoanRegistry.ImmutableLoanData memory loanData;
        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.drawLoan(loanOwner, "", loanData, 0, "");

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.updateStatus(0, ILoanRegistry.LoanStatus.Default);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.updateCCR(0, 0);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.updateLocation(0, "newLocation");

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.setDefault(0, 0);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.closeLoan(0, ILoanRegistry.ClosureReason.EarlyRepayment);

        ILoanRegistry.RepaymentData memory repayment;

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.recordPayment(0, repayment);

        vm.prank(loanRegistryManager);
        loanRegistry.unpause();

        assert(!loanRegistry.paused());
    }

    function _drawDefaultLoan(address to) private returns (uint256 loanId) {
        string memory defaultMetadataURI = "defaultMetadataURI";

        ILoanRegistry.ImmutableLoanData memory loanData = ILoanRegistry.ImmutableLoanData({
            seniorTranche: 1_000_000_000,
            equityTranche: 1_000_000,
            offtakerPrice: 2_000_000,
            rateBps: 1_000_000,
            originationTimestamp: uint128(block.timestamp),
            originalMaturityTimestamp: uint128(block.timestamp + 100),
            facility: "facility"
        });

        vm.prank(loanRegistryManager);
        return loanRegistry.drawLoan(to, defaultMetadataURI, loanData, 1_000_000, "location");
    }
}
