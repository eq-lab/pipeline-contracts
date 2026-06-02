// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {PipelineYieldMinter} from "../src/PipelineYieldMinter.sol";
import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {LoanRegistryUpgradeable} from "../src/loanRegistry/LoanRegistryUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineYieldMinterTest is PipelineTestSetUp {
    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(address(sPlUsd));

        vm.prank(whitelistAdmin);
        whitelistRegistry.allow(address(treasury));
    }

    function test_setUp() public view {
        assertEq(yieldMinter.authority(), address(authority));
        assertEq(address(yieldMinter.loanRegistry()), address(loanRegistry));
        assertEq(yieldMinter.stakedPlUsd(), address(sPlUsd));
        assertEq(address(yieldMinter.plUsd()), address(plUsd));
        assertEq(yieldMinter.treasury(), treasury);
    }

    function test_mintYield() public {
        (uint256 loanId, uint256 repaymentId) = _setUpDefaultLoanAndPayment();
        uint256 totalAssetsBefore = sPlUsd.totalAssets();
        uint256 treasuryBalanceBefore = plUsd.balanceOf(treasury);

        vm.prank(yieldMinterManager);
        yieldMinter.mintYield(loanId, loanId);

        ILoanRegistry.RepaymentData memory repayment = loanRegistry.repaymentData(loanId, repaymentId);
        uint256 sPlUsdAmount = repayment.seniorInterest;
        uint256 treasuryAmount = repayment.mgmtFee + repayment.perfFee + repayment.oetAlloc;

        assertEq(sPlUsd.totalAssets(), totalAssetsBefore + sPlUsdAmount);
        assertEq(plUsd.balanceOf(treasury), treasuryBalanceBefore + treasuryAmount);

        vm.prank(yieldMinterManager);
        vm.expectRevert(
            abi.encodeWithSelector(PipelineYieldMinter.YieldMinterForbiddenMint.selector, loanId, repaymentId)
        );
        yieldMinter.mintYield(loanId, loanId);

        vm.prank(address(yieldMinter));
        vm.expectRevert(
            abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryAlreadyMinted.selector, loanId, repaymentId)
        );
        loanRegistry.markMinted(0, 0);
    }

    function testFuzz_setTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0) && newTreasury != yieldMinter.treasury());

        vm.prank(yieldMinterManager);
        yieldMinter.setTreasury(newTreasury);

        assertEq(yieldMinter.treasury(), newTreasury);
    }

    function test_setTreasuryReverts() public {
        address treasury = yieldMinter.treasury();

        vm.prank(yieldMinterManager);
        vm.expectRevert(abi.encodeWithSelector(PipelineYieldMinter.YieldMinterSameValue.selector));
        yieldMinter.setTreasury(treasury);

        vm.prank(yieldMinterManager);
        vm.expectRevert(abi.encodeWithSelector(PipelineYieldMinter.YieldMinterZeroAddress.selector));
        yieldMinter.setTreasury(address(0));
    }

    function _setUpDefaultLoanAndPayment() private returns (uint256 loanId, uint256 repaymentId) {
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

        address loanOwner = makeAddr("loanOwner");
        ILoanRegistry.LocationUpdate memory location;

        vm.prank(loanRegistryManager);
        loanId = loanRegistry.drawLoan(loanOwner, defaultMetadataURI, loanData, 1_000_000, location);

        vm.warp(block.timestamp + loanRegistry.YEAR() / 2);

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
        repaymentId = loanRegistry.recordPayment(loanId, repayment);
    }
}
