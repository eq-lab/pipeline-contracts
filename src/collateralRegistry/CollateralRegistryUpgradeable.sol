// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";

abstract contract CollateralRegistryUpgradeable is AccessManagedUpgradeable, PausableUpgradeable {
    uint256 public constant PAR_VALUE = 1_000_000;
    uint256 public constant BPS_ONE = 10_000;
    uint256 public constant MAX_LOTS_PER_LOAN = 32;
    uint256 public constant MAX_DOCS_PER_LOT = 16;
    bytes32 public constant PAR_BENCHMARK = "PAR";

    enum LotKind {
        Cargo,
        Receivable
    }

    enum CargoValuationMode {
        StandardGoods,
        MetalConcentrate
    }

    enum ReceivableForm {
        OpenAccount,
        LC,
        BankGuarantee
    }

    enum Unit {
        Dmt,
        Mt,
        Bbl,
        Usd
    }

    enum LotStage {
        Pledged,
        Afloat,
        InStorage,
        Delivered,
        Sold,
        Assigned,
        Acknowledged,
        Presented,
        Paid
    }

    enum LocationType {
        Vessel,
        Warehouse,
        TankFarm,
        Other
    }

    enum ControlKind {
        None,
        EblToOrderOfTrust,
        NegotiableWr,
        Cma,
        Acknowledged
    }

    enum DocKind {
        Ebl,
        WarehouseReceipt,
        Assay,
        Insurance,
        SupplyContract,
        OfftakeContract,
        NoticeOfAssignment,
        LC,
        Inspection,
        Other
    }

    enum ReleaseReason {
        Payment,
        LCAcceptance,
        LOIDischarge,
        Substitution,
        Loss,
        ConsentedSale
    }

    struct CargoDetails {
        string commodity;
        CargoValuationMode valuationMode;
    }

    struct ReceivableDetails {
        bytes32 obligorRef;
        uint64 dueDate;
        ReceivableForm form;
    }

    struct Location {
        LocationType locationType;
        string identifier;
        string trackingUrl;
    }

    struct Control {
        ControlKind kind;
        string ref;
    }

    struct Doc {
        DocKind kind;
        bytes32 hash;
    }

    struct Mark {
        uint256 valuePerUnit;
        uint64 at;
        bytes32 benchmark;
        bytes32 reportHash;
    }

    struct Lot {
        LotKind kind;
        Unit unit;
        LotStage stage;
        uint32 haircutBps;
        bool hasLocation;
        bool hasMark;
        uint256 quantity;
        CargoDetails cargo;
        ReceivableDetails receivable;
        Location location;
        Control control;
        Mark mark;
        Doc[] docs;
    }

    struct PledgeLot {
        LotKind kind;
        Unit unit;
        uint32 haircutBps;
        bool hasLocation;
        uint256 quantity;
        CargoDetails cargo;
        ReceivableDetails receivable;
        Location location;
    }

    struct Sale {
        uint256 lotId;
        uint256 quantity;
        uint64 at;
    }

    event Pledged(uint256 indexed loanId, uint256 indexed lotId);
    event HaircutSet(uint256 indexed loanId, uint256 indexed lotId, uint32 bps);
    event FloorSet(uint256 indexed loanId, uint32 bps);
    event Revalued(
        uint256 indexed loanId, uint256 indexed lotId, uint256 valuePerUnit, bytes32 benchmark, bytes32 reportHash
    );
    event StageUpdated(
        uint256 indexed loanId, uint256 indexed lotId, LotStage stage, bool hasLocation, Location location
    );
    event ControlUpdated(uint256 indexed loanId, uint256 indexed lotId, Control control);
    event DocAdded(uint256 indexed loanId, uint256 indexed lotId, DocKind kind, bytes32 hash);
    event QuantityAdjusted(
        uint256 indexed loanId,
        uint256 indexed lotId,
        uint256 oldQuantity,
        uint256 newQuantity,
        string reason,
        bytes32 hash
    );
    event Released(
        uint256 indexed loanId, uint256 indexed lotId, uint256 quantity, ReleaseReason reason, bytes32 refHash
    );
    event Liquidated(uint256 indexed loanId, uint256 indexed lotId, uint256 saleId, uint256 quantity);
    event MarginCall(uint256 indexed loanId, uint32 coverageBps, uint32 floorBps);
    event LoanRegistrySet(address loanRegistry);

    error CollateralRegistryNonExistentLot(uint256 loanId, uint256 lotId);
    error CollateralRegistryNonExistentSale(uint256 loanId, uint256 saleId);
    error CollateralRegistryTooManyLots(uint256 loanId);
    error CollateralRegistryTooManyDocs(uint256 loanId, uint256 lotId);
    error CollateralRegistryInvalidQuantity();
    error CollateralRegistryInvalidHaircut(uint32 bps);
    error CollateralRegistryInvalidUnit(Unit unit);
    error CollateralRegistryCargoUnitMismatch(Unit expected, Unit unit);
    error CollateralRegistryInvalidLocation();
    error CollateralRegistryLoanClosed(uint256 loanId);
    error CollateralRegistryWrongLoanStatus(uint256 loanId, ILoanRegistry.LoanStatus status);
    error CollateralRegistryInvalidStage(LotStage stage);
    error CollateralRegistryInvalidControl(ControlKind kind);
    error CollateralRegistryInsufficientQuantity(uint256 quantity, uint256 available);
    error CollateralRegistryZeroAddress();
    error CollateralRegistrySameValue();

    /// @custom:storage-location erc7201:pipeline.storage.CollateralRegistry
    struct CollateralRegistryStorage {
        ILoanRegistry loanRegistry;
        mapping(uint256 loanId => uint256) nextLotId;
        mapping(uint256 loanId => uint256) salesCount;
        mapping(uint256 loanId => uint32) floorBps;
        mapping(uint256 loanId => mapping(uint256 lotId => Lot)) lots;
        mapping(uint256 loanId => mapping(uint256 saleId => Sale)) sales;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.CollateralRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CollateralRegistryStorageLocation =
        0x1e04e9b5618d7ee563f4373e9cf896f16bf87f7b57c760045c5e26e38d1aae00;

    function _getCollateralRegistryStorage() private pure returns (CollateralRegistryStorage storage $) {
        assembly {
            $.slot := CollateralRegistryStorageLocation
        }
    }

    function __CollateralRegistry_init_unchained(address _loanRegistry) internal onlyInitializing {
        _setLoanRegistry(_getCollateralRegistryStorage(), _loanRegistry);
    }

    function pledge(uint256 loanId, PledgeLot calldata pledgeLot)
        external
        restricted
        whenNotPaused
        returns (uint256 lotId)
    {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        if (_loanStatus($, loanId) == ILoanRegistry.LoanStatus.Closed) {
            revert CollateralRegistryLoanClosed(loanId);
        }

        if (pledgeLot.quantity == 0) revert CollateralRegistryInvalidQuantity();
        _requireValidHaircut(pledgeLot.haircutBps);

        Unit unit = pledgeLot.unit;
        bool isCargo = pledgeLot.kind == LotKind.Cargo;
        if (isCargo) {
            if (unit == Unit.Usd) revert CollateralRegistryInvalidUnit(unit);
            (bool found, Unit existing) = _existingCargoUnit($, loanId);
            if (found && existing != unit) revert CollateralRegistryCargoUnitMismatch(existing, unit);
        } else {
            if (unit != Unit.Usd) revert CollateralRegistryInvalidUnit(unit);
            if (pledgeLot.hasLocation) revert CollateralRegistryInvalidLocation();
        }

        lotId = $.nextLotId[loanId];
        if (lotId >= MAX_LOTS_PER_LOAN) revert CollateralRegistryTooManyLots(loanId);
        $.nextLotId[loanId] = lotId + 1;

        Lot storage lotData = $.lots[loanId][lotId];
        lotData.kind = pledgeLot.kind;
        lotData.unit = unit;
        lotData.haircutBps = pledgeLot.haircutBps;
        lotData.quantity = pledgeLot.quantity;

        if (isCargo) {
            lotData.stage = LotStage.Pledged;
            lotData.cargo = pledgeLot.cargo;
            if (pledgeLot.hasLocation) {
                lotData.hasLocation = true;
                lotData.location = pledgeLot.location;
            }
        } else {
            lotData.stage = LotStage.Assigned;
            lotData.receivable = pledgeLot.receivable;
        }

        if (unit == Unit.Usd) {
            lotData.hasMark = true;
            lotData.mark =
                Mark({valuePerUnit: PAR_VALUE, at: uint64(block.timestamp), benchmark: PAR_BENCHMARK, reportHash: 0});
        }

        emit Pledged(loanId, lotId);
        _checkCoverage($, loanId);
    }

    function setHaircut(uint256 loanId, uint256 lotId, uint32 bps) external restricted whenNotPaused {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        Lot storage lotData = _existingLot($, loanId, lotId);
        _requireValidHaircut(bps);

        lotData.haircutBps = bps;

        emit HaircutSet(loanId, lotId, bps);
        _checkCoverage($, loanId);
    }

    function setFloor(uint256 loanId, uint32 bps) external restricted whenNotPaused {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        $.floorBps[loanId] = bps;

        emit FloorSet(loanId, bps);
        _checkCoverage($, loanId);
    }

    function revalue(uint256 loanId, uint256 lotId, uint256 valuePerUnit, bytes32 benchmark, bytes32 reportHash)
        external
        restricted
        whenNotPaused
    {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        Lot storage lotData = _existingLot($, loanId, lotId);

        lotData.hasMark = true;
        lotData.mark = Mark({
            valuePerUnit: valuePerUnit, at: uint64(block.timestamp), benchmark: benchmark, reportHash: reportHash
        });

        emit Revalued(loanId, lotId, valuePerUnit, benchmark, reportHash);
        _checkCoverage($, loanId);
    }

    function setStage(uint256 loanId, uint256 lotId, LotStage stage, bool hasLocation, Location calldata location)
        external
        restricted
        whenNotPaused
    {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        Lot storage lotData = _existingLot($, loanId, lotId);

        bool fitsKind = lotData.kind == LotKind.Cargo
            ? stage == LotStage.Pledged || stage == LotStage.Afloat || stage == LotStage.InStorage
            : stage == LotStage.Assigned || stage == LotStage.Acknowledged || stage == LotStage.Presented;
        if (!fitsKind) revert CollateralRegistryInvalidStage(stage);
        if (lotData.kind == LotKind.Receivable && hasLocation) revert CollateralRegistryInvalidLocation();

        lotData.stage = stage;
        lotData.hasLocation = hasLocation;
        if (hasLocation) {
            lotData.location = location;
        } else {
            delete lotData.location;
        }

        emit StageUpdated(loanId, lotId, stage, hasLocation, location);
        _checkCoverage($, loanId);
    }

    function setControl(uint256 loanId, uint256 lotId, Control calldata control) external restricted whenNotPaused {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        Lot storage lotData = _existingLot($, loanId, lotId);

        ControlKind kind = control.kind;
        bool valid = kind == ControlKind.None
            || (lotData.kind == LotKind.Cargo
                    ? kind == ControlKind.EblToOrderOfTrust || kind == ControlKind.NegotiableWr
                    || kind == ControlKind.Cma
                    : kind == ControlKind.Acknowledged);
        if (!valid) revert CollateralRegistryInvalidControl(kind);

        lotData.control = control;
        if (kind == ControlKind.Acknowledged && lotData.stage == LotStage.Assigned) {
            lotData.stage = LotStage.Acknowledged;
        }

        emit ControlUpdated(loanId, lotId, control);
        _checkCoverage($, loanId);
    }

    function addDoc(uint256 loanId, uint256 lotId, DocKind kind, bytes32 hash) external restricted whenNotPaused {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        Lot storage lotData = _existingLot($, loanId, lotId);
        if (lotData.docs.length >= MAX_DOCS_PER_LOT) revert CollateralRegistryTooManyDocs(loanId, lotId);

        lotData.docs.push(Doc({kind: kind, hash: hash}));

        emit DocAdded(loanId, lotId, kind, hash);
        _checkCoverage($, loanId);
    }

    function adjustQuantity(uint256 loanId, uint256 lotId, uint256 newQuantity, string calldata reason, bytes32 hash)
        external
        restricted
        whenNotPaused
    {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        Lot storage lotData = _existingLot($, loanId, lotId);

        uint256 oldQuantity = lotData.quantity;
        lotData.quantity = newQuantity;

        emit QuantityAdjusted(loanId, lotId, oldQuantity, newQuantity, reason, hash);
        _checkCoverage($, loanId);
    }

    function release(uint256 loanId, uint256 lotId, uint256 quantity, ReleaseReason reason, bytes32 refHash)
        external
        restricted
        whenNotPaused
    {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        Lot storage lotData = _existingLot($, loanId, lotId);

        if (_reduceQuantity(lotData, quantity) == 0) {
            lotData.stage = lotData.kind == LotKind.Cargo ? LotStage.Delivered : LotStage.Paid;
        }

        emit Released(loanId, lotId, quantity, reason, refHash);
        _checkCoverage($, loanId);
    }

    function liquidate(uint256 loanId, uint256 lotId, uint256 quantity)
        external
        restricted
        whenNotPaused
        returns (uint256 saleId)
    {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        ILoanRegistry.LoanStatus loanStatus = _loanStatus($, loanId);
        if (loanStatus != ILoanRegistry.LoanStatus.Default) {
            revert CollateralRegistryWrongLoanStatus(loanId, loanStatus);
        }

        Lot storage lotData = _existingLot($, loanId, lotId);
        if (_reduceQuantity(lotData, quantity) == 0) {
            lotData.stage = lotData.kind == LotKind.Cargo ? LotStage.Sold : LotStage.Paid;
        }

        saleId = ++$.salesCount[loanId];
        $.sales[loanId][saleId] = Sale({lotId: lotId, quantity: quantity, at: uint64(block.timestamp)});

        emit Liquidated(loanId, lotId, saleId, quantity);
        _checkCoverage($, loanId);
    }

    function checkCoverage(uint256 loanId) external {
        _checkCoverage(_getCollateralRegistryStorage(), loanId);
    }

    function setLoanRegistry(address newLoanRegistry) external restricted {
        _setLoanRegistry(_getCollateralRegistryStorage(), newLoanRegistry);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function loanRegistry() external view returns (address) {
        return address(_getCollateralRegistryStorage().loanRegistry);
    }

    function floorBps(uint256 loanId) external view returns (uint32) {
        return _getCollateralRegistryStorage().floorBps[loanId];
    }

    function lotsCount(uint256 loanId) external view returns (uint256) {
        return _getCollateralRegistryStorage().nextLotId[loanId];
    }

    function lot(uint256 loanId, uint256 lotId) external view returns (Lot memory) {
        return _existingLot(_getCollateralRegistryStorage(), loanId, lotId);
    }

    function lots(uint256 loanId) external view returns (Lot[] memory result) {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        uint256 count = $.nextLotId[loanId];

        result = new Lot[](count);
        for (uint256 lotId; lotId < count; ++lotId) {
            result[lotId] = $.lots[loanId][lotId];
        }
    }

    function sale(uint256 loanId, uint256 saleId) external view returns (Sale memory) {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        if (saleId == 0 || saleId > $.salesCount[loanId]) revert CollateralRegistryNonExistentSale(loanId, saleId);
        return $.sales[loanId][saleId];
    }

    function cargoQuantity(uint256 loanId) external view returns (uint256 total) {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        uint256 count = $.nextLotId[loanId];

        for (uint256 lotId; lotId < count; ++lotId) {
            Lot storage lotData = $.lots[loanId][lotId];
            if (lotData.kind == LotKind.Cargo) total += lotData.quantity;
        }
    }

    function collateralValue(uint256 loanId) public view returns (uint256) {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        uint256 count = $.nextLotId[loanId];

        uint256 numerator;
        for (uint256 lotId; lotId < count; ++lotId) {
            Lot storage lotData = $.lots[loanId][lotId];
            if (lotData.control.kind == ControlKind.None || !lotData.hasMark) continue;
            numerator += lotData.quantity * lotData.mark.valuePerUnit * (BPS_ONE - lotData.haircutBps);
        }
        return numerator / (BPS_ONE * PAR_VALUE);
    }

    function coverage(uint256 loanId) public view returns (uint32) {
        ILoanRegistry.LoanMoney memory money = _getCollateralRegistryStorage().loanRegistry.loanMoney(loanId);
        uint256 debt = money.outstanding + money.accruedInterest;
        if (debt == 0) return type(uint32).max;

        uint256 bps = collateralValue(loanId) * BPS_ONE / debt;
        return bps > type(uint32).max ? type(uint32).max : SafeCast.toUint32(bps);
    }

    function markAge(uint256 loanId) external view returns (uint64) {
        CollateralRegistryStorage storage $ = _getCollateralRegistryStorage();
        uint256 count = $.nextLotId[loanId];

        bool counted;
        uint64 oldest;
        for (uint256 lotId; lotId < count; ++lotId) {
            Lot storage lotData = $.lots[loanId][lotId];
            if (lotData.control.kind == ControlKind.None) continue;
            if (!lotData.hasMark) return type(uint64).max;

            uint64 at = lotData.mark.at;
            if (!counted || at < oldest) oldest = at;
            counted = true;
        }
        return counted ? uint64(block.timestamp) - oldest : 0;
    }

    function _setLoanRegistry(CollateralRegistryStorage storage $, address newLoanRegistry) private {
        if (newLoanRegistry == address(0)) revert CollateralRegistryZeroAddress();
        if (address($.loanRegistry) == newLoanRegistry) revert CollateralRegistrySameValue();
        $.loanRegistry = ILoanRegistry(newLoanRegistry);

        emit LoanRegistrySet(newLoanRegistry);
    }

    function _loanStatus(CollateralRegistryStorage storage $, uint256 loanId)
        private
        view
        returns (ILoanRegistry.LoanStatus)
    {
        return $.loanRegistry.status(loanId);
    }

    function _checkCoverage(CollateralRegistryStorage storage $, uint256 loanId) private {
        uint32 coverageBps = coverage(loanId);
        uint32 _floorBps = $.floorBps[loanId];
        if (coverageBps < _floorBps) emit MarginCall(loanId, coverageBps, _floorBps);
    }

    function _reduceQuantity(Lot storage lotData, uint256 quantity) private returns (uint256 remaining) {
        if (quantity == 0) revert CollateralRegistryInvalidQuantity();

        uint256 available = lotData.quantity;
        if (quantity > available) revert CollateralRegistryInsufficientQuantity(quantity, available);

        remaining = available - quantity;
        lotData.quantity = remaining;
    }

    function _existingCargoUnit(CollateralRegistryStorage storage $, uint256 loanId)
        private
        view
        returns (bool found, Unit unit)
    {
        uint256 count = $.nextLotId[loanId];
        for (uint256 lotId; lotId < count; ++lotId) {
            Lot storage lotData = $.lots[loanId][lotId];
            if (lotData.kind == LotKind.Cargo) return (true, lotData.unit);
        }
    }

    function _existingLot(CollateralRegistryStorage storage $, uint256 loanId, uint256 lotId)
        private
        view
        returns (Lot storage)
    {
        if (lotId >= $.nextLotId[loanId]) revert CollateralRegistryNonExistentLot(loanId, lotId);
        return $.lots[loanId][lotId];
    }

    function _requireValidHaircut(uint32 bps) private pure {
        if (bps > BPS_ONE) revert CollateralRegistryInvalidHaircut(bps);
    }
}
