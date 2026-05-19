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

    function test_mintLoan() public {
        address loanOwner = makeAddr("loanOwner");
        string memory metadataURI = "test_mintLoan_metadataURI";
        uint64 initialMaturity = uint64(block.timestamp + 100);
        string memory location = "location";

        uint256 nextLoanId = loanRegistry.nextLoanId();

        vm.prank(loanRegistryManager);
        uint256 loanId = loanRegistry.mintLoan(loanOwner, metadataURI, initialMaturity, location);

        assertEq(loanId, nextLoanId);
        assertEq(loanRegistry.nextLoanId(), loanId + 1);

        assertEq(loanRegistry.tokenURI(loanId), metadataURI);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Performing));
        assertEq(mutableLoanData.ccrBps, 0);
        assertEq(mutableLoanData.location, location);
        assertEq(mutableLoanData.maturity, initialMaturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(ILoanRegistry.ClosureReason.None));
    }

    function test_updateStatus() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        ILoanRegistry.LoanStatus newStatus = ILoanRegistry.LoanStatus.WatchList;
        assertNotEq(uint256(mutableDataBefore.status), uint256(newStatus));

        vm.prank(loanRegistryManager);
        loanRegistry.updateStatus(loanId, newStatus);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(newStatus));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, mutableDataBefore.location);
        assertEq(mutableLoanData.maturity, mutableDataBefore.maturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));
    }

    function test_updateStatusReverts() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

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

        loanId = _mintDefaultLoan(makeAddr("loanOwner"));

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
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        uint32 newCcrBps = 1;
        assertNotEq(mutableDataBefore.ccrBps, newCcrBps);

        vm.prank(loanRegistryManager);
        loanRegistry.updateCCR(loanId, newCcrBps);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(mutableDataBefore.status));
        assertEq(mutableLoanData.ccrBps, newCcrBps);
        assertEq(mutableLoanData.location, mutableDataBefore.location);
        assertEq(mutableLoanData.maturity, mutableDataBefore.maturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));
    }

    function test_updateCCRReverts() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

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
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        string memory newLocation = "newLocation";
        assertNotEq(mutableDataBefore.location, newLocation);

        vm.prank(loanRegistryManager);
        loanRegistry.updateLocation(loanId, newLocation);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(mutableDataBefore.status));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, newLocation);
        assertEq(mutableLoanData.maturity, mutableDataBefore.maturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));
    }

    function test_updateLocationReverts() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

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
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId, 0);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Default));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, mutableLoanData.location);
        assertEq(mutableLoanData.maturity, mutableDataBefore.maturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));
    }

    function test_setDefaultReverts() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

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

        loanId = _mintDefaultLoan(makeAddr("loanOwner"));

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
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));
        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        ILoanRegistry.ClosureReason closureReason = ILoanRegistry.ClosureReason.EarlyRepayment;

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, closureReason);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Closed));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, mutableLoanData.location);
        assertEq(mutableLoanData.maturity, mutableDataBefore.maturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(closureReason));
    }

    function test_closeLoanReverts() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

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

        loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryAlreadyClosed.selector, loanId));
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);
    }

    function test_recordPayment(
        uint256 offtakerAmount,
        uint256 seniorPrincipal,
        uint256 seniorInterest,
        uint256 equityAmount
    ) public {
        uint256 reasonableLimit = 10 ** 50;
        vm.assume(
            offtakerAmount < reasonableLimit && seniorPrincipal < reasonableLimit && seniorInterest < reasonableLimit
                && equityAmount < reasonableLimit
        );
        vm.assume(offtakerAmount >= equityAmount + seniorPrincipal + seniorInterest);

        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        (
            uint256 offtakerReceivedTotalBefore,
            uint256 seniorPrincipalRepaidBefore,
            uint256 seniorInterestRepaidBefore,
            uint256 equityDistributedBefore
        ) = loanRegistry.repaymentData();

        vm.prank(loanRegistryManager);
        loanRegistry.recordPayment(loanId, offtakerAmount, seniorPrincipal, seniorInterest, equityAmount);

        (
            uint256 offtakerReceivedTotalAfter,
            uint256 seniorPrincipalRepaidAfter,
            uint256 seniorInterestRepaidAfter,
            uint256 equityDistributedAfter
        ) = loanRegistry.repaymentData();

        assertEq(offtakerReceivedTotalAfter, offtakerReceivedTotalBefore + offtakerAmount);
        assertEq(seniorPrincipalRepaidAfter, seniorPrincipalRepaidBefore + seniorPrincipal);
        assertEq(seniorInterestRepaidAfter, seniorInterestRepaidBefore + seniorInterest);
        assertEq(equityDistributedAfter, equityDistributedBefore + equityAmount);
    }

    function test_recordPaymentWrongData(
        uint256 offtakerAmount,
        uint256 seniorPrincipal,
        uint256 seniorInterest,
        uint256 equityAmount
    ) public {
        uint256 reasonableLimit = 10 ** 50;
        vm.assume(
            offtakerAmount < reasonableLimit && seniorPrincipal < reasonableLimit && seniorInterest < reasonableLimit
                && equityAmount < reasonableLimit
        );
        vm.assume(offtakerAmount < equityAmount + seniorPrincipal + seniorInterest);

        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryWrongRepaymentData.selector));
        loanRegistry.recordPayment(loanId, offtakerAmount, seniorPrincipal, seniorInterest, equityAmount);
    }

    function test_nonTransferrable() public {
        address loanOwner = makeAddr("loanOwner");
        address recipient = makeAddr("recipient");

        uint256 loanId = _mintDefaultLoan(loanOwner);

        vm.prank(loanOwner);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonTransferrable.selector));
        loanRegistry.transferFrom(loanOwner, recipient, loanId);
    }

    function test_pauses() public {
        address loanOwner = makeAddr("loanOwner");

        vm.prank(loanRegistryManager);
        loanRegistry.pause();

        assert(loanRegistry.paused());

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.mintLoan(loanOwner, "", 0, "location");

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

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        loanRegistry.recordPayment(0, 0, 0, 0, 0);

        vm.prank(loanRegistryManager);
        loanRegistry.unpause();

        assert(!loanRegistry.paused());
    }

    function _mintDefaultLoan(address to) private returns (uint256 loanId) {
        string memory defaultMetadataURI = "defaultMetadataURI";
        uint64 initialMaturity = uint64(block.timestamp + 100);
        string memory location = "location";

        vm.prank(loanRegistryManager);
        return loanRegistry.mintLoan(to, defaultMetadataURI, initialMaturity, location);
    }
}
