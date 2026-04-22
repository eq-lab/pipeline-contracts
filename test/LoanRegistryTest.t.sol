// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

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
        ILoanRegistry.ImmutableLoanData memory loanData = _buildDefaultLoanData();
        uint64 initialMaturity = uint64(block.timestamp + 100);
        bytes32 location = bytes32("location");

        uint256 nextLoanId = loanRegistry.nextLoanId();

        vm.prank(loanRegistryManager);
        uint256 loanId = loanRegistry.mintLoan(loanOwner, loanData, initialMaturity, location);

        assertEq(loanId, nextLoanId);
        assertEq(loanRegistry.nextLoanId(), loanId + 1);

        ILoanRegistry.ImmutableLoanData memory immutableLoanData = loanRegistry.immutableLoanData(loanId);
        assertEq(immutableLoanData.docHash, loanData.docHash);
        assertEq(immutableLoanData.principal, loanData.principal);
        assertEq(immutableLoanData.originator, loanData.originator);
        assertEq(immutableLoanData.borrower, loanData.borrower);
        assertEq(immutableLoanData.commodity, loanData.commodity);
        assertEq(immutableLoanData.originatedAt, loanData.originatedAt);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Performing));
        assertEq(mutableLoanData.ccrBps, 0);
        assertEq(mutableLoanData.location, location);
        assertEq(mutableLoanData.maturity, initialMaturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(ILoanRegistry.ClosureReason.None));
    }

    function test_updateStatus() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.ImmutableLoanData memory immutableDataBefore = loanRegistry.immutableLoanData(loanId);
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

        _assertImmutableDataNotChanged(loanId, immutableDataBefore);
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
        loanRegistry.setDefault(loanId);

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

        ILoanRegistry.ImmutableLoanData memory immutableDataBefore = loanRegistry.immutableLoanData(loanId);
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

        _assertImmutableDataNotChanged(loanId, immutableDataBefore);
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
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryAlreadyClosed.selector, loanId));
        loanRegistry.updateCCR(loanId, mutableDataBefore.ccrBps + 1);
    }

    function test_updateLocation() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.ImmutableLoanData memory immutableDataBefore = loanRegistry.immutableLoanData(loanId);
        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        bytes32 newLocation = bytes32("newLocation");
        assertNotEq(mutableDataBefore.location, newLocation);

        vm.prank(loanRegistryManager);
        loanRegistry.updateLocation(loanId, newLocation);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(mutableDataBefore.status));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, newLocation);
        assertEq(mutableLoanData.maturity, mutableDataBefore.maturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));

        _assertImmutableDataNotChanged(loanId, immutableDataBefore);
    }

    function test_updateLocationReverts() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        bytes32 newLocation = bytes32("newLocation");

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.updateLocation(loanId + 1, newLocation);

        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryAlreadyClosed.selector, loanId));
        loanRegistry.updateLocation(loanId, newLocation);
    }

    function test_setDefault() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.ImmutableLoanData memory immutableDataBefore = loanRegistry.immutableLoanData(loanId);
        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId);

        ILoanRegistry.MutableLoanData memory mutableLoanData = loanRegistry.mutableLoanData(loanId);
        assertEq(uint256(mutableLoanData.status), uint256(ILoanRegistry.LoanStatus.Default));
        assertEq(mutableLoanData.ccrBps, mutableDataBefore.ccrBps);
        assertEq(mutableLoanData.location, mutableLoanData.location);
        assertEq(mutableLoanData.maturity, mutableDataBefore.maturity);
        assertEq(uint256(mutableLoanData.closureReason), uint256(mutableDataBefore.closureReason));

        _assertImmutableDataNotChanged(loanId, immutableDataBefore);
    }

    function test_setDefaultReverts() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        ILoanRegistry.MutableLoanData memory mutableDataBefore = loanRegistry.mutableLoanData(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.setDefault(loanId + 1);

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                LoanRegistryUpgradeable.LoanRegistryWrongCurrentStatus.selector,
                loanId,
                ILoanRegistry.LoanStatus.Default
            )
        );
        loanRegistry.setDefault(loanId);

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

        ILoanRegistry.ImmutableLoanData memory immutableDataBefore = loanRegistry.immutableLoanData(loanId);
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

        _assertImmutableDataNotChanged(loanId, immutableDataBefore);
    }

    function test_closeLoanReverts() public {
        uint256 loanId = _mintDefaultLoan(makeAddr("loanOwner"));

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, loanId + 1)
        );
        loanRegistry.closeLoan(loanId + 1, ILoanRegistry.ClosureReason.EarlyRepayment);

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId);

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

    function test_nonTransferrable() public {
        address loanOwner = makeAddr("loanOwner");
        address recipient = makeAddr("recipient");

        uint256 loanId = _mintDefaultLoan(loanOwner);

        vm.prank(loanOwner);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonTransferrable.selector));
        loanRegistry.transferFrom(loanOwner, recipient, loanId);
    }

    function _mintDefaultLoan(address to) private returns (uint256 loanId) {
        ILoanRegistry.ImmutableLoanData memory loanData = _buildDefaultLoanData();
        uint64 initialMaturity = uint64(block.timestamp + 100);
        bytes32 location = bytes32("location");

        vm.prank(loanRegistryManager);
        return loanRegistry.mintLoan(to, loanData, initialMaturity, location);
    }

    function _buildDefaultLoanData() private returns (ILoanRegistry.ImmutableLoanData memory) {
        return ILoanRegistry.ImmutableLoanData({
            docHash: bytes32("docHash"),
            principal: 0,
            originator: makeAddr("originator"),
            borrower: makeAddr("borrower"),
            commodity: bytes32("commodity"),
            originatedAt: uint64(block.timestamp)
        });
    }

    function _assertImmutableDataNotChanged(uint256 loanId, ILoanRegistry.ImmutableLoanData memory dataBefore)
        private
        view
    {
        ILoanRegistry.ImmutableLoanData memory immutableLoanData = loanRegistry.immutableLoanData(loanId);
        assertEq(immutableLoanData.docHash, dataBefore.docHash);
        assertEq(immutableLoanData.principal, dataBefore.principal);
        assertEq(immutableLoanData.originator, dataBefore.originator);
        assertEq(immutableLoanData.borrower, dataBefore.borrower);
        assertEq(immutableLoanData.commodity, dataBefore.commodity);
        assertEq(immutableLoanData.originatedAt, dataBefore.originatedAt);
    }
}
