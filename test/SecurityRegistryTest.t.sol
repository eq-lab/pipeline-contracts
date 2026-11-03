// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILoanRegistry} from "../src/interfaces/ILoanRegistry.sol";
import {ISecurityRecordNft} from "../src/interfaces/ISecurityRecordNft.sol";
import {ISecurityRegistry} from "../src/interfaces/ISecurityRegistry.sol";
import {LoanRegistryUpgradeable} from "../src/loanRegistry/LoanRegistryUpgradeable.sol";
import {PipelineSecurityRecordNft} from "../src/PipelineSecurityRecordNft.sol";
import {PipelineSecurityRegistryReader} from "../src/PipelineSecurityRegistryReader.sol";
import {SecurityRegistryUpgradeable} from "../src/securityRegistry/SecurityRegistryUpgradeable.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract SecurityRegistryTest is PipelineTestSetUp {
    uint256 constant UNIT = 1e6;
    uint64 constant DAY = 1 days;
    uint64 constant START = 1_000 days;
    uint256 constant SENIOR = 6_000_000 * UNIT;
    bytes32 constant LME = "LME";
    bytes32 constant RECORDS_SLOT =
        bytes32(uint256(0xe4c932a8d46f090712464e8bf71540462c3831ff6628970c190523ba96dea900) + 4);

    function setUp() public override {
        super.setUp();
        vm.warp(START);

        address[] memory panel = new address[](1);
        panel[0] = inspector;

        vm.prank(securityRiskCouncil);
        securityRecordNft.setInspectors(panel);
    }

    function test_setUp() public view {
        assertEq(securityRegistry.authority(), address(authority));
        assertEq(securityRegistry.loanRegistry(), address(loanRegistry));
        assertEq(securityRegistry.recordNft(), address(securityRecordNft));
        assertEq(securityRecordNft.authority(), address(authority));
        assertEq(securityRecordNft.securityRegistry(), address(securityRegistry));
        assertEq(securityRecordNft.name(), "Pipeline Security Registry");
        assertEq(securityRecordNft.symbol(), "PLSR");
        assertEq(securityRegistry.PAR_VALUE(), UNIT);
    }

    function test_setLoanRegistry() public {
        address newLoanRegistry = makeAddr("newLoanRegistry");

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.LoanRegistrySet(newLoanRegistry);

        vm.startPrank(admin);
        securityRegistry.setLoanRegistry(newLoanRegistry);
        assertEq(securityRegistry.loanRegistry(), newLoanRegistry);

        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryZeroAddress.selector);
        securityRegistry.setLoanRegistry(address(0));
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistrySameValue.selector);
        securityRegistry.setLoanRegistry(newLoanRegistry);
        vm.stopPrank();
    }

    function test_registerOpensAPendingRecordInANewLot() public {
        uint256 loanId = _loanWithTerms();
        ISecurityRegistry.NewRecord memory input = _bl(10_000);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.RecordRegistered(loanId, 1, 1, ISecurityRegistry.Protection.EndorsedBl);

        uint256 recordId = _register(loanId, 0, input);
        assertEq(recordId, 1);

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertEq(recordData.recordId, 1);
        assertEq(recordData.loanId, loanId);
        assertEq(recordData.lotId, 1);
        assertEq(uint8(recordData.protection), uint8(ISecurityRegistry.Protection.EndorsedBl));
        assertEq(uint8(recordData.unit), uint8(ISecurityRegistry.Unit.Mt));
        assertEq(uint8(recordData.status), uint8(ISecurityRegistry.RecordStatus.PendingPerfection));
        assertEq(recordData.referenceQuantity, 1_000 * UNIT);
        assertEq(recordData.referenceGrade, input.referenceGrade);
        assertEq(recordData.commodityHash, keccak256(bytes(input.details.commodity)));
        assertEq(recordData.perfectedAt, 0);
        assertEq(recordData.attestedBy, address(0));
        assertEq(recordData.attestedAt, 0);
        assertEq(recordData.flaggedBy, 0);
        assertFalse(recordData.hasMark);

        assertEq(abi.encode(securityRecordNft.details(recordId)), abi.encode(input.details));

        PipelineSecurityRegistryReader.RecordView[] memory open = securityRegistryReader.records(loanId);
        assertEq(open.length, 1);
        assertEq(abi.encode(open[0].details), abi.encode(input.details));
        assertEq(abi.encode(open[0].record), abi.encode(recordData));
        assertEq(securityRegistryReader.activeRecords(loanId).length, 0);

        uint256 otherLoanId = _loanWithTerms();
        assertEq(_register(otherLoanId, 0, _bl(10)), 2);
        assertEq(securityRegistry.record(2).lotId, 2);
    }

    function test_registerMarksUsdRecordsAtPar() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _usdRecord(ISecurityRegistry.Protection.AssignedReceivable, 10_500_000));

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertTrue(recordData.hasMark);
        assertEq(recordData.mark.valuePerUnit, securityRegistry.PAR_VALUE());
        assertEq(recordData.mark.at, START);
        assertEq(recordData.mark.benchmark, securityRegistry.PAR_BENCHMARK());
        assertEq(recordData.mark.reportHash, bytes32(0));
    }

    function test_registerNeedsAnOpenLoanWithTerms() public {
        uint256 loanId = _drawLoan(false);

        vm.startPrank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNoTerms.selector);
        securityRegistry.register(loanId, 0, _bl(10));
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        securityRegistry.register(99, 0, _bl(10));
        vm.stopPrank();

        _setTerms(loanId, _copperTerms());
        _closeLoan(loanId);

        _expectRegisterRevert(loanId, 0, _bl(10), SecurityRegistryUpgradeable.SecurityRegistryLoanClosed.selector);
    }

    function test_registerRejectsMalformedRecords() public {
        uint256 loanId = _loanWithTerms();

        _expectRegisterRevert(loanId, 0, _bl(0), SecurityRegistryUpgradeable.SecurityRegistryInvalidQuantity.selector);

        ISecurityRegistry.NewRecord memory newRecord = _bl(10);
        newRecord.unit = ISecurityRegistry.Unit.Usd;
        _expectRegisterRevert(loanId, 0, newRecord, SecurityRegistryUpgradeable.SecurityRegistryInvalidUnit.selector);

        newRecord = _usdRecord(ISecurityRegistry.Protection.AssignedReceivable, 1);
        newRecord.unit = ISecurityRegistry.Unit.Mt;
        _expectRegisterRevert(loanId, 0, newRecord, SecurityRegistryUpgradeable.SecurityRegistryInvalidUnit.selector);

        newRecord = _usdRecord(ISecurityRegistry.Protection.CashCover, 1);
        newRecord.details.region = "China";
        _expectRegisterRevert(
            loanId, 0, newRecord, SecurityRegistryUpgradeable.SecurityRegistryInvalidLocation.selector
        );

        newRecord = _usdRecord(ISecurityRegistry.Protection.CashCover, 1);
        newRecord.details.siteHash = _h(6);
        _expectRegisterRevert(
            loanId, 0, newRecord, SecurityRegistryUpgradeable.SecurityRegistryInvalidLocation.selector
        );

        newRecord = _usdRecord(ISecurityRegistry.Protection.LcProceeds, 1);
        newRecord.details.commodity = "Copper cathodes";
        _expectRegisterRevert(
            loanId, 0, newRecord, SecurityRegistryUpgradeable.SecurityRegistryInvalidCommodity.selector
        );

        newRecord = _bl(10);
        newRecord.details.docs = new ISecurityRecordNft.Doc[](securityRecordNft.MAX_DOCS_PER_RECORD() + 1);
        _expectRegisterRevert(loanId, 0, newRecord, PipelineSecurityRecordNft.SecurityRecordNftTooManyDocs.selector);
    }

    function test_lotsKeepOneLoanAndOneGoodsUnit() public {
        uint256 loanId = _loanWithTerms();
        uint256 blId = _register(loanId, 0, _bl(10_000));
        uint256 lotId = securityRegistry.record(blId).lotId;

        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984));
        uint256 receivable =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.AssignedReceivable, 10_500_000));
        assertEq(securityRegistry.record(warehouse).lotId, lotId);
        assertEq(securityRegistry.record(receivable).lotId, lotId);

        ISecurityRegistry.NewRecord memory dmt = _bl(10);
        dmt.unit = ISecurityRegistry.Unit.Dmt;
        _expectRegisterRevert(loanId, lotId, dmt, SecurityRegistryUpgradeable.SecurityRegistryUnitMismatch.selector);
        _expectRegisterRevert(loanId, 99, _bl(10), SecurityRegistryUpgradeable.SecurityRegistryNonExistentLot.selector);

        uint256 otherLoanId = _loanWithTerms();
        _expectRegisterRevert(
            otherLoanId, lotId, _bl(10), SecurityRegistryUpgradeable.SecurityRegistryWrongLot.selector
        );

        uint256 prepayment = _register(loanId, 0, _usdRecord(ISecurityRegistry.Protection.Prepayment, 1));
        uint256 prepaidLot = securityRegistry.record(prepayment).lotId;
        _register(loanId, prepaidLot, dmt);
        _expectRegisterRevert(
            loanId, prepaidLot, _bl(10), SecurityRegistryUpgradeable.SecurityRegistryUnitMismatch.selector
        );
    }

    function test_openRecordsCapAt32AndClosingFreesASlot() public {
        uint256 loanId = _loanWithTerms();
        for (uint256 i; i < securityRegistry.MAX_OPEN_RECORDS_PER_LOAN(); ++i) {
            _register(loanId, 0, _bl(10));
        }
        _expectRegisterRevert(loanId, 0, _bl(10), SecurityRegistryUpgradeable.SecurityRegistryTooManyRecords.selector);

        _release(5);
        assertEq(_register(loanId, 0, _bl(10)), 33);

        PipelineSecurityRegistryReader.RecordView[] memory open = securityRegistryReader.records(loanId);
        assertEq(open.length, 32);
        for (uint256 i; i < open.length; ++i) {
            assertNotEq(open[i].record.recordId, 5);
        }
    }

    function test_delayedAgentCallsMustBeScheduled() public {
        uint256 loanId = _loanWithTerms();
        address delayed = makeAddr("delayed");

        vm.prank(admin);
        authority.grantRole(uint64(bytes8(keccak256("SECURITY_AGENT"))), delayed, uint32(DAY));

        bytes memory data = abi.encodeCall(SecurityRegistryUpgradeable.register, (loanId, 0, _bl(10)));
        bytes32 operationId = authority.hashOperation(delayed, address(securityRegistry), data);

        vm.prank(delayed);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, operationId));
        securityRegistry.register(loanId, 0, _bl(10));

        vm.prank(delayed);
        authority.schedule(address(securityRegistry), data, 0);
        vm.warp(START + DAY);

        vm.prank(delayed);
        uint256 recordId = securityRegistry.register(loanId, 0, _bl(10));
        assertEq(securityRecordNft.ownerOf(recordId), capitalWallet);
    }

    function test_perfectActivatesAndCountsAsTheFirstAttestation() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10_000));
        vm.warp(START + DAY);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.RecordPerfected(loanId, recordId, _h(9));

        _perfect(recordId);

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertEq(uint8(recordData.status), uint8(ISecurityRegistry.RecordStatus.Active));
        assertEq(recordData.perfectedAt, START + DAY);
        assertEq(recordData.attestedAt, START + DAY);
        assertEq(recordData.attestedBy, securityAgent);

        ISecurityRecordNft.Doc[] memory docs = securityRecordNft.details(recordId).docs;
        ISecurityRecordNft.Doc memory evidence = docs[docs.length - 1];
        assertEq(uint8(evidence.kind), uint8(ISecurityRecordNft.DocKind.Perfection));
        assertEq(evidence.hash, _h(9));

        PipelineSecurityRegistryReader.RecordView[] memory active = securityRegistryReader.activeRecords(loanId);
        assertEq(active.length, 1);
        assertEq(abi.encode(active[0].record), abi.encode(recordData));

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        securityRegistry.perfect(recordId, _h(9));
    }

    function test_perfectKeepsOneCountingRecordPerLot() public {
        uint256 loanId = _drawLoan(false);
        _setTerms(loanId, _copperTerms());
        uint256 blId = _active(loanId, _bl(10_000));
        uint256 lotId = securityRegistry.record(blId).lotId;

        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984));

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryLotAlreadyCounted.selector);
        securityRegistry.perfect(warehouse, _h(9));

        uint256 insurance =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.InsuranceLossPayee, 10_000_000));
        _perfect(insurance);

        _release(blId);
        _perfect(warehouse);
        assertEq(securityRegistryReader.activeRecords(loanId).length, 2);
    }

    function test_documentsCapAtSixteenWithTheEvidenceOnTop() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10));
        uint256 maxDocs = securityRecordNft.MAX_DOCS_PER_RECORD();

        vm.startPrank(securityAgent);
        for (uint256 n = 1; n < maxDocs; ++n) {
            securityRecordNft.addDoc(recordId, ISecurityRecordNft.DocKind.Inspection, _h(n));
        }
        assertEq(securityRecordNft.details(recordId).docs.length, maxDocs);

        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftTooManyDocs.selector);
        securityRecordNft.addDoc(recordId, ISecurityRecordNft.DocKind.Other, _h(1));
        vm.stopPrank();

        _perfect(recordId);
        _setDefault(loanId);
        _startEnforcement(recordId);
        _markEnforced(recordId);

        ISecurityRecordNft.Doc[] memory docs = securityRecordNft.details(recordId).docs;
        assertEq(docs.length, maxDocs + 2);
        assertEq(uint8(docs[16].kind), uint8(ISecurityRecordNft.DocKind.Perfection));
        assertEq(uint8(docs[17].kind), uint8(ISecurityRecordNft.DocKind.Proceeds));
        assertEq(docs[17].hash, _h(13));
    }

    function test_addDoc() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10));

        vm.expectEmit(address(securityRecordNft));
        emit PipelineSecurityRecordNft.DocAdded(loanId, recordId, ISecurityRecordNft.DocKind.LegalOpinion, _h(20));

        vm.prank(securityAgent);
        securityRecordNft.addDoc(recordId, ISecurityRecordNft.DocKind.LegalOpinion, _h(20));

        ISecurityRecordNft.Doc[] memory docs = securityRecordNft.details(recordId).docs;
        assertEq(docs.length, 2);
        assertEq(uint8(docs[1].kind), uint8(ISecurityRecordNft.DocKind.LegalOpinion));
        assertEq(docs[1].hash, _h(20));

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNonExistentRecord.selector);
        securityRecordNft.addDoc(99, ISecurityRecordNft.DocKind.Other, _h(1));
    }

    function test_attestNeedsAnActiveRecord() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10));

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        securityRegistry.attest(recordId);

        _perfect(recordId);
        address otherAgent = makeAddr("otherAgent");
        vm.prank(admin);
        authority.grantRole(uint64(bytes8(keccak256("SECURITY_AGENT"))), otherAgent, 0);
        vm.warp(START + 7 * DAY);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.RecordAttested(loanId, recordId, otherAgent);

        vm.prank(otherAgent);
        securityRegistry.attest(recordId);

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertEq(recordData.attestedBy, otherAgent);
        assertEq(recordData.attestedAt, START + 7 * DAY);
        assertEq(recordData.perfectedAt, START);

        _releaseWithConsent(recordId);

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        securityRegistry.attest(recordId);
    }

    function test_handoverMovesTheLotToTheNewRecord() public {
        uint256 loanId = _loanWithTerms();
        uint256 blId = _active(loanId, _bl(10_000));
        _revalue(blId, 10_000);
        uint256 lotId = securityRegistry.record(blId).lotId;

        vm.warp(START + DAY);
        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984));

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.RecordHandedOver(loanId, blId, warehouse, _h(12));

        _handover(blId, warehouse);

        ISecurityRegistry.Record memory from = securityRegistry.record(blId);
        ISecurityRegistry.Record memory to = securityRegistry.record(warehouse);
        assertEq(uint8(from.status), uint8(ISecurityRegistry.RecordStatus.Released));
        assertEq(uint8(to.status), uint8(ISecurityRegistry.RecordStatus.Active));
        assertEq(to.perfectedAt, START + DAY);
        assertEq(to.attestedAt, START + DAY);
        assertEq(to.attestedBy, securityAgent);
        ISecurityRecordNft.Doc[] memory docs = securityRecordNft.details(warehouse).docs;
        assertEq(uint8(docs[docs.length - 1].kind), uint8(ISecurityRecordNft.DocKind.Perfection));
        assertTrue(to.hasMark);
        assertEq(abi.encode(to.mark), abi.encode(from.mark));

        PipelineSecurityRegistryReader.RecordView[] memory open = securityRegistryReader.records(loanId);
        assertEq(open.length, 1);
        assertEq(abi.encode(open[0].record), abi.encode(to));
        assertEq(securityRegistry.collateralValue(loanId), 9_984_000 * UNIT);

        uint256 receivable =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.AssignedReceivable, 10_500_000));
        _handover(warehouse, receivable);

        assertEq(securityRegistry.record(receivable).mark.benchmark, securityRegistry.PAR_BENCHMARK());
        assertEq(securityRegistry.collateralValue(loanId), 10_500_000 * UNIT);
    }

    function test_handoverCarriesTheMarkOnlyForTheSameCommodity() public {
        uint256 loanId = _loanWithTerms();
        uint256 blId = _active(loanId, _bl(10_000));
        _revalue(blId, 10_000);
        uint256 lotId = securityRegistry.record(blId).lotId;

        ISecurityRegistry.NewRecord memory nickel = _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984);
        nickel.details.commodity = "Nickel ore";
        uint256 warehouse = _register(loanId, lotId, nickel);
        _handover(blId, warehouse);

        ISecurityRegistry.Record memory to = securityRegistry.record(warehouse);
        assertFalse(to.hasMark);
        assertEq(to.mark.valuePerUnit, 0);
        assertEq(securityRegistry.collateralValue(loanId), 0);
    }

    function test_handoverRejections() public {
        uint256 loanId = _loanWithTerms();
        uint256 blId = _active(loanId, _bl(10_000));
        uint256 lotId = securityRegistry.record(blId).lotId;
        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984));
        uint256 otherLot = _register(loanId, 0, _bl(10));
        uint256 insurance =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.InsuranceLossPayee, 10_000_000));

        _expectHandoverRevert(blId, otherLot, SecurityRegistryUpgradeable.SecurityRegistryWrongLot.selector);
        _expectHandoverRevert(warehouse, blId, SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        _expectHandoverRevert(blId, blId, SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        _expectHandoverRevert(blId, insurance, SecurityRegistryUpgradeable.SecurityRegistryNotCounting.selector);
        _perfect(insurance);
        _expectHandoverRevert(insurance, warehouse, SecurityRegistryUpgradeable.SecurityRegistryNotCounting.selector);
        _expectHandoverRevert(blId, 99, SecurityRegistryUpgradeable.SecurityRegistryNonExistentRecord.selector);

        bytes32 flaggedBySlot = bytes32(uint256(keccak256(abi.encode(blId, RECORDS_SLOT))) + 5);
        vm.store(address(securityRegistry), flaggedBySlot, bytes32(uint256(1)));
        assertEq(securityRegistry.record(blId).flaggedBy, 1);
        _expectHandoverRevert(blId, warehouse, SecurityRegistryUpgradeable.SecurityRegistryFlagged.selector);
    }

    function test_releaseClosesAnyOpenRecordForGood() public {
        uint256 loanId = _loanWithTerms();
        _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 10_000_000));
        uint256 pending = _register(loanId, 0, _bl(10));
        uint256 activeBl = _active(loanId, _bl(10));
        uint256 enforced = _active(loanId, _bl(10));
        _setDefault(loanId);
        _startEnforcement(enforced);

        uint256[3] memory recordIds = [pending, activeBl, enforced];
        for (uint256 i; i < recordIds.length; ++i) {
            vm.expectEmit(address(securityRegistry));
            emit SecurityRegistryUpgradeable.RecordReleased(loanId, recordIds[i], _h(10), false);

            _release(recordIds[i]);
            assertEq(
                uint8(securityRegistry.record(recordIds[i]).status), uint8(ISecurityRegistry.RecordStatus.Released)
            );

            vm.prank(securityAgent);
            vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
            securityRegistry.release(recordIds[i], _h(10));
        }
        assertEq(securityRegistryReader.records(loanId).length, 1);

        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNonExistentRecord.selector);
        securityRegistry.record(99);
    }

    function test_releaseNeedsRoomUnderTheAdvanceRatio() public {
        uint256 loanId = _loanWithTerms();
        uint256 blId = _active(loanId, _bl(10_000));
        _revalue(blId, 10_000);
        uint256 lotId = securityRegistry.record(blId).lotId;
        uint256 cash = _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000_000));

        _release(cash);
        cash = _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000_000));

        _revalue(blId, 7_000);
        assertEq(_marginCallAt(loanId), 0);

        vm.startPrank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryLtvTooHigh.selector);
        securityRegistry.release(cash, _h(10));
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryLtvTooHigh.selector);
        securityRegistry.release(blId, _h(10));
        vm.stopPrank();

        uint256 insurance =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.InsuranceLossPayee, 10_000_000));
        _perfect(insurance);
        _release(insurance);
        uint256 pending = _register(loanId, 0, _bl(10));
        _release(pending);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.RecordReleased(loanId, cash, _h(14), true);

        _releaseWithConsent(cash);
        assertEq(_marginCallAt(loanId), START);

        vm.prank(securityRiskCouncil);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        securityRegistry.releaseWithConsent(cash, _h(14));

        _repayAll(loanId);
        _release(blId);
        assertEq(securityRegistryReader.records(loanId).length, 0);
    }

    function test_enforcementNeedsADefaultedLoanAndAnActiveRecord() public {
        uint256 loanId = _loanWithTerms();
        uint256 pending = _register(loanId, 0, _bl(10));
        uint256 recordId = _active(loanId, _bl(10));

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongLoanStatus.selector);
        securityRegistry.startEnforcement(recordId);

        _setDefault(loanId);

        vm.startPrank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        securityRegistry.startEnforcement(pending);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        securityRegistry.markEnforced(recordId, _h(13));

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.EnforcementStarted(loanId, recordId);

        securityRegistry.startEnforcement(recordId);
        vm.stopPrank();

        assertEq(
            uint8(securityRegistry.record(recordId).status), uint8(ISecurityRegistry.RecordStatus.UnderEnforcement)
        );
        assertEq(securityRegistryReader.records(loanId).length, 2);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.RecordEnforced(loanId, recordId, _h(13));

        _markEnforced(recordId);

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertEq(uint8(recordData.status), uint8(ISecurityRegistry.RecordStatus.Enforced));
        ISecurityRecordNft.Doc[] memory docs = securityRecordNft.details(recordId).docs;
        assertEq(uint8(docs[docs.length - 1].kind), uint8(ISecurityRecordNft.DocKind.Proceeds));
        assertEq(securityRegistryReader.records(loanId).length, 1);

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryWrongRecordStatus.selector);
        securityRegistry.markEnforced(recordId, _h(13));
    }

    function test_reportMandateBreachNeedsAnOpenLoan() public {
        uint256 loanId = _loanWithTerms();

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.MandateBreach(loanId, _h(15));

        vm.prank(securityAgent);
        securityRegistry.reportMandateBreach(loanId, _h(15));

        vm.prank(securityAgent);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        securityRegistry.reportMandateBreach(99, _h(15));

        uint256 closed = _drawLoan(false);
        _closeLoan(closed);

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryLoanClosed.selector);
        securityRegistry.reportMandateBreach(closed, _h(15));
    }

    function test_writesStopWhilePaused() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10));

        vm.prank(pauser);
        securityRegistry.pause();
        assertTrue(securityRegistry.paused());

        vm.startPrank(securityAgent);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.register(loanId, 0, _bl(10));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.perfect(recordId, _h(9));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.handover(recordId, recordId, _h(12));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.attest(recordId);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRecordNft.addDoc(recordId, ISecurityRecordNft.DocKind.Other, _h(1));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.release(recordId, _h(10));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.reportMandateBreach(loanId, _h(15));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.startEnforcement(recordId);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.markEnforced(recordId, _h(13));
        vm.stopPrank();

        vm.startPrank(securityRiskCouncil);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.setTerms(loanId, _copperTerms());
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.releaseWithConsent(recordId, _h(14));
        vm.stopPrank();

        vm.prank(securityValuer);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.revalue(recordId, UNIT, LME, _h(11));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.checkCoverage(loanId);

        vm.prank(pauser);
        securityRegistry.unpause();
        assertFalse(securityRegistry.paused());
    }

    function test_eachRecordIsASoulboundNftOfTheLoansHolder() public {
        uint256 loanId = _loanWithTerms();
        address holder = loanRegistry.ownerOf(loanId);
        assertEq(holder, capitalWallet);

        vm.expectEmit(address(securityRecordNft));
        emit IERC721.Transfer(address(0), holder, 1);

        uint256 blId = _register(loanId, 0, _bl(10));
        uint256 cashId = _register(loanId, 0, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000));
        assertEq(securityRecordNft.ownerOf(blId), holder);
        assertEq(securityRecordNft.ownerOf(cashId), holder);
        assertEq(securityRecordNft.balanceOf(holder), 2);
        assertEq(securityRecordNft.tokenURI(blId), "");

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 99));
        securityRecordNft.tokenURI(99);

        address other = makeAddr("other");

        vm.startPrank(holder);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftNonTransferable.selector);
        securityRecordNft.transferFrom(holder, other, blId);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftNonTransferable.selector);
        securityRecordNft.safeTransferFrom(holder, other, blId);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftNonTransferable.selector);
        securityRecordNft.approve(other, blId);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftNonTransferable.selector);
        securityRecordNft.setApprovalForAll(other, true);
        vm.stopPrank();

        vm.prank(other);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftNonTransferable.selector);
        securityRecordNft.transferFrom(holder, other, blId);
    }

    function test_aRecordThatEndsBurnsItsNft() public {
        uint256 loanId = _loanWithTerms();
        address holder = loanRegistry.ownerOf(loanId);
        uint256 cashId = _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 10_000_000));
        uint256 released = _register(loanId, 0, _bl(10));
        uint256 handedOver = _active(loanId, _bl(10));
        uint256 lotId = securityRegistry.record(handedOver).lotId;
        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 10));
        uint256 byConsent = _register(loanId, 0, _bl(10));
        uint256 enforced = _active(loanId, _bl(10));
        assertEq(securityRecordNft.balanceOf(holder), 6);

        _expectBurn(holder, released);
        _release(released);
        _assertBurned(released);

        _expectBurn(holder, handedOver);
        _handover(handedOver, warehouse);
        _assertBurned(handedOver);

        _expectBurn(holder, byConsent);
        _releaseWithConsent(byConsent);
        _assertBurned(byConsent);

        _setDefault(loanId);
        _startEnforcement(enforced);
        _expectBurn(holder, enforced);
        _markEnforced(enforced);
        _assertBurned(enforced);

        assertEq(uint8(securityRegistry.record(released).status), uint8(ISecurityRegistry.RecordStatus.Released));
        assertEq(securityRecordNft.ownerOf(cashId), holder);
        assertEq(securityRecordNft.ownerOf(warehouse), holder);
        assertEq(securityRecordNft.balanceOf(holder), 2);
    }

    function test_theExampleDeal() public {
        uint256 loanId = _drawLoan(false);
        _setTerms(loanId, _copperTerms());
        uint256 blId = _register(loanId, 0, _bl(10_000));
        uint256 lotId = securityRegistry.record(blId).lotId;

        vm.prank(address(minter));
        loanRegistry.disburse(loanId, SENIOR);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.PriceStale(loanId, type(uint32).max, 8_500);

        _perfect(blId);
        assertEq(_marginCallAt(loanId), 0);

        _revalue(blId, 10_000);
        assertEq(securityRegistry.collateralValue(loanId), 10_000_000 * UNIT);
        assertEq(securityRegistry.coverage(loanId), 16_666);
        assertEq(_expectedLtv(loanId, 10_000_000 * UNIT), 6_000);

        uint256 insurance =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.InsuranceLossPayee, 10_000_000));
        _perfect(insurance);
        assertEq(securityRegistry.collateralValue(loanId), 10_000_000 * UNIT);

        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984));
        _handover(blId, warehouse);
        assertEq(securityRegistry.collateralValue(loanId), 9_984_000 * UNIT);

        uint256 receivable =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.AssignedReceivable, 10_500_000));
        _handover(warehouse, receivable);
        assertEq(securityRegistry.collateralValue(loanId), 10_500_000 * UNIT);

        PipelineSecurityRegistryReader.RecordView[] memory active = securityRegistryReader.activeRecords(loanId);
        assertEq(active.length, 2);
        assertEq(active[0].record.recordId, receivable);
        assertEq(active[1].record.recordId, insurance);

        _repayAll(loanId);
        _release(insurance);
        _release(receivable);
        assertEq(securityRegistryReader.records(loanId).length, 0);
        assertEq(securityRegistry.collateralValue(loanId), 0);
        assertEq(_marginCallAt(loanId), 0);
    }

    function test_marginCallOpensAboveTheMarginCallRatioAndCuresAtTheAdvanceRatio() public {
        uint256 loanId = _loanWithTerms();
        uint256 warehouse = _active(loanId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984));
        _revalue(warehouse, 10_000);
        assertEq(_marginCallAt(loanId), 0);

        uint64 day30 = START + 30 * DAY;
        vm.warp(day30);
        uint32 ltvBps = _expectedLtv(loanId, 6_988_800 * UNIT);
        assertEq(ltvBps, 8_670);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.MarginCall(loanId, ltvBps, 8_500, day30 + 7 * DAY);

        _revalue(warehouse, 7_000);
        assertEq(_marginCallAt(loanId), day30);

        _revalue(warehouse, 7_400);
        securityRegistry.checkCoverage(loanId);
        assertEq(_marginCallAt(loanId), day30);

        _revalue(warehouse, 7_000);
        _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 584_950));
        assertEq(_marginCallAt(loanId), day30);

        ltvBps = _expectedLtv(loanId, 7_573_950 * UNIT);
        assertEq(ltvBps, 8_000);
        uint256 topUp = _register(loanId, 0, _usdRecord(ISecurityRegistry.Protection.CashCover, 200));

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.MarginCallCured(loanId, ltvBps);

        _perfect(topUp);
        assertEq(_marginCallAt(loanId), 0);
        assertEq(uint8(securityRegistry.record(topUp).status), uint8(ISecurityRegistry.RecordStatus.Active));
    }

    function test_aStalePriceOpensNoMarginCall() public {
        uint256 loanId = _loanWithTerms();
        uint256 first = _active(loanId, _bl(10_000));
        uint256 second = _active(loanId, _bl(10_000));
        _revalue(first, 5_000);
        _revalue(second, 10_000);
        assertEq(_marginCallAt(loanId), 0);

        uint64 day3 = START + 3 * DAY;
        vm.warp(day3);
        uint32 ltvBps = _expectedLtv(loanId, 6_000_000 * UNIT);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.PriceStale(loanId, ltvBps, 8_500);

        _revalue(second, 1_000);
        securityRegistry.checkCoverage(loanId);
        assertEq(_marginCallAt(loanId), 0);
        assertEq(securityRegistryReader.markAge(loanId), 3 * DAY);

        ISecurityRegistry.Terms memory terms = _copperTerms();
        terms.priceStaleAfter = 0;
        _setTerms(loanId, terms);
        assertEq(_marginCallAt(loanId), day3);
    }

    function test_separateLotsAddUpAndEnforcementStopsCounting() public {
        uint256 loanId = _loanWithTerms();
        uint256 first = _active(loanId, _bl(5_000));
        uint256 second = _active(loanId, _bl(5_000));
        _active(loanId, _usdRecord(ISecurityRegistry.Protection.Prepayment, 6_000_000));
        _active(loanId, _usdRecord(ISecurityRegistry.Protection.InsuranceLossPayee, 10_000_000));
        _revalue(first, 10_000);
        _revalue(second, 10_000);
        assertEq(securityRegistry.collateralValue(loanId), 16_000_000 * UNIT);

        _setDefault(loanId);
        _startEnforcement(first);
        assertEq(securityRegistry.collateralValue(loanId), 11_000_000 * UNIT);
    }

    function test_coverageIsMaxWithoutDebt() public {
        uint256 loanId = _drawLoan(false);
        _setTerms(loanId, _copperTerms());
        assertEq(securityRegistry.coverage(loanId), type(uint32).max);

        _active(loanId, _bl(10));
        assertEq(securityRegistry.coverage(loanId), type(uint32).max);
        assertEq(_marginCallAt(loanId), 0);
    }

    function test_checkCoverageIsOpenToAnyoneButStopsWhilePaused() public {
        uint256 loanId = _loanWithTerms();
        securityRegistry.checkCoverage(99);

        vm.prank(makeAddr("anyone"));
        securityRegistry.checkCoverage(loanId);
        assertEq(_marginCallAt(loanId), START);

        vm.prank(pauser);
        securityRegistry.pause();
        vm.warp(START + DAY);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.checkCoverage(loanId);
        assertEq(securityRegistry.coverage(loanId), 0);
    }

    function test_setTermsKeepsTheContractsMarginCall() public {
        uint256 loanId = _drawLoan(true);

        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNoTerms.selector);
        securityRegistry.terms(loanId);

        ISecurityRegistry.Terms memory terms = _copperTerms();
        terms.marginCallAt = 123;
        _setTerms(loanId, terms);
        assertEq(_marginCallAt(loanId), START);

        vm.warp(START + DAY);
        ISecurityRegistry.Terms memory expected = _copperTerms();
        expected.marginCallAt = START;

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.TermsSet(loanId, expected);

        _setTerms(loanId, _copperTerms());
        assertEq(_marginCallAt(loanId), START);

        _active(loanId, _usdRecord(ISecurityRegistry.Protection.Prepayment, 8_000_000));
        assertEq(_marginCallAt(loanId), 0);
    }

    function test_setTermsRejections() public {
        uint256 loanId = _drawLoan(true);
        ISecurityRegistry.Terms memory terms = _copperTerms();
        terms.marginCallRatioBps = 7_999;

        vm.prank(securityRiskCouncil);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryInvalidRatio.selector);
        securityRegistry.setTerms(loanId, terms);

        terms.marginCallRatioBps = 8_000;
        _setTerms(loanId, terms);
        assertEq(securityRegistry.terms(loanId).marginCallRatioBps, 8_000);

        vm.prank(securityRiskCouncil);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        securityRegistry.setTerms(99, _copperTerms());
    }

    function test_revalueIsKeyedByRecord() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _active(loanId, _bl(10_000));

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.Revalued(loanId, recordId, 10_000 * UNIT, LME, _h(11));

        _revalue(recordId, 10_000);
        assertEq(securityRegistry.collateralValue(loanId), 10_000_000 * UNIT);

        ISecurityRegistry.Mark memory mark = securityRegistry.record(recordId).mark;
        assertEq(mark.valuePerUnit, 10_000 * UNIT);
        assertEq(mark.at, START);
        assertEq(mark.benchmark, LME);
        assertEq(mark.reportHash, _h(11));

        _revalue(recordId, 0);
        assertEq(securityRegistry.collateralValue(loanId), 0);

        vm.prank(securityValuer);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNonExistentRecord.selector);
        securityRegistry.revalue(99, 1, LME, _h(1));

        uint256 cash = _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000_000));
        _revalue(cash, 2);
        assertEq(securityRegistry.record(cash).mark.valuePerUnit, 2 * UNIT);
        assertEq(securityRegistry.collateralValue(loanId), 1_000_000 * UNIT);
    }

    function test_markAgeCoversTheCountedGoodsRecords() public {
        uint256 loanId = _loanWithTerms();
        assertEq(securityRegistryReader.markAge(loanId), 0);

        _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000));
        uint256 goods = _register(loanId, 0, _bl(10));
        vm.warp(START + 3 * DAY);
        assertEq(securityRegistryReader.markAge(loanId), 0);

        _perfect(goods);
        assertEq(securityRegistryReader.markAge(loanId), type(uint64).max);

        _revalue(goods, 10_000);
        vm.warp(START + 4 * DAY);
        assertEq(securityRegistryReader.markAge(loanId), DAY);
    }

    function test_theExampleDealInspections() public {
        uint256 loanId = _drawLoan(false);
        _setTerms(loanId, _copperTerms());
        uint256 blId = _register(loanId, 0, _bl(10_000));
        uint256 lotId = securityRegistry.record(blId).lotId;

        ISecurityRecordNft.NewInspection memory input =
            _certificate(ISecurityRecordNft.InspectionKind.LoadingTally, 10_002);

        vm.expectEmit(address(securityRecordNft));
        emit PipelineSecurityRecordNft.InspectionRecorded(
            loanId, blId, 1, lotId, inspector, ISecurityRecordNft.InspectionKind.LoadingTally
        );

        uint256 loading = _enter(blId, input);
        assertEq(loading, 1);

        ISecurityRecordNft.Inspection memory entered = securityRecordNft.inspection(loading);
        assertEq(entered.inspectionId, 1);
        assertEq(entered.recordId, blId);
        assertEq(entered.lotId, lotId);
        assertEq(entered.inspector, inspector);
        assertEq(uint8(entered.kind), uint8(ISecurityRecordNft.InspectionKind.LoadingTally));
        assertEq(entered.inspectedAt, START);
        assertEq(entered.region, input.region);
        assertEq(entered.siteHash, input.siteHash);
        assertEq(entered.quantity, 10_002 * UNIT / 10);
        assertEq(entered.grade, 0);
        assertEq(entered.certificateHash, input.certificateHash);
        assertEq(entered.certificateNo, input.certificateNo);
        assertEq(entered.enteredBy, securityInspectionOperator);
        assertEq(entered.enteredAt, START);
        assertEq(entered.approvedBy, address(0));
        assertEq(entered.approvedAt, 0);
        assertEq(entered.varianceReferenceBps, 0);
        assertEq(entered.variancePreviousBps, 0);
        assertEq(entered.varianceGradeBps, 0);

        vm.warp(START + DAY);

        vm.expectEmit(address(securityRecordNft));
        emit PipelineSecurityRecordNft.InspectionApproved(
            loanId, blId, loading, securityInspectionSecondOperator, 2, 0, 0, false
        );

        _approve(loading);

        ISecurityRecordNft.Inspection memory approved = securityRecordNft.inspection(loading);
        assertEq(approved.approvedBy, securityInspectionSecondOperator);
        assertEq(approved.approvedAt, START + DAY);

        vm.prank(address(minter));
        loanRegistry.disburse(loanId, SENIOR);
        _perfect(blId);
        _revalue(blId, 10_000);
        assertEq(securityRegistry.collateralValue(loanId), 10_000_000 * UNIT);

        uint256 discharge = _enter(blId, _certificate(ISecurityRecordNft.InspectionKind.DischargeSurvey, 9_984));

        vm.expectEmit(address(securityRecordNft));
        emit PipelineSecurityRecordNft.InspectionApproved(
            loanId, blId, discharge, securityInspectionSecondOperator, -16, -18, 0, false
        );

        _approve(discharge);
        assertEq(securityRegistry.record(blId).flaggedBy, 0);
        assertEq(securityRegistry.collateralValue(loanId), 9_984_000 * UNIT);

        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984));
        _handover(blId, warehouse);
        assertEq(securityRegistry.collateralValue(loanId), 9_984_000 * UNIT);

        ISecurityRecordNft.Inspection[] memory all = securityRecordNft.inspections(blId);
        assertEq(all.length, 2);
        assertEq(all[0].inspectionId, loading);
        assertEq(all[1].inspectionId, discharge);
        assertEq(securityRecordNft.inspections(warehouse).length, 0);
    }

    function test_recordInspectionRejections() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10_000));
        ISecurityRecordNft.NewInspection memory valid =
            _certificate(ISecurityRecordNft.InspectionKind.StockCount, 10_000);

        _expectEnterRevert(99, valid, SecurityRegistryUpgradeable.SecurityRegistryNonExistentRecord.selector);

        uint256 cash = _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1));
        _expectEnterRevert(cash, valid, PipelineSecurityRecordNft.SecurityRecordNftNotGoodsRecord.selector);

        ISecurityRecordNft.NewInspection memory input =
            _certificate(ISecurityRecordNft.InspectionKind.StockCount, 10_000);
        input.inspector = makeAddr("notOnThePanel");
        _expectEnterRevert(recordId, input, PipelineSecurityRecordNft.SecurityRecordNftNotInspector.selector);

        input = _certificate(ISecurityRecordNft.InspectionKind.StockCount, 10_000);
        input.inspectedAt = START + 1;
        _expectEnterRevert(recordId, input, PipelineSecurityRecordNft.SecurityRecordNftInvalidInspectionDate.selector);

        uint256 released = _register(loanId, 0, _bl(10));
        _release(released);
        _expectEnterRevert(released, valid, PipelineSecurityRecordNft.SecurityRecordNftWrongRecordStatus.selector);
    }

    function test_inspectionsCapAtSixtyFourPerRecord() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10_000));
        ISecurityRecordNft.NewInspection memory input =
            _certificate(ISecurityRecordNft.InspectionKind.StockCount, 10_000);

        uint256 maxInspections = securityRecordNft.MAX_INSPECTIONS_PER_RECORD();
        for (uint256 i; i < maxInspections; ++i) {
            _enter(recordId, input);
        }

        _expectEnterRevert(recordId, input, PipelineSecurityRecordNft.SecurityRecordNftTooManyInspections.selector);
        assertEq(securityRecordNft.inspections(recordId).length, maxInspections);
    }

    function test_approvalNeedsASecondOperatorAndHappensOnce() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _active(loanId, _bl(10_000));
        _revalue(recordId, 10_000);
        uint256 inspectionId = _enter(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_000));

        assertEq(securityRegistry.collateralValue(loanId), 10_000_000 * UNIT);
        assertEq(securityRegistry.record(recordId).flaggedBy, 0);

        vm.prank(securityInspectionOperator);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftSameOperator.selector);
        securityRecordNft.approveInspection(inspectionId);

        vm.startPrank(securityInspectionSecondOperator);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftNonExistentInspection.selector);
        securityRecordNft.approveInspection(99);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftNonExistentInspection.selector);
        securityRecordNft.approveInspection(0);

        securityRecordNft.approveInspection(inspectionId);
        assertEq(securityRegistry.collateralValue(loanId), 9_000_000 * UNIT);

        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftAlreadyApproved.selector);
        securityRecordNft.approveInspection(inspectionId);
        vm.stopPrank();

        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftNonExistentInspection.selector);
        securityRecordNft.inspection(99);
    }

    function test_operatorCallsMustBeDirect() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10));
        ISecurityRecordNft.NewInspection memory input = _certificate(ISecurityRecordNft.InspectionKind.LoadingTally, 10);

        vm.prank(securityInspectionOperator);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftDirectCallOnly.selector);
        authority.execute(
            address(securityRecordNft), abi.encodeCall(PipelineSecurityRecordNft.recordInspection, (recordId, input))
        );

        uint256 inspectionId = _enter(recordId, input);

        vm.prank(securityInspectionOperator);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftDirectCallOnly.selector);
        authority.execute(
            address(securityRecordNft), abi.encodeCall(PipelineSecurityRecordNft.approveInspection, (inspectionId))
        );
        assertEq(securityRecordNft.inspection(inspectionId).approvedBy, address(0));
    }

    function test_agentsAndOperatorsKeepToTheirOwnWrites() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10));
        ISecurityRecordNft.NewInspection memory input = _certificate(ISecurityRecordNft.InspectionKind.LoadingTally, 10);
        uint256 inspectionId = _enter(recordId, input);

        bytes memory agentUnauthorized =
            abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, securityAgent);
        vm.startPrank(securityAgent);
        vm.expectRevert(agentUnauthorized);
        securityRecordNft.recordInspection(recordId, input);
        vm.expectRevert(agentUnauthorized);
        securityRecordNft.approveInspection(inspectionId);
        vm.stopPrank();

        vm.prank(securityInspectionOperator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, securityInspectionOperator)
        );
        securityRegistry.register(loanId, 0, _bl(10));
    }

    function test_variancesRoundHalfAwayFromZeroAndSaturate() public {
        uint256 loanId = _loanWithTerms();

        assertEq(_varianceOf(loanId, 10_002, 9_984), -18);
        assertEq(_varianceOf(loanId, 10_000, 9_984), -16);
        assertEq(_varianceOf(loanId, 10_000, 10_000), 0);
        assertEq(_varianceOf(loanId, 20_000, 20_001), 1);
        assertEq(_varianceOf(loanId, 20_000, 19_999), -1);
        assertEq(_varianceOf(loanId, 200_000, 200_009), 0);
        assertEq(_varianceOf(loanId, 200_000, 199_991), 0);
        assertEq(_varianceOf(loanId, 1_000, 0), -10_000);
        assertEq(_varianceOf(loanId, 1, type(uint256).max), type(int32).max);
        assertEq(_varianceOf(loanId, type(uint256).max, 0), -10_000);
    }

    function test_aShortfallFlagsTheRecordAndCountsAtOnce() public {
        uint256 loanId = _loanWithTerms();
        uint256 warehouse = _active(loanId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 9_984));
        _revalue(warehouse, 10_000);
        uint256 lotId = securityRegistry.record(warehouse).lotId;
        uint256 count = _enter(warehouse, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_700));

        vm.expectEmit(address(securityRecordNft));
        emit PipelineSecurityRecordNft.InspectionApproved(
            loanId, warehouse, count, securityInspectionSecondOperator, -284, 0, 0, true
        );

        _approve(count);
        assertEq(securityRegistry.record(warehouse).flaggedBy, count);
        assertEq(securityRegistry.collateralValue(loanId), 9_700_000 * UNIT);

        uint256 receivable =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.AssignedReceivable, 10_500_000));
        _expectHandoverRevert(warehouse, receivable, SecurityRegistryUpgradeable.SecurityRegistryFlagged.selector);

        uint256 lower = _inspect(warehouse, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_000));
        assertEq(securityRegistry.record(warehouse).flaggedBy, lower);
    }

    function test_tolerancesFlagAboveTheirLimitInEitherDirection() public {
        uint256 loanId = _loanWithTerms();

        assertFalse(_flagsOn(loanId, 10_050));
        assertTrue(_flagsOn(loanId, 10_051));
        assertFalse(_flagsOn(loanId, 9_950));
        assertTrue(_flagsOn(loanId, 9_949));

        uint256 recordId = _register(loanId, 0, _bl(10_000));
        _inspect(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_950));
        assertEq(securityRegistry.record(recordId).flaggedBy, 0);

        uint256 second = _inspect(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 10_049));
        ISecurityRecordNft.Inspection memory inspection = securityRecordNft.inspection(second);
        assertEq(inspection.varianceReferenceBps, 49);
        assertEq(inspection.variancePreviousBps, 99);
        assertEq(securityRegistry.record(recordId).flaggedBy, second);
    }

    function test_anAssayMeasuresGradeOnly() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _active(loanId, _bl(10_000));
        _revalue(recordId, 10_000);
        _inspect(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_990));

        uint256 assay = _inspect(recordId, _assay(99_500_000));
        ISecurityRecordNft.Inspection memory inspection = securityRecordNft.inspection(assay);
        assertEq(inspection.varianceReferenceBps, 0);
        assertEq(inspection.variancePreviousBps, 0);
        assertEq(inspection.varianceGradeBps, -49);
        assertEq(securityRegistry.record(recordId).flaggedBy, 0);
        assertEq(securityRegistry.collateralValue(loanId), 9_990_000 * UNIT);

        uint256 next = _inspect(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_990));
        assertEq(securityRecordNft.inspection(next).variancePreviousBps, 0);

        uint256 lowGrade = _inspect(recordId, _assay(98_000_000));
        assertEq(securityRecordNft.inspection(lowGrade).varianceGradeBps, -199);
        assertEq(securityRegistry.record(recordId).flaggedBy, lowGrade);
        assertEq(securityRegistry.collateralValue(loanId), 9_990_000 * UNIT);

        _inspect(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_990));
        assertEq(securityRegistry.record(recordId).flaggedBy, lowGrade);

        ISecurityRegistry.NewRecord memory noGrade = _bl(10);
        noGrade.referenceGrade = 0;
        uint256 ungraded = _active(loanId, noGrade);
        uint256 unmeasured = _inspect(ungraded, _assay(98_000_000));
        assertEq(securityRecordNft.inspection(unmeasured).varianceGradeBps, 0);
        assertEq(securityRegistry.record(ungraded).flaggedBy, 0);
    }

    function test_theLatestInspectionIsTheNewestByDate() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _active(loanId, _bl(10_000));
        _revalue(recordId, 10_000);

        vm.warp(START + DAY);
        ISecurityRecordNft.NewInspection memory older =
            _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_000);
        older.inspectedAt = START;

        uint256 newerId = _enter(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_500));
        uint256 olderId = _enter(recordId, older);

        _approve(newerId);
        _approve(olderId);
        assertEq(securityRegistry.collateralValue(loanId), 9_500_000 * UNIT);

        ISecurityRecordNft.Inspection memory inspection = securityRecordNft.inspection(olderId);
        assertEq(inspection.varianceReferenceBps, -1_000);
        assertEq(inspection.variancePreviousBps, -526);
        assertEq(securityRegistry.record(recordId).flaggedBy, olderId);
    }

    function test_aLotsLatestInspectionCountsForItsGoodsRecordsOnly() public {
        uint256 loanId = _loanWithTerms();
        uint256 blId = _active(loanId, _bl(10_000));
        _revalue(blId, 10_000);
        uint256 lotId = securityRegistry.record(blId).lotId;
        uint256 elsewhere = _active(loanId, _bl(10_000));
        _revalue(elsewhere, 10_000);

        _inspect(blId, _certificate(ISecurityRecordNft.InspectionKind.DischargeSurvey, 9_000));
        assertEq(securityRegistry.collateralValue(loanId), 19_000_000 * UNIT);
        _resolveFlag(blId, ISecurityRegistry.FlagOutcome.TopUpRequired);

        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 10_000));
        _handover(blId, warehouse);
        assertEq(securityRegistry.collateralValue(loanId), 19_000_000 * UNIT);

        uint256 receivable =
            _register(loanId, lotId, _usdRecord(ISecurityRegistry.Protection.AssignedReceivable, 10_500_000));
        _handover(warehouse, receivable);
        assertEq(securityRegistry.collateralValue(loanId), 20_500_000 * UNIT);
    }

    function test_anInspectionApprovedAfterAHandoverFlagsTheReleasedRecord() public {
        uint256 loanId = _loanWithTerms();
        uint256 blId = _active(loanId, _bl(10_000));
        _revalue(blId, 10_000);
        uint256 lotId = securityRegistry.record(blId).lotId;
        uint256 survey = _enter(blId, _certificate(ISecurityRecordNft.InspectionKind.DischargeSurvey, 9_000));

        uint256 warehouse = _register(loanId, lotId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 10_000));
        _handover(blId, warehouse);
        _approve(survey);

        assertEq(securityRegistry.record(blId).flaggedBy, survey);
        assertEq(securityRegistry.record(warehouse).flaggedBy, 0);

        PipelineSecurityRegistryReader.CoverageDetail memory detail = securityRegistryReader.coverageDetail(loanId);
        assertEq(detail.value, 9_000_000 * UNIT);
        assertEq(detail.flaggedValue, 0);
    }

    function test_aShortfallCanOpenAMarginCallAndBlockARelease() public {
        uint256 loanId = _loanWithTerms();
        uint256 warehouse = _active(loanId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 10_000));
        _revalue(warehouse, 8_000);
        uint256 cash = _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 500_000));
        assertEq(_marginCallAt(loanId), 0);

        _inspect(warehouse, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 8_500));
        assertEq(_marginCallAt(loanId), 0);

        vm.prank(securityAgent);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryLtvTooHigh.selector);
        securityRegistry.release(cash, _h(10));

        uint32 ltvBps = _expectedLtv(loanId, 6_900_000 * UNIT);
        uint256 count = _enter(warehouse, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 8_000));

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.MarginCall(loanId, ltvBps, 8_500, START + 7 * DAY);

        _approve(count);
        assertEq(_marginCallAt(loanId), START);
        assertEq(securityRegistry.record(warehouse).flaggedBy, count);
    }

    function test_acceptingAFlagUpdatesTheReference() public {
        uint256 loanId = _loanWithTerms();
        (uint256 recordId, uint256 inspectionId) = _flaggedRecord(loanId, 9_000);
        assertEq(securityRegistry.collateralValue(loanId), 7_200_000 * UNIT);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.FlagResolved(
            loanId, recordId, inspectionId, ISecurityRegistry.FlagOutcome.Accepted, _h(19)
        );

        _resolveFlag(recordId, ISecurityRegistry.FlagOutcome.Accepted);

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertEq(recordData.flaggedBy, 0);
        assertEq(recordData.referenceQuantity, 900 * UNIT);
        assertEq(recordData.referenceGrade, 99_990_000);
        assertEq(securityRegistry.collateralValue(loanId), 7_200_000 * UNIT);

        uint256 next = _inspect(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_000));
        assertEq(securityRecordNft.inspection(next).varianceReferenceBps, 0);
        assertEq(securityRegistry.record(recordId).flaggedBy, 0);

        vm.prank(securityRiskCouncil);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNotFlagged.selector);
        securityRegistry.resolveFlag(recordId, ISecurityRegistry.FlagOutcome.Accepted, _h(19));
    }

    function test_acceptingAnAssayUpdatesTheGradeOnly() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _active(loanId, _bl(10_000));
        _inspect(recordId, _assay(98_000_000));

        _resolveFlag(recordId, ISecurityRegistry.FlagOutcome.Accepted);

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertEq(recordData.referenceGrade, 98_000_000);
        assertEq(recordData.referenceQuantity, 1_000 * UNIT);
        assertEq(recordData.flaggedBy, 0);
    }

    function test_aCountOfNothingCantBeAccepted() public {
        uint256 loanId = _loanWithTerms();
        (uint256 recordId,) = _flaggedRecord(loanId, 0);

        vm.prank(securityRiskCouncil);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryInvalidQuantity.selector);
        securityRegistry.resolveFlag(recordId, ISecurityRegistry.FlagOutcome.Accepted, _h(19));

        _resolveFlag(recordId, ISecurityRegistry.FlagOutcome.Escalated);
        assertNotEq(securityRegistry.record(recordId).flaggedBy, 0);
    }

    function test_topUpRequiredOpensAMarginCallAboveTheAdvanceRatio() public {
        uint256 loanId = _loanWithTerms();
        (uint256 recordId, uint256 inspectionId) = _flaggedRecord(loanId, 9_000);
        assertEq(_marginCallAt(loanId), 0);

        vm.warp(START + 3 * DAY);
        uint32 ltvBps = _expectedLtv(loanId, 7_200_000 * UNIT);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.MarginCall(loanId, ltvBps, 8_500, START + 10 * DAY);
        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.FlagResolved(
            loanId, recordId, inspectionId, ISecurityRegistry.FlagOutcome.TopUpRequired, _h(19)
        );

        _resolveFlag(recordId, ISecurityRegistry.FlagOutcome.TopUpRequired);
        assertEq(_marginCallAt(loanId), START + 3 * DAY);

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertEq(recordData.flaggedBy, 0);
        assertEq(recordData.referenceQuantity, 1_000 * UNIT);
    }

    function test_topUpRequiredOpensNothingAtOrBelowTheAdvanceRatio() public {
        uint256 loanId = _loanWithTerms();
        (uint256 recordId,) = _flaggedRecord(loanId, 9_900);

        _resolveFlag(recordId, ISecurityRegistry.FlagOutcome.TopUpRequired);
        assertEq(_marginCallAt(loanId), 0);
        assertEq(securityRegistry.record(recordId).flaggedBy, 0);
    }

    function test_topUpRequiredKeepsAnOpenMarginCall() public {
        uint256 loanId = _loanWithTerms();
        (uint256 recordId,) = _flaggedRecord(loanId, 8_000);
        assertEq(_marginCallAt(loanId), START);

        vm.warp(START + DAY);
        _resolveFlag(recordId, ISecurityRegistry.FlagOutcome.TopUpRequired);
        assertEq(_marginCallAt(loanId), START);
    }

    function test_topUpRequiredDoesntWaitForAFreshPrice() public {
        uint256 loanId = _loanWithTerms();
        (uint256 recordId,) = _flaggedRecord(loanId, 9_000);

        vm.warp(START + 3 * DAY);
        assertTrue(securityRegistryReader.coverageDetail(loanId).priceStale);

        _resolveFlag(recordId, ISecurityRegistry.FlagOutcome.TopUpRequired);
        assertEq(_marginCallAt(loanId), START + 3 * DAY);
    }

    function test_escalatingKeepsTheFlag() public {
        uint256 loanId = _loanWithTerms();
        (uint256 recordId, uint256 inspectionId) = _flaggedRecord(loanId, 9_000);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.FlagResolved(
            loanId, recordId, inspectionId, ISecurityRegistry.FlagOutcome.Escalated, _h(19)
        );

        _resolveFlag(recordId, ISecurityRegistry.FlagOutcome.Escalated);

        ISecurityRegistry.Record memory recordData = securityRegistry.record(recordId);
        assertEq(recordData.flaggedBy, inspectionId);
        assertEq(recordData.referenceQuantity, 1_000 * UNIT);
    }

    function test_resolveFlagNeedsAnExistingRecord() public {
        vm.prank(securityRiskCouncil);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNonExistentRecord.selector);
        securityRegistry.resolveFlag(99, ISecurityRegistry.FlagOutcome.Accepted, _h(19));
    }

    function test_theInspectorPanelAppliesToNewEntries() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10));
        address[] memory panel = securityRecordNft.inspectors();
        assertEq(panel.length, 1);
        assertEq(panel[0], inspector);

        ISecurityRecordNft.NewInspection memory input = _certificate(ISecurityRecordNft.InspectionKind.StockCount, 10);
        uint256 entered = _enter(recordId, input);

        address replacement = makeAddr("replacement");
        panel[0] = replacement;

        vm.expectEmit(address(securityRecordNft));
        emit PipelineSecurityRecordNft.InspectorsSet(panel);

        vm.prank(securityRiskCouncil);
        securityRecordNft.setInspectors(panel);

        address[] memory updated = securityRecordNft.inspectors();
        assertEq(updated.length, 1);
        assertEq(updated[0], replacement);

        _expectEnterRevert(recordId, input, PipelineSecurityRecordNft.SecurityRecordNftNotInspector.selector);

        input.inspector = replacement;
        _enter(recordId, input);
        _approve(entered);
    }

    function test_extensionConsentsAreKeptPerLoan() public {
        uint256 loanId = _loanWithTerms();
        uint256 otherLoanId = _loanWithTerms();
        assertEq(securityRegistry.extensionConsents(loanId).length, 0);

        uint64 newMaturity = START + 120 * DAY;

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.ExtensionConsent(loanId, newMaturity, _h(18));

        vm.startPrank(securityTrustee);
        securityRegistry.recordExtensionConsent(loanId, newMaturity, _h(18));
        securityRegistry.recordExtensionConsent(loanId, START + 150 * DAY, _h(20));
        vm.stopPrank();

        bytes32[] memory consents = securityRegistry.extensionConsents(loanId);
        assertEq(consents.length, 2);
        assertEq(consents[0], _h(18));
        assertEq(consents[1], _h(20));
        assertEq(securityRegistry.extensionConsents(otherLoanId).length, 0);
        assertEq(loanRegistry.outstanding(loanId), SENIOR);

        vm.prank(securityTrustee);
        vm.expectRevert(LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId.selector);
        securityRegistry.recordExtensionConsent(99, newMaturity, _h(18));

        uint256 closed = _drawLoan(false);
        _closeLoan(closed);

        vm.prank(securityTrustee);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryLoanClosed.selector);
        securityRegistry.recordExtensionConsent(closed, newMaturity, _h(18));
    }

    function test_coverageDetailShowsWhatStandsBehindTheValue() public {
        uint256 loanId = _drawLoan(true);

        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNoTerms.selector);
        securityRegistryReader.coverageDetail(loanId);

        _setTerms(loanId, _copperTerms());
        assertEq(_marginCallAt(loanId), START);

        uint256 goods = _active(loanId, _bl(10_000));
        _revalue(goods, 8_000);
        uint256 cash = _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000_000));
        _active(loanId, _usdRecord(ISecurityRegistry.Protection.InsuranceLossPayee, 10_000_000));
        _register(loanId, 0, _bl(10));

        PipelineSecurityRegistryReader.CoverageDetail memory detail = securityRegistryReader.coverageDetail(loanId);
        assertEq(detail.value, 9_000_000 * UNIT);
        assertEq(detail.staleValue, 0);
        assertEq(detail.flaggedValue, 0);
        assertEq(detail.debt, SENIOR);
        assertEq(detail.coverageBps, 15_000);
        assertEq(detail.ltvBps, 6_667);
        assertEq(detail.marginCallAt, 0);
        assertEq(detail.cureBy, 0);
        assertFalse(detail.priceStale);
        assertEq(detail.coverageBps, securityRegistry.coverage(loanId));

        assertEq(detail.records.length, 2);
        assertEq(detail.records[0].recordId, goods);
        assertEq(detail.records[0].countedQuantity, 1_000 * UNIT);
        assertEq(detail.records[0].valuePerUnit, 8_000 * UNIT);
        assertEq(detail.records[0].markAt, START);
        assertFalse(detail.records[0].stale);
        assertFalse(detail.records[0].flagged);
        assertEq(detail.records[1].recordId, cash);
        assertEq(detail.records[1].countedQuantity, 1_000_000 * UNIT);
        assertEq(detail.records[1].valuePerUnit, securityRegistry.PAR_VALUE());
        assertEq(detail.records[1].markAt, START);

        uint256 count = _inspect(goods, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_000));
        assertEq(securityRegistry.record(goods).flaggedBy, count);

        detail = securityRegistryReader.coverageDetail(loanId);
        assertEq(detail.value, 8_200_000 * UNIT);
        assertEq(detail.flaggedValue, 7_200_000 * UNIT);
        assertEq(detail.staleValue, 0);
        assertEq(detail.records[0].countedQuantity, 900 * UNIT);
        assertTrue(detail.records[0].flagged);
    }

    function test_coverageDetailShowsAnOpenMarginCallAndAStalePrice() public {
        uint256 loanId = _loanWithTerms();

        PipelineSecurityRegistryReader.CoverageDetail memory detail = securityRegistryReader.coverageDetail(loanId);
        assertEq(detail.marginCallAt, START);
        assertEq(detail.cureBy, START + 7 * DAY);
        assertEq(detail.ltvBps, type(uint32).max);
        assertEq(detail.value, 0);
        assertEq(detail.records.length, 0);

        uint256 goods = _active(loanId, _bl(10_000));
        detail = securityRegistryReader.coverageDetail(loanId);
        assertTrue(detail.priceStale);
        assertEq(detail.value, 0);
        assertEq(detail.records[0].recordId, goods);
        assertEq(detail.records[0].countedQuantity, 1_000 * UNIT);
        assertEq(detail.records[0].valuePerUnit, 0);
        assertEq(detail.records[0].markAt, 0);

        _revalue(goods, 10_000);
        detail = securityRegistryReader.coverageDetail(loanId);
        assertFalse(detail.priceStale);
        assertEq(detail.marginCallAt, 0);
        assertEq(detail.cureBy, 0);

        vm.warp(START + 2 * DAY);
        assertFalse(securityRegistryReader.coverageDetail(loanId).priceStale);

        vm.warp(START + 2 * DAY + 1);
        assertTrue(securityRegistryReader.coverageDetail(loanId).priceStale);
    }

    function test_coverageDetailWithoutDebtHasMaxCoverageAndNoLtv() public {
        uint256 loanId = _drawLoan(false);
        _setTerms(loanId, _copperTerms());
        _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000));

        PipelineSecurityRegistryReader.CoverageDetail memory detail = securityRegistryReader.coverageDetail(loanId);
        assertEq(detail.debt, 0);
        assertEq(detail.coverageBps, type(uint32).max);
        assertEq(detail.ltvBps, 0);
        assertEq(detail.value, 1_000 * UNIT);
    }

    function test_recordsGoStaleWithoutAttestationOrInspection() public {
        uint256 loanId = _loanWithTerms();
        uint256 blId = _active(loanId, _bl(5_000));
        _revalue(blId, 10_000);
        uint256 warehouse = _active(loanId, _goodsRecord(ISecurityRegistry.Protection.WarehousePledge, 5_000));
        _revalue(warehouse, 10_000);
        uint256 cash = _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000));
        uint256[3] memory recordIds = [blId, warehouse, cash];
        uint256 total = 10_001_000 * UNIT;

        vm.warp(START + 7 * DAY);
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, 0);

        vm.warp(START + 7 * DAY + 1);
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, total);
        assertEq(securityRegistryReader.coverageDetail(loanId).value, total);

        _attestAll(recordIds);
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, 0);

        vm.warp(START + 14 * DAY);
        _attestAll(recordIds);
        vm.warp(START + 21 * DAY);
        _attestAll(recordIds);
        vm.warp(START + 28 * DAY);
        _attestAll(recordIds);

        vm.warp(START + 30 * DAY);
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, 0);

        vm.warp(START + 30 * DAY + 1);
        PipelineSecurityRegistryReader.CoverageDetail memory detail = securityRegistryReader.coverageDetail(loanId);
        assertEq(detail.staleValue, 5_000_000 * UNIT);
        assertFalse(detail.records[0].stale);
        assertTrue(detail.records[1].stale);
        assertFalse(detail.records[2].stale);

        uint256 count = _enter(warehouse, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 5_000));
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, 5_000_000 * UNIT);
        _approve(count);
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, 0);

        vm.warp(START + 61 * DAY + 2);
        _attestAll(recordIds);
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, 5_000_000 * UNIT);

        _inspect(warehouse, _assay(99_990_000));
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, 5_000_000 * UNIT);

        ISecurityRegistry.Terms memory terms = _copperTerms();
        terms.attestationInterval = 0;
        terms.inspectionInterval = 0;
        _setTerms(loanId, terms);

        vm.warp(START + 1_000 * DAY);
        assertEq(securityRegistryReader.coverageDetail(loanId).staleValue, 0);
    }

    function test_inspectionWritesStopWhilePaused() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _active(loanId, _bl(10_000));
        _revalue(recordId, 8_000);
        ISecurityRecordNft.NewInspection memory input =
            _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_000);
        uint256 inspectionId = _enter(recordId, input);
        uint256 flagged = _inspect(recordId, input);
        assertEq(securityRegistry.record(recordId).flaggedBy, flagged);

        address[] memory panel = new address[](1);
        panel[0] = inspector;

        vm.prank(pauser);
        securityRegistry.pause();

        vm.prank(securityInspectionOperator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRecordNft.recordInspection(recordId, input);

        vm.prank(securityInspectionSecondOperator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRecordNft.approveInspection(inspectionId);

        vm.startPrank(securityRiskCouncil);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.resolveFlag(recordId, ISecurityRegistry.FlagOutcome.Escalated, _h(19));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRecordNft.setInspectors(panel);
        vm.stopPrank();

        vm.prank(securityTrustee);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        securityRegistry.recordExtensionConsent(loanId, START, _h(18));

        assertEq(securityRecordNft.inspections(recordId).length, 2);
        assertEq(securityRegistryReader.coverageDetail(loanId).value, 7_200_000 * UNIT);
    }

    function testFuzz_onlyTheRecordNftAppliesInspections(address caller) public {
        vm.assume(caller != address(securityRecordNft));

        uint256 loanId = _loanWithTerms();
        uint256 recordId = _active(loanId, _bl(10_000));

        vm.prank(caller);
        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryOnlyRecordNft.selector);
        securityRegistry.applyInspection(recordId, 1, uint64(START), 1, true, true);

        assertEq(securityRegistry.record(recordId).flaggedBy, 0);
        assertEq(securityRegistry.latestInspection(securityRegistry.record(recordId).lotId).inspectionId, 0);
    }

    function test_writesOnTheNftRecheckCoverage() public {
        uint256 loanId = _loanWithTerms();
        uint256 recordId = _register(loanId, 0, _bl(10));
        assertEq(_marginCallAt(loanId), START);

        _repayAll(loanId);
        assertEq(_marginCallAt(loanId), START);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.MarginCallCured(loanId, 0);

        vm.prank(securityAgent);
        securityRecordNft.addDoc(recordId, ISecurityRecordNft.DocKind.Other, _h(1));
        assertEq(_marginCallAt(loanId), 0);

        uint256 otherLoanId = _loanWithTerms();
        uint256 otherRecordId = _register(otherLoanId, 0, _bl(10));
        _repayAll(otherLoanId);

        vm.expectEmit(address(securityRegistry));
        emit SecurityRegistryUpgradeable.MarginCallCured(otherLoanId, 0);

        _enter(otherRecordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 10));
        assertEq(_marginCallAt(otherLoanId), 0);
    }

    function test_recordDetailsOutliveTheNft() public {
        uint256 loanId = _loanWithTerms();
        ISecurityRegistry.NewRecord memory input = _bl(10);
        uint256 recordId = _register(loanId, 0, input);
        _release(recordId);
        _assertBurned(recordId);

        assertEq(abi.encode(securityRecordNft.details(recordId)), abi.encode(input.details));

        vm.prank(securityAgent);
        securityRecordNft.addDoc(recordId, ISecurityRecordNft.DocKind.Other, _h(1));
        assertEq(securityRecordNft.details(recordId).docs.length, 2);

        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNonExistentRecord.selector);
        securityRecordNft.details(99);
    }

    function test_theReaderAgreesWithTheRegistry() public {
        uint256 loanId = _loanWithTerms();
        ISecurityRegistry.NewRecord memory input = _bl(10_000);
        uint256 goods = _active(loanId, input);
        _revalue(goods, 8_000);
        _active(loanId, _usdRecord(ISecurityRegistry.Protection.CashCover, 1_000_000));
        _active(loanId, _usdRecord(ISecurityRegistry.Protection.InsuranceLossPayee, 10_000_000));
        _inspect(goods, _certificate(ISecurityRecordNft.InspectionKind.StockCount, 9_500));

        assertEq(address(securityRegistryReader.securityRegistry()), address(securityRegistry));
        assertEq(address(securityRegistryReader.recordNft()), address(securityRecordNft));

        PipelineSecurityRegistryReader.RecordView memory recordView = securityRegistryReader.record(goods);
        assertEq(abi.encode(recordView.record), abi.encode(securityRegistry.record(goods)));
        assertEq(abi.encode(recordView.details), abi.encode(securityRecordNft.details(goods)));

        PipelineSecurityRegistryReader.CoverageDetail memory detail = securityRegistryReader.coverageDetail(loanId);
        assertEq(detail.value, securityRegistry.collateralValue(loanId));
        assertEq(detail.coverageBps, securityRegistry.coverage(loanId));
        assertEq(detail.ltvBps, _expectedLtv(loanId, detail.value));
        assertEq(detail.records[0].countedQuantity, 950 * UNIT);

        vm.expectRevert(SecurityRegistryUpgradeable.SecurityRegistryNonExistentRecord.selector);
        securityRegistryReader.record(99);
    }

    function _drawLoan(bool disburse) private returns (uint256 loanId) {
        ILoanRegistry.ImmutableLoanData memory economics = ILoanRegistry.ImmutableLoanData({
            borrowerRef: bytes32(uint256(1)),
            originalFacilitySize: 10_000_000 * UNIT,
            originalSeniorTranche: SENIOR,
            originalEquityTranche: 4_000_000 * UNIT,
            originalOfftakerPrice: 10_500_000 * UNIT,
            seniorInterestRate: 120_000,
            originationDate: START,
            originalMaturityDate: START + 90 * DAY
        });

        vm.prank(loanRegistryManager);
        loanId = loanRegistry.drawLoan("metadataURI", economics);

        if (disburse) {
            vm.prank(address(minter));
            loanRegistry.disburse(loanId, SENIOR);
        }
    }

    function _loanWithTerms() private returns (uint256 loanId) {
        loanId = _drawLoan(true);
        _setTerms(loanId, _copperTerms());
    }

    function _copperTerms() private pure returns (ISecurityRegistry.Terms memory) {
        return ISecurityRegistry.Terms({
            advanceRatioBps: 8_000,
            marginCallRatioBps: 8_500,
            curePeriod: 7 * DAY,
            priceStaleAfter: 2 * DAY,
            paymentTerm: ISecurityRegistry.PaymentTerm.OpenAccount,
            gracePeriod: 10 * DAY,
            defaultRate: 180_000,
            attestationInterval: 7 * DAY,
            inspectionInterval: 30 * DAY,
            toleranceBps: 50,
            gradeToleranceBps: 100,
            marginCallAt: 0
        });
    }

    function _goodsRecord(ISecurityRegistry.Protection protection, uint256 tenths)
        private
        pure
        returns (ISecurityRegistry.NewRecord memory newRecord)
    {
        newRecord.protection = protection;
        newRecord.unit = ISecurityRegistry.Unit.Mt;
        newRecord.referenceQuantity = tenths * UNIT / 10;
        newRecord.referenceGrade = 99_990_000;
        newRecord.details.perfection = ISecurityRecordNft.Perfection.Endorsement;
        newRecord.details.commodity = "Copper cathodes";
        newRecord.details.region = "Indonesia";
        newRecord.details.siteHash = _h(6);
        newRecord.details.releaseCondition = _h(7);
        newRecord.details.control =
            ISecurityRecordNft.Control({kind: ISecurityRecordNft.ControlKind.Agent, ref: "3/3 original B/Ls"});
        newRecord.details.docs = new ISecurityRecordNft.Doc[](1);
        newRecord.details.docs[0] = ISecurityRecordNft.Doc({kind: ISecurityRecordNft.DocKind.Ebl, hash: _h(8)});
    }

    function _bl(uint256 tenths) private pure returns (ISecurityRegistry.NewRecord memory) {
        return _goodsRecord(ISecurityRegistry.Protection.EndorsedBl, tenths);
    }

    function _usdRecord(ISecurityRegistry.Protection protection, uint256 dollars)
        private
        pure
        returns (ISecurityRegistry.NewRecord memory newRecord)
    {
        newRecord.protection = protection;
        newRecord.unit = ISecurityRegistry.Unit.Usd;
        newRecord.referenceQuantity = dollars * UNIT;
        newRecord.details.perfection = ISecurityRecordNft.Perfection.NoticeAndAcknowledgment;
        newRecord.details.releaseCondition = _h(7);
        newRecord.details.control =
            ISecurityRecordNft.Control({kind: ISecurityRecordNft.ControlKind.Bank, ref: "collection account"});
    }

    function _h(uint256 n) private pure returns (bytes32) {
        return bytes32(n);
    }

    function _setTerms(uint256 loanId, ISecurityRegistry.Terms memory terms) private {
        vm.prank(securityRiskCouncil);
        securityRegistry.setTerms(loanId, terms);
    }

    function _register(uint256 loanId, uint256 lotId, ISecurityRegistry.NewRecord memory newRecord)
        private
        returns (uint256)
    {
        vm.prank(securityAgent);
        return securityRegistry.register(loanId, lotId, newRecord);
    }

    function _expectRegisterRevert(
        uint256 loanId,
        uint256 lotId,
        ISecurityRegistry.NewRecord memory newRecord,
        bytes4 selector
    ) private {
        vm.prank(securityAgent);
        vm.expectRevert(selector);
        securityRegistry.register(loanId, lotId, newRecord);
    }

    function _active(uint256 loanId, ISecurityRegistry.NewRecord memory newRecord) private returns (uint256 recordId) {
        recordId = _register(loanId, 0, newRecord);
        _perfect(recordId);
    }

    function _perfect(uint256 recordId) private {
        vm.prank(securityAgent);
        securityRegistry.perfect(recordId, _h(9));
    }

    function _handover(uint256 fromRecordId, uint256 toRecordId) private {
        vm.prank(securityAgent);
        securityRegistry.handover(fromRecordId, toRecordId, _h(12));
    }

    function _expectHandoverRevert(uint256 fromRecordId, uint256 toRecordId, bytes4 selector) private {
        vm.prank(securityAgent);
        vm.expectRevert(selector);
        securityRegistry.handover(fromRecordId, toRecordId, _h(12));
    }

    function _release(uint256 recordId) private {
        vm.prank(securityAgent);
        securityRegistry.release(recordId, _h(10));
    }

    function _releaseWithConsent(uint256 recordId) private {
        vm.prank(securityRiskCouncil);
        securityRegistry.releaseWithConsent(recordId, _h(14));
    }

    function _startEnforcement(uint256 recordId) private {
        vm.prank(securityAgent);
        securityRegistry.startEnforcement(recordId);
    }

    function _markEnforced(uint256 recordId) private {
        vm.prank(securityAgent);
        securityRegistry.markEnforced(recordId, _h(13));
    }

    function _revalue(uint256 recordId, uint256 dollars) private {
        vm.prank(securityValuer);
        securityRegistry.revalue(recordId, dollars * UNIT, LME, _h(11));
    }

    function _setDefault(uint256 loanId) private {
        vm.prank(loanRegistryManager);
        loanRegistry.setDefault(loanId);
    }

    function _closeLoan(uint256 loanId) private {
        vm.prank(loanRegistryManager);
        loanRegistry.closeLoan(loanId, ILoanRegistry.ClosureReason.Cancelled);
    }

    function _repayAll(uint256 loanId) private {
        ILoanRegistry.LoanMoney memory money = loanRegistry.loanMoney(loanId);

        ILoanRegistry.RepaymentData memory repayment;
        repayment.offtakerReceived = money.outstanding + money.accruedInterest;
        repayment.seniorPrincipalRepaid = money.outstanding;
        repayment.seniorInterest = money.accruedInterest;

        vm.prank(address(minter));
        loanRegistry.recordPayment(loanId, repayment);
    }

    function _expectedLtv(uint256 loanId, uint256 value) private view returns (uint32) {
        ILoanRegistry.LoanMoney memory money = loanRegistry.loanMoney(loanId);
        return uint32(Math.ceilDiv((money.outstanding + money.accruedInterest) * 10_000, value));
    }

    function _marginCallAt(uint256 loanId) private view returns (uint64) {
        return securityRegistry.terms(loanId).marginCallAt;
    }

    function _expectBurn(address holder, uint256 recordId) private {
        vm.expectEmit(address(securityRecordNft));
        emit IERC721.Transfer(holder, address(0), recordId);
    }

    function _assertBurned(uint256 recordId) private {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, recordId));
        securityRecordNft.ownerOf(recordId);
    }

    function _certificate(ISecurityRecordNft.InspectionKind kind, uint256 tenths)
        private
        view
        returns (ISecurityRecordNft.NewInspection memory)
    {
        return ISecurityRecordNft.NewInspection({
            inspector: inspector,
            kind: kind,
            inspectedAt: uint64(vm.getBlockTimestamp()),
            quantity: tenths * UNIT / 10,
            grade: 0,
            siteHash: _h(16),
            certificateHash: _h(17),
            region: "China",
            certificateNo: "QD-2027-0412"
        });
    }

    function _assay(uint256 grade) private view returns (ISecurityRecordNft.NewInspection memory newInspection) {
        newInspection = _certificate(ISecurityRecordNft.InspectionKind.SamplingAssay, 1);
        newInspection.grade = grade;
    }

    function _enter(uint256 recordId, ISecurityRecordNft.NewInspection memory newInspection) private returns (uint256) {
        vm.prank(securityInspectionOperator);
        return securityRecordNft.recordInspection(recordId, newInspection);
    }

    function _expectEnterRevert(
        uint256 recordId,
        ISecurityRecordNft.NewInspection memory newInspection,
        bytes4 selector
    ) private {
        vm.prank(securityInspectionOperator);
        vm.expectRevert(selector);
        securityRecordNft.recordInspection(recordId, newInspection);
    }

    function _approve(uint256 inspectionId) private {
        vm.prank(securityInspectionSecondOperator);
        securityRecordNft.approveInspection(inspectionId);
    }

    function _inspect(uint256 recordId, ISecurityRecordNft.NewInspection memory newInspection)
        private
        returns (uint256 inspectionId)
    {
        inspectionId = _enter(recordId, newInspection);
        _approve(inspectionId);
    }

    function _flaggedRecord(uint256 loanId, uint256 tenths) private returns (uint256 recordId, uint256 inspectionId) {
        recordId = _active(loanId, _bl(10_000));
        _revalue(recordId, 8_000);
        inspectionId = _inspect(recordId, _certificate(ISecurityRecordNft.InspectionKind.StockCount, tenths));
    }

    function _flagsOn(uint256 loanId, uint256 tenths) private returns (bool) {
        uint256 recordId = _register(loanId, 0, _bl(10_000));
        _inspect(recordId, _certificate(ISecurityRecordNft.InspectionKind.LoadingTally, tenths));
        return securityRegistry.record(recordId).flaggedBy != 0;
    }

    function _varianceOf(uint256 loanId, uint256 referenceQuantity, uint256 found) private returns (int32) {
        ISecurityRegistry.NewRecord memory newRecord = _bl(10);
        newRecord.referenceQuantity = referenceQuantity;
        uint256 recordId = _register(loanId, 0, newRecord);

        ISecurityRecordNft.NewInspection memory newInspection =
            _certificate(ISecurityRecordNft.InspectionKind.LoadingTally, 0);
        newInspection.quantity = found;
        uint256 inspectionId = _inspect(recordId, newInspection);
        return securityRecordNft.inspection(inspectionId).varianceReferenceBps;
    }

    function _resolveFlag(uint256 recordId, ISecurityRegistry.FlagOutcome outcome) private {
        vm.prank(securityRiskCouncil);
        securityRegistry.resolveFlag(recordId, outcome, _h(19));
    }

    function _attestAll(uint256[3] memory recordIds) private {
        vm.startPrank(securityAgent);
        for (uint256 i; i < recordIds.length; ++i) {
            securityRegistry.attest(recordIds[i]);
        }
        vm.stopPrank();
    }
}
