// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {LoanRegistryUpgradeable} from "../src/loanRegistry/LoanRegistryUpgradeable.sol";
import {CollateralRegistryUpgradeable} from "../src/collateralRegistry/CollateralRegistryUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract CollateralRegistryTest is PipelineTestSetUp {
    uint256 constant UNIT = 1e6;
    uint256 constant YEAR = 31557600;
    uint256 constant SENIOR_TRANCHE = 1_000_000 * UNIT;
    bytes32 constant LME = "LME";

    function test_setUp() public view {
        assertEq(collateralRegistry.authority(), address(authority));
        assertEq(collateralRegistry.loanRegistry(), address(loanRegistry));
        assertEq(collateralRegistry.PAR_VALUE(), UNIT);
    }

    function test_setLoanRegistry() public {
        address newLoanRegistry = makeAddr("newLoanRegistry");

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.LoanRegistrySet(newLoanRegistry);

        vm.prank(admin);
        collateralRegistry.setLoanRegistry(newLoanRegistry);
        assertEq(collateralRegistry.loanRegistry(), newLoanRegistry);

        vm.startPrank(admin);
        vm.expectRevert(CollateralRegistryUpgradeable.CollateralRegistryZeroAddress.selector);
        collateralRegistry.setLoanRegistry(address(0));
        vm.expectRevert(CollateralRegistryUpgradeable.CollateralRegistrySameValue.selector);
        collateralRegistry.setLoanRegistry(newLoanRegistry);
        vm.stopPrank();
    }

    function test_pledgeCargo() public {
        uint256 loanId = _drawLoan();

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.Pledged(loanId, 0);

        uint256 lotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1_000, 1_000));
        assertEq(lotId, 0);
        assertEq(collateralRegistry.lotsCount(loanId), 1);

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, lotId);
        assertEq(uint8(lotData.kind), uint8(CollateralRegistryUpgradeable.LotKind.Cargo));
        assertEq(uint8(lotData.unit), uint8(CollateralRegistryUpgradeable.Unit.Dmt));
        assertEq(uint8(lotData.stage), uint8(CollateralRegistryUpgradeable.LotStage.Pledged));
        assertEq(uint8(lotData.control.kind), uint8(CollateralRegistryUpgradeable.ControlKind.None));
        assertEq(lotData.quantity, 1_000);
        assertEq(lotData.haircutBps, 1_000);
        assertEq(lotData.docs.length, 0);
        assertFalse(lotData.hasMark);
        assertFalse(lotData.hasLocation);
        assertEq(lotData.cargo.commodity, "copper concentrate");
        assertEq(
            uint8(lotData.cargo.valuationMode), uint8(CollateralRegistryUpgradeable.CargoValuationMode.MetalConcentrate)
        );
    }

    function test_pledgeCargoWithLocation() public {
        uint256 loanId = _drawLoan();
        CollateralRegistryUpgradeable.PledgeLot memory pledgeLot =
            _cargoLot(CollateralRegistryUpgradeable.Unit.Bbl, 100, 0);
        pledgeLot.hasLocation = true;
        pledgeLot.location = _vessel();

        uint256 lotId = _pledge(loanId, pledgeLot);

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, lotId);
        assertTrue(lotData.hasLocation);
        assertEq(uint8(lotData.location.locationType), uint8(CollateralRegistryUpgradeable.LocationType.Vessel));
        assertEq(lotData.location.identifier, "MV Example");
        assertEq(lotData.location.trackingUrl, "https://example.com");
    }

    function test_pledgeReceivable() public {
        uint256 loanId = _drawLoan();
        vm.warp(42);

        uint256 lotId = _pledge(loanId, _receivableLot(5_000));

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, lotId);
        assertEq(uint8(lotData.kind), uint8(CollateralRegistryUpgradeable.LotKind.Receivable));
        assertEq(uint8(lotData.stage), uint8(CollateralRegistryUpgradeable.LotStage.Assigned));
        assertTrue(lotData.hasMark);
        assertEq(lotData.mark.valuePerUnit, UNIT);
        assertEq(lotData.mark.at, 42);
        assertEq(lotData.mark.benchmark, collateralRegistry.PAR_BENCHMARK());
        assertEq(lotData.mark.reportHash, bytes32(0));
        assertEq(lotData.receivable.obligorRef, bytes32(uint256(9)));
        assertEq(lotData.receivable.dueDate, YEAR);
    }

    function test_pledgeReverts() public {
        uint256 closedLoanId = _drawLoan();
        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(closedLoanId, ILoanRegistry.ClosureReason.Cancelled);

        vm.prank(collateralTrustee);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryLoanClosed.selector, closedLoanId)
        );
        collateralRegistry.pledge(closedLoanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1, 0));

        vm.prank(collateralTrustee);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        collateralRegistry.pledge(77, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1, 0));

        uint256 loanId = _drawLoan();

        vm.startPrank(collateralTrustee);

        vm.expectRevert(CollateralRegistryUpgradeable.CollateralRegistryInvalidQuantity.selector);
        collateralRegistry.pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 0, 0));

        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryInvalidHaircut.selector, 10_001)
        );
        collateralRegistry.pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1, 10_001));

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryInvalidUnit.selector,
                CollateralRegistryUpgradeable.Unit.Usd
            )
        );
        collateralRegistry.pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Usd, 1, 0));

        CollateralRegistryUpgradeable.PledgeLot memory receivable = _receivableLot(1);
        receivable.unit = CollateralRegistryUpgradeable.Unit.Dmt;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryInvalidUnit.selector,
                CollateralRegistryUpgradeable.Unit.Dmt
            )
        );
        collateralRegistry.pledge(loanId, receivable);

        receivable = _receivableLot(1);
        receivable.hasLocation = true;
        vm.expectRevert(CollateralRegistryUpgradeable.CollateralRegistryInvalidLocation.selector);
        collateralRegistry.pledge(loanId, receivable);

        collateralRegistry.pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1, 0));
        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryCargoUnitMismatch.selector,
                CollateralRegistryUpgradeable.Unit.Dmt,
                CollateralRegistryUpgradeable.Unit.Mt
            )
        );
        collateralRegistry.pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Mt, 1, 0));

        vm.stopPrank();
    }

    function test_pledgeAllowedOnDefaultedLoan() public {
        uint256 loanId = _drawAndDisburse(SENIOR_TRANCHE);
        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId);

        _pledge(loanId, _receivableLot(1));
        assertEq(collateralRegistry.lotsCount(loanId), 1);
    }

    function test_pledgeLotCap() public {
        uint256 loanId = _drawLoan();
        for (uint256 i; i < 32; ++i) {
            _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1, 0));
        }

        vm.prank(collateralTrustee);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryTooManyLots.selector, loanId)
        );
        collateralRegistry.pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1, 0));
    }

    function test_setHaircut() public {
        uint256 loanId = _drawLoan();
        uint256 lotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 500));

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.HaircutSet(loanId, lotId, 2_000);

        vm.prank(collateralTrustee);
        collateralRegistry.setHaircut(loanId, lotId, 2_000);
        assertEq(collateralRegistry.lot(loanId, lotId).haircutBps, 2_000);

        vm.prank(collateralTrustee);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryInvalidHaircut.selector, 10_001)
        );
        collateralRegistry.setHaircut(loanId, lotId, 10_001);

        vm.prank(collateralTrustee);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryNonExistentLot.selector, loanId, 1)
        );
        collateralRegistry.setHaircut(loanId, 1, 0);
    }

    function test_setFloor() public {
        uint256 loanId = _drawLoan();

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.FloorSet(loanId, 12_000);

        vm.prank(collateralTrustee);
        collateralRegistry.setFloor(loanId, 12_000);
        assertEq(collateralRegistry.floorBps(loanId), 12_000);

        vm.prank(collateralTrustee);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        collateralRegistry.setFloor(77, 12_000);
    }

    function test_revalue() public {
        uint256 loanId = _drawLoan();
        uint256 lotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        vm.warp(1_000);

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.Revalued(loanId, lotId, 50 * UNIT, LME, bytes32(uint256(5)));

        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, lotId, 50 * UNIT, LME, bytes32(uint256(5)));

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, lotId);
        assertTrue(lotData.hasMark);
        assertEq(lotData.mark.valuePerUnit, 50 * UNIT);
        assertEq(lotData.mark.at, 1_000);
        assertEq(lotData.mark.benchmark, LME);
        assertEq(lotData.mark.reportHash, bytes32(uint256(5)));

        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, lotId, 0, LME, bytes32(0));
        assertEq(collateralRegistry.lot(loanId, lotId).mark.valuePerUnit, 0);

        vm.prank(collateralValuer);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryNonExistentLot.selector, loanId, 1)
        );
        collateralRegistry.revalue(loanId, 1, 0, LME, bytes32(0));
    }

    function test_setStage() public {
        uint256 loanId = _drawLoan();
        uint256 cargoLotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        uint256 receivableLotId = _pledge(loanId, _receivableLot(100));
        CollateralRegistryUpgradeable.Location memory vessel = _vessel();
        CollateralRegistryUpgradeable.Location memory none;

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.StageUpdated(
            loanId, cargoLotId, CollateralRegistryUpgradeable.LotStage.Afloat, true, vessel
        );

        vm.prank(collateralTrustee);
        collateralRegistry.setStage(loanId, cargoLotId, CollateralRegistryUpgradeable.LotStage.Afloat, true, vessel);

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, cargoLotId);
        assertEq(uint8(lotData.stage), uint8(CollateralRegistryUpgradeable.LotStage.Afloat));
        assertTrue(lotData.hasLocation);
        assertEq(lotData.location.identifier, "MV Example");

        vm.prank(collateralTrustee);
        collateralRegistry.setStage(loanId, cargoLotId, CollateralRegistryUpgradeable.LotStage.Pledged, false, none);

        lotData = collateralRegistry.lot(loanId, cargoLotId);
        assertEq(uint8(lotData.stage), uint8(CollateralRegistryUpgradeable.LotStage.Pledged));
        assertFalse(lotData.hasLocation);
        assertEq(lotData.location.identifier, "");

        vm.prank(collateralTrustee);
        collateralRegistry.setStage(
            loanId, receivableLotId, CollateralRegistryUpgradeable.LotStage.Presented, false, none
        );
        assertEq(
            uint8(collateralRegistry.lot(loanId, receivableLotId).stage),
            uint8(CollateralRegistryUpgradeable.LotStage.Presented)
        );
    }

    function test_setStageReverts() public {
        uint256 loanId = _drawLoan();
        uint256 cargoLotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        uint256 receivableLotId = _pledge(loanId, _receivableLot(100));
        CollateralRegistryUpgradeable.Location memory vessel = _vessel();
        CollateralRegistryUpgradeable.Location memory none;

        vm.startPrank(collateralTrustee);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryInvalidStage.selector,
                CollateralRegistryUpgradeable.LotStage.Delivered
            )
        );
        collateralRegistry.setStage(loanId, cargoLotId, CollateralRegistryUpgradeable.LotStage.Delivered, false, none);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryInvalidStage.selector,
                CollateralRegistryUpgradeable.LotStage.Assigned
            )
        );
        collateralRegistry.setStage(loanId, cargoLotId, CollateralRegistryUpgradeable.LotStage.Assigned, false, none);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryInvalidStage.selector,
                CollateralRegistryUpgradeable.LotStage.Paid
            )
        );
        collateralRegistry.setStage(loanId, receivableLotId, CollateralRegistryUpgradeable.LotStage.Paid, false, none);

        vm.expectRevert(CollateralRegistryUpgradeable.CollateralRegistryInvalidLocation.selector);
        collateralRegistry.setStage(
            loanId, receivableLotId, CollateralRegistryUpgradeable.LotStage.Acknowledged, true, vessel
        );

        vm.stopPrank();
    }

    function test_setControl() public {
        uint256 loanId = _drawLoan();
        uint256 cargoLotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        uint256 receivableLotId = _pledge(loanId, _receivableLot(100));

        CollateralRegistryUpgradeable.Control memory acknowledged =
            _control(CollateralRegistryUpgradeable.ControlKind.Acknowledged, "ack");

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.ControlUpdated(loanId, receivableLotId, acknowledged);

        vm.prank(collateralTrustee);
        collateralRegistry.setControl(loanId, receivableLotId, acknowledged);

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, receivableLotId);
        assertEq(uint8(lotData.control.kind), uint8(CollateralRegistryUpgradeable.ControlKind.Acknowledged));
        assertEq(lotData.control.ref, "ack");
        assertEq(uint8(lotData.stage), uint8(CollateralRegistryUpgradeable.LotStage.Acknowledged));

        vm.startPrank(collateralTrustee);

        collateralRegistry.setControl(loanId, cargoLotId, _ebl());
        assertEq(
            uint8(collateralRegistry.lot(loanId, cargoLotId).control.kind),
            uint8(CollateralRegistryUpgradeable.ControlKind.EblToOrderOfTrust)
        );

        collateralRegistry.setControl(loanId, cargoLotId, _control(CollateralRegistryUpgradeable.ControlKind.None, ""));
        assertEq(
            uint8(collateralRegistry.lot(loanId, cargoLotId).control.kind),
            uint8(CollateralRegistryUpgradeable.ControlKind.None)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryInvalidControl.selector,
                CollateralRegistryUpgradeable.ControlKind.Acknowledged
            )
        );
        collateralRegistry.setControl(loanId, cargoLotId, acknowledged);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryInvalidControl.selector,
                CollateralRegistryUpgradeable.ControlKind.EblToOrderOfTrust
            )
        );
        collateralRegistry.setControl(loanId, receivableLotId, _ebl());

        vm.stopPrank();
    }

    function test_addDoc() public {
        uint256 loanId = _drawLoan();
        uint256 lotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.DocAdded(
            loanId, lotId, CollateralRegistryUpgradeable.DocKind.Assay, bytes32(uint256(1))
        );

        vm.startPrank(collateralTrustee);
        for (uint256 i = 1; i <= 16; ++i) {
            collateralRegistry.addDoc(loanId, lotId, CollateralRegistryUpgradeable.DocKind.Assay, bytes32(i));
        }

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, lotId);
        assertEq(lotData.docs.length, 16);
        assertEq(uint8(lotData.docs[15].kind), uint8(CollateralRegistryUpgradeable.DocKind.Assay));
        assertEq(lotData.docs[15].hash, bytes32(uint256(16)));

        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryTooManyDocs.selector, loanId, lotId)
        );
        collateralRegistry.addDoc(loanId, lotId, CollateralRegistryUpgradeable.DocKind.Other, bytes32(uint256(99)));
        vm.stopPrank();
    }

    function test_adjustQuantity() public {
        uint256 loanId = _drawLoan();
        uint256 lotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.QuantityAdjusted(loanId, lotId, 100, 80, "shrinkage", bytes32(uint256(3)));

        vm.prank(collateralTrustee);
        collateralRegistry.adjustQuantity(loanId, lotId, 80, "shrinkage", bytes32(uint256(3)));
        assertEq(collateralRegistry.lot(loanId, lotId).quantity, 80);

        vm.prank(collateralTrustee);
        collateralRegistry.adjustQuantity(loanId, lotId, 0, "lost", bytes32(0));

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, lotId);
        assertEq(lotData.quantity, 0);
        assertEq(uint8(lotData.stage), uint8(CollateralRegistryUpgradeable.LotStage.Pledged));
    }

    function test_release() public {
        uint256 loanId = _drawLoan();
        uint256 cargoLotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        uint256 receivableLotId = _pledge(loanId, _receivableLot(50));

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.Released(
            loanId, cargoLotId, 40, CollateralRegistryUpgradeable.ReleaseReason.Substitution, bytes32(uint256(4))
        );

        vm.startPrank(collateralTrustee);
        collateralRegistry.release(
            loanId, cargoLotId, 40, CollateralRegistryUpgradeable.ReleaseReason.Substitution, bytes32(uint256(4))
        );

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, cargoLotId);
        assertEq(lotData.quantity, 60);
        assertEq(uint8(lotData.stage), uint8(CollateralRegistryUpgradeable.LotStage.Pledged));

        collateralRegistry.release(
            loanId, cargoLotId, 60, CollateralRegistryUpgradeable.ReleaseReason.Payment, bytes32(uint256(4))
        );
        assertEq(
            uint8(collateralRegistry.lot(loanId, cargoLotId).stage),
            uint8(CollateralRegistryUpgradeable.LotStage.Delivered)
        );

        collateralRegistry.release(
            loanId, receivableLotId, 50, CollateralRegistryUpgradeable.ReleaseReason.Payment, bytes32(uint256(4))
        );
        assertEq(
            uint8(collateralRegistry.lot(loanId, receivableLotId).stage),
            uint8(CollateralRegistryUpgradeable.LotStage.Paid)
        );
        vm.stopPrank();
    }

    function test_releaseReverts() public {
        uint256 loanId = _drawLoan();
        uint256 lotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));

        vm.startPrank(collateralTrustee);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryInsufficientQuantity.selector, 101, 100
            )
        );
        collateralRegistry.release(loanId, lotId, 101, CollateralRegistryUpgradeable.ReleaseReason.Loss, bytes32(0));

        vm.expectRevert(CollateralRegistryUpgradeable.CollateralRegistryInvalidQuantity.selector);
        collateralRegistry.release(loanId, lotId, 0, CollateralRegistryUpgradeable.ReleaseReason.Loss, bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryNonExistentLot.selector, loanId, 1)
        );
        collateralRegistry.release(loanId, 1, 1, CollateralRegistryUpgradeable.ReleaseReason.Loss, bytes32(0));

        vm.stopPrank();
    }

    function test_liquidate() public {
        uint256 loanId = _drawAndDisburse(SENIOR_TRANCHE);
        uint256 cargoLotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        uint256 receivableLotId = _pledge(loanId, _receivableLot(50));

        vm.prank(collateralTrustee);
        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralRegistryUpgradeable.CollateralRegistryWrongLoanStatus.selector,
                loanId,
                ILoanRegistry.LoanStatus.Performing
            )
        );
        collateralRegistry.liquidate(loanId, cargoLotId, 10);

        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId);
        vm.warp(555);

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.Liquidated(loanId, cargoLotId, 1, 40);

        vm.startPrank(collateralTrustee);
        assertEq(collateralRegistry.liquidate(loanId, cargoLotId, 40), 1);
        assertEq(collateralRegistry.liquidate(loanId, cargoLotId, 60), 2);
        assertEq(collateralRegistry.liquidate(loanId, receivableLotId, 50), 3);
        vm.stopPrank();

        CollateralRegistryUpgradeable.Lot memory lotData = collateralRegistry.lot(loanId, cargoLotId);
        assertEq(lotData.quantity, 0);
        assertEq(uint8(lotData.stage), uint8(CollateralRegistryUpgradeable.LotStage.Sold));
        assertEq(
            uint8(collateralRegistry.lot(loanId, receivableLotId).stage),
            uint8(CollateralRegistryUpgradeable.LotStage.Paid)
        );

        CollateralRegistryUpgradeable.Sale memory saleData = collateralRegistry.sale(loanId, 1);
        assertEq(saleData.lotId, cargoLotId);
        assertEq(saleData.quantity, 40);
        assertEq(saleData.at, 555);
        assertEq(collateralRegistry.sale(loanId, 3).lotId, receivableLotId);

        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryNonExistentSale.selector, loanId, 0)
        );
        collateralRegistry.sale(loanId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(CollateralRegistryUpgradeable.CollateralRegistryNonExistentSale.selector, loanId, 4)
        );
        collateralRegistry.sale(loanId, 4);
    }

    function test_lotsAndCargoQuantity() public {
        uint256 loanId = _drawLoan();
        _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 250, 0));
        _pledge(loanId, _receivableLot(999));

        CollateralRegistryUpgradeable.Lot[] memory lotList = collateralRegistry.lots(loanId);
        assertEq(lotList.length, 3);
        assertEq(lotList[1].quantity, 250);
        assertEq(uint8(lotList[2].kind), uint8(CollateralRegistryUpgradeable.LotKind.Receivable));
        assertEq(collateralRegistry.cargoQuantity(loanId), 350);
        assertEq(collateralRegistry.lots(loanId + 1).length, 0);
    }

    function test_collateralValue() public {
        uint256 loanId = _drawLoan();
        uint256 cargoLotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1_000 * UNIT, 1_000));
        assertEq(collateralRegistry.collateralValue(loanId), 0);

        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, cargoLotId, 50 * UNIT, LME, bytes32(0));
        assertEq(collateralRegistry.collateralValue(loanId), 0);

        vm.prank(collateralTrustee);
        collateralRegistry.setControl(loanId, cargoLotId, _ebl());
        assertEq(collateralRegistry.collateralValue(loanId), 45_000 * UNIT);

        uint256 receivableLotId = _pledge(loanId, _receivableLot(10_000 * UNIT));
        assertEq(collateralRegistry.collateralValue(loanId), 45_000 * UNIT);

        vm.prank(collateralTrustee);
        collateralRegistry.setControl(
            loanId, receivableLotId, _control(CollateralRegistryUpgradeable.ControlKind.Acknowledged, "ack")
        );
        assertEq(collateralRegistry.collateralValue(loanId), 55_000 * UNIT);
    }

    function test_coverage() public {
        uint256 loanId = _drawLoan();
        _pledgeControlledCargo(loanId, 1_000 * UNIT, 50 * UNIT, 1_000);

        assertEq(collateralRegistry.coverage(loanId), type(uint32).max);

        vm.prank(address(minter));
        loanRegistry.disburse(loanId, 22_500 * UNIT);
        assertEq(collateralRegistry.coverage(loanId), 20_000);

        skip(YEAR);
        uint256 debt = 22_500 * UNIT + loanRegistry.loanMoney(loanId).accruedInterest;
        assertEq(collateralRegistry.coverage(loanId), 45_000 * UNIT * 10_000 / debt);

        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, 0, type(uint128).max, LME, bytes32(0));
        assertEq(collateralRegistry.coverage(loanId), type(uint32).max);
    }

    function test_marginCall() public {
        uint256 loanId = _drawLoan();
        uint256 lotId = _pledgeControlledCargo(loanId, 1_000 * UNIT, 50 * UNIT, 1_000);

        vm.prank(address(minter));
        loanRegistry.disburse(loanId, 22_500 * UNIT);

        vm.recordLogs();
        vm.prank(collateralTrustee);
        collateralRegistry.setFloor(loanId, 15_000);
        assertEq(_marginCalls(), 0);

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.MarginCall(loanId, 20_000, 25_000);

        vm.prank(collateralTrustee);
        collateralRegistry.setFloor(loanId, 25_000);

        vm.prank(collateralTrustee);
        collateralRegistry.setFloor(loanId, 15_000);

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.MarginCall(loanId, 10_000, 15_000);

        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, lotId, 25 * UNIT, LME, bytes32(0));

        vm.expectEmit(address(collateralRegistry));
        emit CollateralRegistryUpgradeable.MarginCall(loanId, 10_000, 15_000);

        vm.prank(makeAddr("anyone"));
        collateralRegistry.checkCoverage(loanId);
    }

    function test_markAge() public {
        uint256 loanId = _drawLoan();
        assertEq(collateralRegistry.markAge(loanId), 0);

        uint256 firstLotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        assertEq(collateralRegistry.markAge(loanId), 0);

        vm.startPrank(collateralTrustee);
        collateralRegistry.setControl(loanId, firstLotId, _ebl());
        assertEq(collateralRegistry.markAge(loanId), type(uint64).max);

        uint256 secondLotId =
            collateralRegistry.pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        collateralRegistry.setControl(loanId, secondLotId, _ebl());
        vm.stopPrank();

        vm.warp(100);
        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, firstLotId, 1, LME, bytes32(0));
        assertEq(collateralRegistry.markAge(loanId), type(uint64).max);

        vm.warp(120);
        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, secondLotId, 1, LME, bytes32(0));

        vm.warp(150);
        assertEq(collateralRegistry.markAge(loanId), 50);

        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, firstLotId, 1, LME, bytes32(0));
        assertEq(collateralRegistry.markAge(loanId), 30);
    }

    function test_pauses() public {
        uint256 loanId = _drawAndDisburse(SENIOR_TRANCHE);
        uint256 lotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 100, 0));
        CollateralRegistryUpgradeable.PledgeLot memory pledgeLot =
            _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, 1, 0);
        CollateralRegistryUpgradeable.Location memory none;
        CollateralRegistryUpgradeable.Control memory control = _ebl();

        vm.prank(collateralTrustee);
        collateralRegistry.pause();
        assertTrue(collateralRegistry.paused());

        vm.startPrank(collateralTrustee);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.pledge(loanId, pledgeLot);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.setHaircut(loanId, lotId, 0);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.setFloor(loanId, 0);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.setStage(loanId, lotId, CollateralRegistryUpgradeable.LotStage.Afloat, false, none);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.setControl(loanId, lotId, control);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.addDoc(loanId, lotId, CollateralRegistryUpgradeable.DocKind.Ebl, bytes32(0));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.adjustQuantity(loanId, lotId, 1, "", bytes32(0));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.release(loanId, lotId, 1, CollateralRegistryUpgradeable.ReleaseReason.Loss, bytes32(0));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.liquidate(loanId, lotId, 1);
        vm.stopPrank();

        vm.prank(collateralValuer);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collateralRegistry.revalue(loanId, lotId, 1, LME, bytes32(0));

        collateralRegistry.checkCoverage(loanId);

        vm.prank(collateralTrustee);
        collateralRegistry.unpause();
        assertFalse(collateralRegistry.paused());
    }

    function _drawLoan() private returns (uint256 loanId) {
        ILoanRegistry.ImmutableLoanData memory economics = ILoanRegistry.ImmutableLoanData({
            borrowerRef: bytes32(uint256(1)),
            originalFacilitySize: SENIOR_TRANCHE + 200_000 * UNIT,
            originalSeniorTranche: SENIOR_TRANCHE,
            originalEquityTranche: 200_000 * UNIT,
            originalOfftakerPrice: SENIOR_TRANCHE + 200_000 * UNIT,
            seniorInterestRate: 100_000,
            originationDate: uint64(vm.getBlockTimestamp()),
            originalMaturityDate: uint64(vm.getBlockTimestamp() + YEAR)
        });

        vm.prank(loanRegistryManager);
        return loanRegistry.drawLoan("metadataURI", economics);
    }

    function _drawAndDisburse(uint256 amount) private returns (uint256 loanId) {
        loanId = _drawLoan();

        vm.prank(address(minter));
        loanRegistry.disburse(loanId, amount);
    }

    function _pledge(uint256 loanId, CollateralRegistryUpgradeable.PledgeLot memory pledgeLot)
        private
        returns (uint256 lotId)
    {
        vm.prank(collateralTrustee);
        return collateralRegistry.pledge(loanId, pledgeLot);
    }

    function _pledgeControlledCargo(uint256 loanId, uint256 quantity, uint256 valuePerUnit, uint32 haircutBps)
        private
        returns (uint256 lotId)
    {
        lotId = _pledge(loanId, _cargoLot(CollateralRegistryUpgradeable.Unit.Dmt, quantity, haircutBps));

        vm.prank(collateralValuer);
        collateralRegistry.revalue(loanId, lotId, valuePerUnit, LME, bytes32(0));

        vm.prank(collateralTrustee);
        collateralRegistry.setControl(loanId, lotId, _ebl());
    }

    function _cargoLot(CollateralRegistryUpgradeable.Unit unit, uint256 quantity, uint32 haircutBps)
        private
        pure
        returns (CollateralRegistryUpgradeable.PledgeLot memory pledgeLot)
    {
        pledgeLot.kind = CollateralRegistryUpgradeable.LotKind.Cargo;
        pledgeLot.unit = unit;
        pledgeLot.quantity = quantity;
        pledgeLot.haircutBps = haircutBps;
        pledgeLot.cargo = CollateralRegistryUpgradeable.CargoDetails({
            commodity: "copper concentrate",
            valuationMode: CollateralRegistryUpgradeable.CargoValuationMode.MetalConcentrate
        });
    }

    function _receivableLot(uint256 quantity)
        private
        pure
        returns (CollateralRegistryUpgradeable.PledgeLot memory pledgeLot)
    {
        pledgeLot.kind = CollateralRegistryUpgradeable.LotKind.Receivable;
        pledgeLot.unit = CollateralRegistryUpgradeable.Unit.Usd;
        pledgeLot.quantity = quantity;
        pledgeLot.receivable = CollateralRegistryUpgradeable.ReceivableDetails({
            obligorRef: bytes32(uint256(9)),
            dueDate: uint64(YEAR),
            form: CollateralRegistryUpgradeable.ReceivableForm.OpenAccount
        });
    }

    function _vessel() private pure returns (CollateralRegistryUpgradeable.Location memory) {
        return CollateralRegistryUpgradeable.Location({
            locationType: CollateralRegistryUpgradeable.LocationType.Vessel,
            identifier: "MV Example",
            trackingUrl: "https://example.com"
        });
    }

    function _control(CollateralRegistryUpgradeable.ControlKind kind, string memory ref)
        private
        pure
        returns (CollateralRegistryUpgradeable.Control memory)
    {
        return CollateralRegistryUpgradeable.Control({kind: kind, ref: ref});
    }

    function _ebl() private pure returns (CollateralRegistryUpgradeable.Control memory) {
        return _control(CollateralRegistryUpgradeable.ControlKind.EblToOrderOfTrust, "ebl-1");
    }

    function _marginCalls() private view returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == CollateralRegistryUpgradeable.MarginCall.selector) ++count;
        }
    }
}
