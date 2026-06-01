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
        uint32 initialCcr = 1_000_000;

        uint256 nextLoanId = loanRegistry.nextLoanId();

        ILoanRegistry.ImmutableLoanData memory loanData = ILoanRegistry.ImmutableLoanData({
            originalFacilitySize: 1_000_000_000,
            originalSeniorTranche: 600_000_000,
            originalEquityTranche: 400_000_000,
            originalOfftakerPrice: 3_000_000_000,
            seniorInterestRate: 1_000_000,
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
        uint256 loanId = loanRegistry.drawLoan(loanOwner, metadataURI, loanData, initialCcr, location);

        assertEq(loanId, nextLoanId);
        assertEq(loanRegistry.nextLoanId(), loanId + 1);

        assertEq(loanRegistry.tokenURI(loanId), metadataURI);

        ILoanRegistry.ImmutableLoanData memory immutableLoanData = loanRegistry.immutableLoanData(loanId);
        assertEq(immutableLoanData.originalFacilitySize, loanData.originalFacilitySize);
        assertEq(immutableLoanData.originalSeniorTranche, loanData.originalSeniorTranche);
        assertEq(immutableLoanData.originalEquityTranche, loanData.originalEquityTranche);
        assertEq(immutableLoanData.originalOfftakerPrice, loanData.originalOfftakerPrice);
        assertEq(immutableLoanData.seniorInterestRate, loanData.seniorInterestRate);
        assertEq(immutableLoanData.originationDate, loanData.originationDate);
        assertEq(immutableLoanData.originalMaturityDate, loanData.originalMaturityDate);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Performing));
        assertEq(mutableLoanData.ccr, initialCcr);
        assertEq(mutableLoanData.currentMaturityTimestamp, initialMaturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(ILoanRegistry.ClosureReason.None));

        assertEq(uint8(mutableLoanData.currentLocation.locationType), uint8(location.locationType));
        assertEq(mutableLoanData.currentLocation.locationIdentifier, location.locationIdentifier);
        assertEq(mutableLoanData.currentLocation.trackingURL, location.trackingURL);
        assertEq(mutableLoanData.currentLocation.updatedAt, location.updatedAt);

        assertEq(mutableLoanData.nextEconomicsEpochsId, 1);

        ILoanRegistry.EconomicsEpoch memory epoch = loanRegistry.economicsEpoch(loanId, 0);
        assertEq(epoch.accruedInterest, 0);
        assertEq(epoch.effectiveFrom, loanData.originationDate);
        assertEq(epoch.maturityDate, loanData.originalMaturityDate);
        assertEq(epoch.seniorInterestRate, loanData.seniorInterestRate);
    }

    function test_updateMutable() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        string memory newMetadataURI = "newMetadataURI";
        ILoanRegistry.LoanStatus newStatus = ILoanRegistry.LoanStatus.WatchList;
        uint32 newCcr = 2_000_000;
        ILoanRegistry.LocationUpdate memory newLocation = ILoanRegistry.LocationUpdate({
            locationType: ILoanRegistry.LocationType.Warehouse,
            locationIdentifier: "newLocationIdentifier",
            trackingURL: "newTrackingURL",
            updatedAt: uint64(block.timestamp)
        });

        vm.prank(loanRegistryManager);
        loanRegistry.updateMutable(loanId, newMetadataURI, newStatus, newCcr, newLocation);

        assertEq(loanRegistry.tokenURI(loanId), newMetadataURI);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(newStatus));
        assertEq(mutableLoanData.ccr, newCcr);
        assertEq(mutableLoanData.lastReportedCCRTimestamp, uint64(block.timestamp));

        assertEq(uint8(mutableLoanData.currentLocation.locationType), uint8(newLocation.locationType));
        assertEq(mutableLoanData.currentLocation.locationIdentifier, newLocation.locationIdentifier);
        assertEq(mutableLoanData.currentLocation.trackingURL, newLocation.trackingURL);
        assertEq(mutableLoanData.currentLocation.updatedAt, newLocation.updatedAt);
    }

    function test_rollover() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        vm.warp(block.timestamp + loanRegistry.YEAR());

        uint256 nextEpochIdBefore = loanRegistry.mutableLoanData(loanId).nextEconomicsEpochsId;

        uint32 newRate = 2_000_000;
        uint64 rolloverTimestamp = uint64(block.timestamp);
        uint64 newMaturity = uint64(block.timestamp + loanRegistry.YEAR());

        vm.expectEmit(true, false, false, true, address(loanRegistry));
        emit LoanRegistryUpgradeable.LoanRolledOver(loanId, newRate, newMaturity);

        vm.prank(loanRegistryManager);
        loanRegistry.rollover(loanId, newRate, newMaturity);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Performing));
        assertEq(mutableLoanData.currentMaturityTimestamp, newMaturity);
        assertEq(mutableLoanData.nextEconomicsEpochsId, nextEpochIdBefore + 1);

        ILoanRegistry.EconomicsEpoch memory epoch = loanRegistry.economicsEpoch(loanId, nextEpochIdBefore);
        assertEq(epoch.accruedInterest, 600_000_000);
        assertEq(epoch.effectiveFrom, rolloverTimestamp);
        assertEq(epoch.maturityDate, newMaturity);
        assertEq(epoch.seniorInterestRate, newRate);

        vm.warp(block.timestamp + loanRegistry.YEAR() / 2);
        assertEq(loanRegistry.maxInterest(loanId), 1_200_000_000);
    }

    function test_rolloverReverts() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));
        uint64 newMaturity = uint64(block.timestamp + 2 * loanRegistry.YEAR());

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.rollover(loanId + 1, 1_000_000, newMaturity);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNotMatured.selector, loanId));
        loanRegistry.rollover(loanId, 1_000_000, newMaturity);

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
        loanRegistry.rollover(loanId, 1_000_000, newMaturity);
    }

    function test_amendEconomics() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        vm.warp(block.timestamp + loanRegistry.YEAR());

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId, 0);

        uint256 nextEpochIdBefore = loanRegistry.mutableLoanData(loanId).nextEconomicsEpochsId;

        uint32 newRate = 2_000_000;
        uint64 amendTimestamp = uint64(block.timestamp);
        uint64 newMaturity = uint64(block.timestamp + loanRegistry.YEAR());

        vm.expectEmit(true, false, false, true, address(loanRegistry));
        emit LoanRegistryUpgradeable.EconomicsAmended(loanId, newRate, newMaturity);

        vm.prank(loanRegistryManager);
        loanRegistry.amendEconomics(loanId, newRate, newMaturity);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Performing));
        assertEq(mutableLoanData.currentMaturityTimestamp, newMaturity);
        assertEq(mutableLoanData.nextEconomicsEpochsId, nextEpochIdBefore + 1);

        ILoanRegistry.EconomicsEpoch memory epoch = loanRegistry.economicsEpoch(loanId, nextEpochIdBefore);
        assertEq(epoch.accruedInterest, 600_000_000);
        assertEq(epoch.effectiveFrom, amendTimestamp);
        assertEq(epoch.maturityDate, newMaturity);
        assertEq(epoch.seniorInterestRate, newRate);

        vm.warp(block.timestamp + loanRegistry.YEAR() / 2);
        assertEq(loanRegistry.maxInterest(loanId), 1_200_000_000);
    }

    function test_amendEconomicsReverts() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));
        uint64 newMaturity = uint64(block.timestamp + 2 * loanRegistry.YEAR());

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.amendEconomics(loanId + 1, 1_000_000, newMaturity);

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryAlreadyClosed.selector, loanId));
        loanRegistry.amendEconomics(loanId, 1_000_000, newMaturity);
    }

    function test_setDefault() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        uint32 ccr = 0;

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId, ccr);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Default));
        assertEq(mutableLoanData.ccr, ccr);
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

        ILoanRegistry.LocationUpdate memory location;

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector,
                loanId,
                ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.updateMutable(loanId, "", ILoanRegistry.LoanStatus.Default, 1_000_000, location);
    }

    function test_closeLoan() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));
        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        ILoanRegistry.ClosureReason closureReason = ILoanRegistry.ClosureReason.EarlyRepayment;

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, closureReason);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Closed));
        assertEq(mutableLoanData.ccr, mutableDataBefore.ccr);
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
        uint256 nextEpochIdBefore = loanRegistry.mutableLoanData(loanId).nextEconomicsEpochsId;

        assert(!loanRegistry.canYieldBeMinted(loanId, nextRepaymentIdBefore));

        vm.warp(loanRegistry.YEAR() / 2);

        ILoanRegistry.RepaymentData memory repayment = ILoanRegistry.RepaymentData({
            offtakerReceived: 1_000_000_000,
            equityDistributed: 100_000_000,
            seniorPrincipalRepaid: 500_000_000,
            seniorInterest: 250_000_000,
            mgmtFee: 4_000_000,
            perfFee: 5_000_000,
            oetAlloc: 6_000_000
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

        assertEq(loanRegistry.mutableLoanData(loanId).nextEconomicsEpochsId, nextEpochIdBefore + 1);

        ILoanRegistry.ImmutableLoanData memory immutableData = loanRegistry.immutableLoanData(loanId);
        ILoanRegistry.EconomicsEpoch memory epoch = loanRegistry.economicsEpoch(loanId, nextEpochIdBefore);
        assertEq(epoch.accruedInterest, 299_999_400);
        assertEq(epoch.effectiveFrom, loanRegistry.YEAR() / 2);
        assertEq(epoch.maturityDate, immutableData.originalMaturityDate);
        assertEq(epoch.seniorInterestRate, immutableData.seniorInterestRate);

        _assertSeniorInterestMaxEdge();
    }

    function test_recordPaymentSeniorInterest() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.RepaymentData[3] memory repayments = [
            ILoanRegistry.RepaymentData({
                offtakerReceived: 400_000_000,
                equityDistributed: 10_000_000,
                seniorPrincipalRepaid: 50_000_000,
                seniorInterest: 100_000_000,
                mgmtFee: 1_000_000,
                perfFee: 2_000_000,
                oetAlloc: 3_000_000
            }),
            ILoanRegistry.RepaymentData({
                offtakerReceived: 300_000_000,
                equityDistributed: 20_000_000,
                seniorPrincipalRepaid: 40_000_000,
                seniorInterest: 75_000_000,
                mgmtFee: 1_000_000,
                perfFee: 2_000_000,
                oetAlloc: 3_000_000
            }),
            ILoanRegistry.RepaymentData({
                offtakerReceived: 500_000_000,
                equityDistributed: 30_000_000,
                seniorPrincipalRepaid: 60_000_000,
                seniorInterest: 200_000_000,
                mgmtFee: 1_000_000,
                perfFee: 2_000_000,
                oetAlloc: 3_000_000
            })
        ];

        uint256 expectedCumulativeSeniorInterest = loanRegistry.cumulativeRepaymentData(loanId).seniorInterest;

        for (uint256 i = 0; i < repayments.length; i++) {
            vm.warp(block.timestamp + loanRegistry.YEAR() / 4);

            vm.prank(loanRegistryManager);
            uint256 repaymentId = loanRegistry.recordPayment(loanId, repayments[i]);

            expectedCumulativeSeniorInterest += repayments[i].seniorInterest;

            assertEq(loanRegistry.repaymentData(loanId, repaymentId).seniorInterest, repayments[i].seniorInterest);

            assertEq(loanRegistry.cumulativeRepaymentData(loanId).seniorInterest, expectedCumulativeSeniorInterest);
        }

        assertEq(
            loanRegistry.cumulativeRepaymentData(loanId).seniorInterest,
            repayments[0].seniorInterest + repayments[1].seniorInterest + repayments[2].seniorInterest
        );

        _assertSeniorInterestMaxEdge();
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

    function test_recordPaymentPrincipalExceedsTranche() public {
        uint256 loanId = _drawDefaultLoan(makeAddr("loanOwner"));
        uint256 seniorTranche = loanRegistry.immutableLoanData(loanId).originalSeniorTranche;

        ILoanRegistry.RepaymentData memory aboveTranche;
        aboveTranche.offtakerReceived = seniorTranche + 1;
        aboveTranche.seniorPrincipalRepaid = seniorTranche + 1;

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryPrincipalExceedsTranche.selector,
                loanId,
                seniorTranche + 1,
                seniorTranche
            )
        );
        loanRegistry.recordPayment(loanId, aboveTranche);

        ILoanRegistry.RepaymentData memory firstHalf;
        firstHalf.offtakerReceived = seniorTranche / 2;
        firstHalf.seniorPrincipalRepaid = seniorTranche / 2;

        vm.prank(loanRegistryManager);
        loanRegistry.recordPayment(loanId, firstHalf);

        ILoanRegistry.RepaymentData memory secondHalf;
        secondHalf.offtakerReceived = seniorTranche - seniorTranche / 2;
        secondHalf.seniorPrincipalRepaid = seniorTranche - seniorTranche / 2;

        vm.prank(loanRegistryManager);
        loanRegistry.recordPayment(loanId, secondHalf);

        assertEq(loanRegistry.cumulativeRepaymentData(loanId).seniorPrincipalRepaid, seniorTranche);

        ILoanRegistry.RepaymentData memory oneMore;
        oneMore.offtakerReceived = 1;
        oneMore.seniorPrincipalRepaid = 1;

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryPrincipalExceedsTranche.selector,
                loanId,
                seniorTranche + 1,
                seniorTranche
            )
        );
        loanRegistry.recordPayment(loanId, oneMore);
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

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.updateMutable(0, "", ILoanRegistry.LoanStatus.Performing, 0, location);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.rollover(0, 0, 0);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.amendEconomics(0, 0, 0);

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
            originalSeniorTranche: 600_000_000,
            originalEquityTranche: 400_000_000,
            originalOfftakerPrice: 3_000_000_000,
            seniorInterestRate: 1_000_000,
            originationDate: uint64(block.timestamp),
            originalMaturityDate: uint64(block.timestamp + loanRegistry.YEAR())
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

    function _assertSeniorInterestMaxEdge() private {
        uint256 loanId = _drawDefaultLoan(makeAddr("edgeLoanOwner"));

        vm.warp(block.timestamp + loanRegistry.YEAR() / 2);

        uint256 cap = loanRegistry.maxInterest(loanId);
        assert(cap > 0);

        ILoanRegistry.RepaymentData memory aboveCap;
        aboveCap.offtakerReceived = cap + 1;
        aboveCap.seniorInterest = cap + 1;

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryInterestExceedsMax.selector, loanId, cap + 1, cap
            )
        );
        loanRegistry.recordPayment(loanId, aboveCap);

        ILoanRegistry.RepaymentData memory atCap;
        atCap.offtakerReceived = cap;
        atCap.seniorInterest = cap;

        vm.prank(loanRegistryManager);
        uint256 repaymentId = loanRegistry.recordPayment(loanId, atCap);
        assertEq(loanRegistry.repaymentData(loanId, repaymentId).seniorInterest, cap);
    }
}
