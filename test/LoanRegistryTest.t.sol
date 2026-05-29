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
        uint32 initialCcrBps = 1_000_000;

        uint256 nextLoanId = loanRegistry.nextLoanId();

        ILoanRegistry.ImmutableLoanData memory loanData = ILoanRegistry.ImmutableLoanData({
            originalFacilitySize: 1_000_000_000,
            originalSeniorTranche: 1_000_000,
            originalEquityTranche: 2_000_000,
            originalOfftakerPrice: 3_000_000,
            seniorInterestRateBps: 1_000_000,
            originationDate: uint64(block.timestamp),
            originalMaturityDate: uint64(block.timestamp + 100)
        });

        ILoanRegistry.LocationUpdate memory location = ILoanRegistry.LocationUpdate({
            locationType: ILoanRegistry.LocationType.Vessel,
            locationIdentifier: "locationIdentifier",
            trackingURL: "trackingURL",
            updatedAt: uint64(block.timestamp)
        });

        vm.prank(loanRegistryManager);
        uint256 loanId = loanRegistry.drawLoan(loanOwner, metadataURI, loanData, initialCcrBps, location);

        assertEq(loanId, nextLoanId);
        assertEq(loanRegistry.nextLoanId(), loanId + 1);

        assertEq(loanRegistry.tokenURI(loanId), metadataURI);

        ILoanRegistry.ImmutableLoanData memory immutableLoanData = loanRegistry.immutableLoanData(loanId);
        assertEq(immutableLoanData.originalFacilitySize, loanData.originalFacilitySize);
        assertEq(immutableLoanData.originalSeniorTranche, loanData.originalSeniorTranche);
        assertEq(immutableLoanData.originalEquityTranche, loanData.originalEquityTranche);
        assertEq(immutableLoanData.originalOfftakerPrice, loanData.originalOfftakerPrice);
        assertEq(immutableLoanData.seniorInterestRateBps, loanData.seniorInterestRateBps);
        assertEq(immutableLoanData.originationDate, loanData.originationDate);
        assertEq(immutableLoanData.originalMaturityDate, loanData.originalMaturityDate);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Performing));
        assertEq(mutableLoanData.ccrBps, initialCcrBps);
        assertEq(mutableLoanData.currentMaturityTimestamp, initialMaturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(ILoanRegistry.ClosureReason.None));

        assertEq(uint8(mutableLoanData.currentLocation.locationType), uint8(location.locationType));
        assertEq(mutableLoanData.currentLocation.locationIdentifier, location.locationIdentifier);
        assertEq(mutableLoanData.currentLocation.trackingURL, location.trackingURL);
        assertEq(mutableLoanData.currentLocation.updatedAt, location.updatedAt);
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
        assertEq(mutableLoanData.currentMaturityTimestamp, mutableDataBefore.currentMaturityTimestamp);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));

        assertEq(
            uint8(mutableLoanData.currentLocation.locationType), uint8(mutableDataBefore.currentLocation.locationType)
        );
        assertEq(
            mutableLoanData.currentLocation.locationIdentifier, mutableDataBefore.currentLocation.locationIdentifier
        );
        assertEq(mutableLoanData.currentLocation.trackingURL, mutableDataBefore.currentLocation.trackingURL);
        assertEq(mutableLoanData.currentLocation.updatedAt, mutableDataBefore.currentLocation.updatedAt);
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

        // TODO: updateMutableData
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
        assertEq(mutableLoanData.currentMaturityTimestamp, mutableDataBefore.currentMaturityTimestamp);
        assertEq(uint256(mutableLoanData.closureReason), uint256(closureReason));

        assertEq(
            uint8(mutableLoanData.currentLocation.locationType), uint8(mutableDataBefore.currentLocation.locationType)
        );
        assertEq(
            mutableLoanData.currentLocation.locationIdentifier, mutableDataBefore.currentLocation.locationIdentifier
        );
        assertEq(mutableLoanData.currentLocation.trackingURL, mutableDataBefore.currentLocation.trackingURL);
        assertEq(mutableLoanData.currentLocation.updatedAt, mutableDataBefore.currentLocation.updatedAt);
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
        assert(!loanRegistry.canYieldBeMinted(loanRegistry.nextLoanId(), 0));
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.RepaymentData memory repaymentDataBefore = loanRegistry.cumulativeRepaymentData(loanId);
        uint256 nextRepaymentIdBefore = loanRegistry.mutableLoanData(loanId).nextRepaymentId;

        assert(!loanRegistry.canYieldBeMinted(loanId, nextRepaymentIdBefore));

        ILoanRegistry.RepaymentData memory repayment = ILoanRegistry.RepaymentData({
            offtakerReceived: 1_000_000_000_000_000,
            equityDistributed: 1_000_000_000_000,
            seniorPrincipalRepaid: 2_000_000_000_000,
            seniorInterest: 3_000_000_000_000,
            mgmtFee: 4_000_000_000_000,
            perfFee: 5_000_000_000_000,
            oetAlloc: 6_000_000_000_000
        });

        vm.prank(loanRegistryManager);
        uint256 repaymentId = loanRegistry.recordPayment(loanId, repayment);

        assertEq(repaymentId, nextRepaymentIdBefore);
        assertEq(loanRegistry.mutableLoanData(loanId).nextRepaymentId, repaymentId + 1);
        assert(loanRegistry.canYieldBeMinted(loanId, repaymentId));

        ILoanRegistry.RepaymentData memory cumulativeRepaymentDataAfter = loanRegistry.cumulativeRepaymentData(loanId);

        assertEq(
            cumulativeRepaymentDataAfter.offtakerReceived,
            repaymentDataBefore.offtakerReceived + repayment.offtakerReceived
        );
        assertEq(
            cumulativeRepaymentDataAfter.seniorPrincipalRepaid,
            repaymentDataBefore.seniorPrincipalRepaid + repayment.seniorPrincipalRepaid
        );
        assertEq(
            cumulativeRepaymentDataAfter.seniorInterest, repaymentDataBefore.seniorInterest + repayment.seniorInterest
        );
        assertEq(
            cumulativeRepaymentDataAfter.equityDistributed,
            repaymentDataBefore.equityDistributed + repayment.equityDistributed
        );
        assertEq(cumulativeRepaymentDataAfter.mgmtFee, repaymentDataBefore.mgmtFee + repayment.mgmtFee);
        assertEq(cumulativeRepaymentDataAfter.perfFee, repaymentDataBefore.perfFee + repayment.perfFee);
        assertEq(cumulativeRepaymentDataAfter.oetAlloc, repaymentDataBefore.oetAlloc + repayment.oetAlloc);

        ILoanRegistry.RepaymentData memory repaymentData = loanRegistry.repaymentData(loanId, repaymentId);

        assertEq(repaymentData.offtakerReceived, repayment.offtakerReceived);
        assertEq(repaymentData.seniorPrincipalRepaid, repayment.seniorPrincipalRepaid);
        assertEq(repaymentData.seniorInterest, repayment.seniorInterest);
        assertEq(repaymentData.equityDistributed, repayment.equityDistributed);
        assertEq(repaymentData.mgmtFee, repayment.mgmtFee);
        assertEq(repaymentData.perfFee, repayment.perfFee);
        assertEq(repaymentData.oetAlloc, repayment.oetAlloc);
    }

    function test_markMintedReverts() public {
        uint256 nextLoadId = loanRegistry.nextLoanId();

        vm.prank(address(yieldMinter));
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, nextLoadId)
        );
        loanRegistry.markMinted(nextLoadId, 0);

        _drawDefaultLoan(makeAddr("loanOwner"));

        vm.prank(address(yieldMinter));
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentRepayment.selector, nextLoadId, 0)
        );
        loanRegistry.markMinted(nextLoadId, 0);
    }

    function test_recordPaymentWrongData() public {
        ILoanRegistry.RepaymentData memory repayment = ILoanRegistry.RepaymentData({
            offtakerReceived: 1_000_000,
            equityDistributed: 1_000_000_000_000,
            seniorPrincipalRepaid: 2_000_000_000_000,
            seniorInterest: 3_000_000_000_000,
            mgmtFee: 4_000_000_000_000,
            perfFee: 5_000_000_000_000,
            oetAlloc: 6_000_000_000_000
        });

        assert(
            repayment.offtakerReceived
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
        ILoanRegistry.LocationUpdate memory location;
        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.drawLoan(loanOwner, "", loanData, 0, location);

        // TODO: updateMutableData

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
            originalFacilitySize: 1_000_000_000,
            originalSeniorTranche: 1_000_000,
            originalEquityTranche: 2_000_000,
            originalOfftakerPrice: 3_000_000,
            seniorInterestRateBps: 1_000_000,
            originationDate: uint64(block.timestamp),
            originalMaturityDate: uint64(block.timestamp + 100)
        });

        ILoanRegistry.LocationUpdate memory location = ILoanRegistry.LocationUpdate({
            locationType: ILoanRegistry.LocationType.Vessel,
            locationIdentifier: "locationIdentifier",
            trackingURL: "trackingURL",
            updatedAt: uint64(block.timestamp)
        });

        vm.prank(loanRegistryManager);
        return loanRegistry.drawLoan(to, defaultMetadataURI, loanData, 1_000_000, location);
    }
}
