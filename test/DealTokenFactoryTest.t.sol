// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {LoanRegistryUpgradeable} from "../src/loanRegistry/LoanRegistryUpgradeable.sol";
import {CollateralRegistryUpgradeable} from "../src/collateralRegistry/CollateralRegistryUpgradeable.sol";
import {DealToken} from "../src/dealTokenFactory/DealToken.sol";
import {DealTokenFactoryUpgradeable} from "../src/dealTokenFactory/DealTokenFactoryUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract DealTokenFactoryTest is PipelineTestSetUp {
    uint256 constant UNIT = 1e6;
    uint256 constant YEAR = 31557600;
    uint256 constant SENIOR_TRANCHE = 1_000_000 * UNIT;
    bytes32 constant LOAN_REGISTRY_STORAGE = 0x0e83a2630ccddfd2ad45e4ed21bf1275e7a3fac47a3296c919cdc663065e5e00;

    function test_setUp() public view {
        assertEq(dealTokenFactory.authority(), address(authority));
        assertEq(dealTokenFactory.loanRegistry(), address(loanRegistry));
        assertEq(dealTokenFactory.collateralRegistry(), address(collateralRegistry));
    }

    function test_registerDeal() public {
        uint256 loanId = _drawLoan();
        address predictedDebt = dealTokenFactory.debtAddress(loanId);
        address predictedCargo = dealTokenFactory.cargoAddress(loanId);

        vm.expectEmit(address(dealTokenFactory));
        emit DealTokenFactoryUpgradeable.DealRegistered(loanId, predictedDebt, predictedCargo);

        DealTokenFactoryUpgradeable.Deal memory dealData = _registerDeal(loanId);

        assertEq(dealData.debt, predictedDebt);
        assertEq(dealData.cargo, predictedCargo);
        assertEq(dealTokenFactory.deal(loanId).debt, predictedDebt);
        assertEq(dealTokenFactory.deal(loanId).cargo, predictedCargo);

        DealToken debt = DealToken(dealData.debt);
        assertEq(debt.name(), "Pipeline DEBT0000");
        assertEq(debt.symbol(), "DEBT0000");
        assertEq(debt.decimals(), 6);
        assertEq(debt.factory(), address(dealTokenFactory));
        assertEq(debt.totalSupply(), 0);

        DealToken cargo = DealToken(dealData.cargo);
        assertEq(cargo.name(), "Pipeline CARGO0000");
        assertEq(cargo.symbol(), "CARGO0000");
        assertEq(cargo.factory(), address(dealTokenFactory));
    }

    function test_codesArePadded() public {
        vm.store(address(loanRegistry), LOAN_REGISTRY_STORAGE, bytes32(uint256(42)));
        uint256 loanId = _drawLoan();
        assertEq(loanId, 42);
        DealTokenFactoryUpgradeable.Deal memory dealData = _registerDeal(loanId);
        assertEq(DealToken(dealData.debt).symbol(), "DEBT0042");
        assertEq(DealToken(dealData.cargo).symbol(), "CARGO0042");

        vm.store(address(loanRegistry), LOAN_REGISTRY_STORAGE, bytes32(uint256(12_345)));
        loanId = _drawLoan();
        dealData = _registerDeal(loanId);
        assertEq(DealToken(dealData.debt).symbol(), "DEBT12345");
        assertEq(DealToken(dealData.cargo).name(), "Pipeline CARGO12345");
    }

    function test_registerDealReverts() public {
        vm.prank(loanRegistryManager);
        vm.expectRevert(abi.encodeWithSelector(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector, 0));
        dealTokenFactory.registerDeal(0);

        uint256 loanId = _drawLoan();
        _registerDeal(loanId);

        vm.prank(loanRegistryManager);
        vm.expectRevert(
            abi.encodeWithSelector(DealTokenFactoryUpgradeable.DealTokenFactoryAlreadyRegistered.selector, loanId)
        );
        dealTokenFactory.registerDeal(loanId);
    }

    function test_syncDebt() public {
        uint256 loanId = _drawLoan();
        DealToken debt = DealToken(_registerDeal(loanId).debt);

        vm.prank(address(minter));
        loanRegistry.disburse(loanId, 500 * UNIT);

        vm.expectEmit(address(dealTokenFactory));
        emit DealTokenFactoryUpgradeable.DebtSynced(loanId, 500 * UNIT, 0, 500 * UNIT, 0);

        vm.prank(makeAddr("anyone"));
        dealTokenFactory.syncDebt(loanId);
        assertEq(debt.balanceOf(capitalWallet), 500 * UNIT);
        assertEq(debt.totalSupply(), 500 * UNIT);

        ILoanRegistry.RepaymentData memory repaymentData;
        repaymentData.offtakerReceived = 200 * UNIT;
        repaymentData.seniorPrincipalRepaid = 200 * UNIT;
        vm.prank(address(minter));
        loanRegistry.recordPayment(loanId, repaymentData);

        vm.expectEmit(address(dealTokenFactory));
        emit DealTokenFactoryUpgradeable.DebtSynced(loanId, 300 * UNIT, 500 * UNIT, 0, 200 * UNIT);

        dealTokenFactory.syncDebt(loanId);
        assertEq(debt.balanceOf(capitalWallet), 300 * UNIT);

        vm.expectEmit(address(dealTokenFactory));
        emit DealTokenFactoryUpgradeable.DebtSynced(loanId, 300 * UNIT, 300 * UNIT, 0, 0);

        dealTokenFactory.syncDebt(loanId);
        assertEq(debt.balanceOf(capitalWallet), 300 * UNIT);

        vm.startPrank(loanRegistryManager);
        loanRegistry.setDefault(loanId);
        loanRegistry.writeDown(loanId, 300 * UNIT);
        vm.stopPrank();

        dealTokenFactory.syncDebt(loanId);
        assertEq(debt.totalSupply(), 0);
    }

    function test_syncCargo() public {
        uint256 loanId = _drawLoan();
        DealToken cargo = DealToken(_registerDeal(loanId).cargo);

        vm.startPrank(collateralTrustee);
        uint256 lotId = collateralRegistry.pledge(loanId, _cargoLot(600 * UNIT));
        collateralRegistry.pledge(loanId, _cargoLot(400 * UNIT));
        collateralRegistry.pledge(loanId, _receivableLot(999 * UNIT));
        vm.stopPrank();

        vm.expectEmit(address(dealTokenFactory));
        emit DealTokenFactoryUpgradeable.CargoSynced(loanId, 1_000 * UNIT, 0, 1_000 * UNIT, 0);

        dealTokenFactory.syncCargo(loanId);
        assertEq(cargo.balanceOf(address(dealTokenFactory)), 1_000 * UNIT);

        vm.prank(collateralTrustee);
        collateralRegistry.release(
            loanId, lotId, 600 * UNIT, CollateralRegistryUpgradeable.ReleaseReason.Payment, bytes32(0)
        );

        vm.expectEmit(address(dealTokenFactory));
        emit DealTokenFactoryUpgradeable.CargoSynced(loanId, 400 * UNIT, 1_000 * UNIT, 0, 600 * UNIT);

        dealTokenFactory.syncCargo(loanId);
        assertEq(cargo.balanceOf(address(dealTokenFactory)), 400 * UNIT);
        assertEq(cargo.totalSupply(), 400 * UNIT);
    }

    function test_syncNeedsRegisteredDeal() public {
        uint256 loanId = _drawLoan();
        bytes memory notRegistered =
            abi.encodeWithSelector(DealTokenFactoryUpgradeable.DealTokenFactoryNotRegistered.selector, loanId);

        vm.expectRevert(notRegistered);
        dealTokenFactory.syncDebt(loanId);
        vm.expectRevert(notRegistered);
        dealTokenFactory.syncCargo(loanId);
        vm.expectRevert(notRegistered);
        dealTokenFactory.deal(loanId);
    }

    function test_dealTokensAreFrozen() public {
        uint256 loanId = _drawLoan();
        DealToken debt = DealToken(_registerDeal(loanId).debt);

        vm.prank(address(minter));
        loanRegistry.disburse(loanId, 500 * UNIT);
        dealTokenFactory.syncDebt(loanId);

        address other = makeAddr("other");

        vm.prank(capitalWallet);
        vm.expectRevert(DealToken.DealTokenNonTransferrable.selector);
        debt.transfer(other, 1);

        vm.prank(capitalWallet);
        debt.approve(other, 1);

        vm.prank(other);
        vm.expectRevert(DealToken.DealTokenNonTransferrable.selector);
        debt.transferFrom(capitalWallet, other, 1);

        vm.prank(other);
        vm.expectRevert(DealToken.DealTokenOnlyFactory.selector);
        debt.mint(other, 1);

        vm.prank(capitalWallet);
        vm.expectRevert(DealToken.DealTokenOnlyFactory.selector);
        debt.burn(capitalWallet, 1);
    }

    function test_setters() public {
        address newLoanRegistry = makeAddr("newLoanRegistry");
        address newCollateralRegistry = makeAddr("newCollateralRegistry");

        vm.startPrank(admin);

        vm.expectEmit(address(dealTokenFactory));
        emit DealTokenFactoryUpgradeable.LoanRegistrySet(newLoanRegistry);
        dealTokenFactory.setLoanRegistry(newLoanRegistry);

        vm.expectEmit(address(dealTokenFactory));
        emit DealTokenFactoryUpgradeable.CollateralRegistrySet(newCollateralRegistry);
        dealTokenFactory.setCollateralRegistry(newCollateralRegistry);

        assertEq(dealTokenFactory.loanRegistry(), newLoanRegistry);
        assertEq(dealTokenFactory.collateralRegistry(), newCollateralRegistry);

        vm.expectRevert(DealTokenFactoryUpgradeable.DealTokenFactoryZeroAddress.selector);
        dealTokenFactory.setLoanRegistry(address(0));
        vm.expectRevert(DealTokenFactoryUpgradeable.DealTokenFactorySameValue.selector);
        dealTokenFactory.setLoanRegistry(newLoanRegistry);
        vm.expectRevert(DealTokenFactoryUpgradeable.DealTokenFactoryZeroAddress.selector);
        dealTokenFactory.setCollateralRegistry(address(0));
        vm.expectRevert(DealTokenFactoryUpgradeable.DealTokenFactorySameValue.selector);
        dealTokenFactory.setCollateralRegistry(newCollateralRegistry);

        vm.stopPrank();
    }

    function _drawLoan() private returns (uint256 loanId) {
        ILoanRegistry.ImmutableLoanData memory economics = ILoanRegistry.ImmutableLoanData({
            borrowerRef: bytes32(uint256(1)),
            originalFacilitySize: SENIOR_TRANCHE,
            originalSeniorTranche: SENIOR_TRANCHE,
            originalEquityTranche: 0,
            originalOfftakerPrice: SENIOR_TRANCHE,
            seniorInterestRate: 100_000,
            originationDate: uint64(vm.getBlockTimestamp()),
            originalMaturityDate: uint64(vm.getBlockTimestamp() + YEAR)
        });

        vm.prank(loanRegistryManager);
        return loanRegistry.drawLoan("metadataURI", economics);
    }

    function _registerDeal(uint256 loanId) private returns (DealTokenFactoryUpgradeable.Deal memory) {
        vm.prank(loanRegistryManager);
        return dealTokenFactory.registerDeal(loanId);
    }

    function _cargoLot(uint256 quantity)
        private
        pure
        returns (CollateralRegistryUpgradeable.PledgeLot memory pledgeLot)
    {
        pledgeLot.kind = CollateralRegistryUpgradeable.LotKind.Cargo;
        pledgeLot.unit = CollateralRegistryUpgradeable.Unit.Dmt;
        pledgeLot.quantity = quantity;
        pledgeLot.cargo.commodity = "copper concentrate";
    }

    function _receivableLot(uint256 quantity)
        private
        pure
        returns (CollateralRegistryUpgradeable.PledgeLot memory pledgeLot)
    {
        pledgeLot.kind = CollateralRegistryUpgradeable.LotKind.Receivable;
        pledgeLot.unit = CollateralRegistryUpgradeable.Unit.Usd;
        pledgeLot.quantity = quantity;
    }
}
