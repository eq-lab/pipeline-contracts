// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";
import {ISecurityRecordNft} from "../interfaces/ISecurityRecordNft.sol";
import {ISecurityRegistry} from "../interfaces/ISecurityRegistry.sol";

abstract contract SecurityRegistryUpgradeable is AccessManagedUpgradeable, PausableUpgradeable, ISecurityRegistry {
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public constant PAR_VALUE = 1_000_000;
    uint256 public constant BPS_ONE = 10_000;
    uint256 public constant MAX_OPEN_RECORDS_PER_LOAN = 32;
    bytes32 public constant PAR_BENCHMARK = "PAR";

    struct Lot {
        uint256 loanId;
        bool hasGoodsUnit;
        Unit goodsUnit;
    }

    event RecordRegistered(uint256 indexed loanId, uint256 indexed recordId, uint256 lotId, Protection protection);
    event RecordPerfected(uint256 indexed loanId, uint256 indexed recordId, bytes32 evidenceHash);
    event RecordHandedOver(
        uint256 indexed loanId, uint256 indexed fromRecordId, uint256 indexed toRecordId, bytes32 evidenceHash
    );
    event RecordAttested(uint256 indexed loanId, uint256 indexed recordId, address attestedBy);
    event RecordReleased(uint256 indexed loanId, uint256 indexed recordId, bytes32 reasonHash, bool byConsent);
    event MandateBreach(uint256 indexed loanId, bytes32 evidenceHash);
    event EnforcementStarted(uint256 indexed loanId, uint256 indexed recordId);
    event RecordEnforced(uint256 indexed loanId, uint256 indexed recordId, bytes32 proceedsHash);
    event TermsSet(uint256 indexed loanId, Terms terms);
    event Revalued(
        uint256 indexed loanId, uint256 indexed recordId, uint256 valuePerUnit, bytes32 benchmark, bytes32 reportHash
    );
    event MarginCall(uint256 indexed loanId, uint32 ltvBps, uint32 marginCallRatioBps, uint256 cureBy);
    event PriceStale(uint256 indexed loanId, uint32 ltvBps, uint32 marginCallRatioBps);
    event MarginCallCured(uint256 indexed loanId, uint32 ltvBps);
    event FlagResolved(
        uint256 indexed loanId, uint256 indexed recordId, uint256 inspectionId, FlagOutcome outcome, bytes32 reasonHash
    );
    event ExtensionConsent(uint256 indexed loanId, uint64 newMaturity, bytes32 consentHash);
    event LoanRegistrySet(address loanRegistry);

    error SecurityRegistryNonExistentRecord();
    error SecurityRegistryNonExistentLot();
    error SecurityRegistryTooManyRecords();
    error SecurityRegistryInvalidQuantity();
    error SecurityRegistryInvalidUnit();
    error SecurityRegistryUnitMismatch();
    error SecurityRegistryInvalidLocation();
    error SecurityRegistryInvalidCommodity();
    error SecurityRegistryLoanClosed();
    error SecurityRegistryWrongLoanStatus();
    error SecurityRegistryWrongLot();
    error SecurityRegistryWrongRecordStatus();
    error SecurityRegistryNoTerms();
    error SecurityRegistryInvalidRatio();
    error SecurityRegistryLotAlreadyCounted();
    error SecurityRegistryNotCounting();
    error SecurityRegistryFlagged();
    error SecurityRegistryLtvTooHigh();
    error SecurityRegistryNotFlagged();
    error SecurityRegistryOnlyRecordNft();
    error SecurityRegistryZeroAddress();
    error SecurityRegistrySameValue();

    /// @custom:storage-location erc7201:pipeline.storage.SecurityRegistry
    struct SecurityRegistryStorage {
        ILoanRegistry loanRegistry;
        ISecurityRecordNft recordNft;
        uint256 recordCount;
        uint256 lotCount;
        mapping(uint256 recordId => Record) records;
        mapping(uint256 lotId => Lot) lots;
        mapping(uint256 loanId => EnumerableSet.UintSet) openRecords;
        mapping(uint256 loanId => Terms) terms;
        mapping(uint256 loanId => bool) hasTerms;
        mapping(uint256 lotId => LatestInspection) latestInspections;
        mapping(uint256 loanId => bytes32[]) extensionConsents;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.SecurityRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SecurityRegistryStorageLocation =
        0xe4c932a8d46f090712464e8bf71540462c3831ff6628970c190523ba96dea900;

    function _getSecurityRegistryStorage() private pure returns (SecurityRegistryStorage storage $) {
        assembly {
            $.slot := SecurityRegistryStorageLocation
        }
    }

    function __SecurityRegistry_init_unchained(address _loanRegistry, address _recordNft) internal onlyInitializing {
        if (_recordNft == address(0)) revert SecurityRegistryZeroAddress();

        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        _setLoanRegistry($, _loanRegistry);
        $.recordNft = ISecurityRecordNft(_recordNft);
    }

    function register(uint256 loanId, uint256 lotId, NewRecord calldata newRecord)
        external
        restricted
        whenNotPaused
        returns (uint256 recordId)
    {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        _requireLoanNotClosed($, loanId);
        _loanTerms($, loanId);
        _validateNewRecord(newRecord);
        lotId = _assignLot($, loanId, lotId, newRecord);

        EnumerableSet.UintSet storage openIds = $.openRecords[loanId];
        if (openIds.length() >= MAX_OPEN_RECORDS_PER_LOAN) revert SecurityRegistryTooManyRecords();
        recordId = ++$.recordCount;
        openIds.add(recordId);

        Record storage recordData = $.records[recordId];
        recordData.recordId = recordId;
        recordData.loanId = loanId;
        recordData.lotId = lotId;
        recordData.protection = newRecord.protection;
        recordData.unit = newRecord.unit;
        recordData.referenceQuantity = newRecord.referenceQuantity;
        recordData.referenceGrade = newRecord.referenceGrade;
        recordData.commodityHash = keccak256(bytes(newRecord.details.commodity));
        if (newRecord.unit == Unit.Usd) {
            recordData.hasMark = true;
            recordData.mark =
                Mark({valuePerUnit: PAR_VALUE, at: uint64(block.timestamp), benchmark: PAR_BENCHMARK, reportHash: 0});
        }
        $.recordNft.mint(IERC721(address($.loanRegistry)).ownerOf(loanId), recordId, newRecord.details);

        emit RecordRegistered(loanId, recordId, lotId, newRecord.protection);
        _updateMarginCall($, loanId);
    }

    function perfect(uint256 recordId, bytes32 evidenceHash) external restricted whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);
        _requireStatus(recordData, RecordStatus.PendingPerfection);
        if (_counts(recordData.protection) && _lotCounted($, recordData.loanId, recordData.lotId)) {
            revert SecurityRegistryLotAlreadyCounted();
        }
        _activate($, recordData, evidenceHash);

        emit RecordPerfected(recordData.loanId, recordId, evidenceHash);
        _updateMarginCall($, recordData.loanId);
    }

    function handover(uint256 fromRecordId, uint256 toRecordId, bytes32 evidenceHash)
        external
        restricted
        whenNotPaused
    {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage from = _existingRecord($, fromRecordId);
        Record storage to = _existingRecord($, toRecordId);
        uint256 loanId = from.loanId;
        if (to.loanId != loanId || to.lotId != from.lotId) revert SecurityRegistryWrongLot();
        _requireStatus(from, RecordStatus.Active);
        _requireStatus(to, RecordStatus.PendingPerfection);
        if (!_counts(from.protection) || !_counts(to.protection)) revert SecurityRegistryNotCounting();
        if (from.flaggedBy != 0) revert SecurityRegistryFlagged();

        if (to.unit == from.unit && to.commodityHash == from.commodityHash) {
            to.hasMark = from.hasMark;
            to.mark = from.mark;
        }
        _activate($, to, evidenceHash);
        _close($, from, RecordStatus.Released);

        emit RecordHandedOver(loanId, fromRecordId, toRecordId, evidenceHash);
        _updateMarginCall($, loanId);
    }

    function attest(uint256 recordId) external restricted whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);
        _requireStatus(recordData, RecordStatus.Active);

        recordData.attestedBy = msg.sender;
        recordData.attestedAt = uint64(block.timestamp);

        emit RecordAttested(recordData.loanId, recordId, msg.sender);
        _updateMarginCall($, recordData.loanId);
    }

    function release(uint256 recordId, bytes32 reasonHash) external restricted whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);
        _requireOpen(recordData);
        _requireReleasable($, recordData);
        _release($, recordData, reasonHash, false);
    }

    function reportMandateBreach(uint256 loanId, bytes32 evidenceHash) external restricted whenNotPaused {
        _requireLoanNotClosed(_getSecurityRegistryStorage(), loanId);
        emit MandateBreach(loanId, evidenceHash);
    }

    function startEnforcement(uint256 recordId) external restricted whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);
        _requireStatus(recordData, RecordStatus.Active);
        if (_loanStatus($, recordData.loanId) != ILoanRegistry.LoanStatus.Default) {
            revert SecurityRegistryWrongLoanStatus();
        }

        recordData.status = RecordStatus.UnderEnforcement;

        emit EnforcementStarted(recordData.loanId, recordId);
        _updateMarginCall($, recordData.loanId);
    }

    function markEnforced(uint256 recordId, bytes32 proceedsHash) external restricted whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);
        _requireStatus(recordData, RecordStatus.UnderEnforcement);

        _addEvidence($, recordId, ISecurityRecordNft.DocKind.Proceeds, proceedsHash);
        _close($, recordData, RecordStatus.Enforced);

        emit RecordEnforced(recordData.loanId, recordId, proceedsHash);
        _updateMarginCall($, recordData.loanId);
    }

    function applyInspection(
        uint256 recordId,
        uint256 inspectionId,
        uint64 inspectedAt,
        uint256 quantity,
        bool measuresQuantity,
        bool flagged
    ) external whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        if (msg.sender != address($.recordNft)) revert SecurityRegistryOnlyRecordNft();

        Record storage recordData = $.records[recordId];
        if (measuresQuantity) {
            LatestInspection storage latest = $.latestInspections[recordData.lotId];
            if (latest.inspectionId == 0 || inspectedAt >= latest.inspectedAt) {
                latest.inspectionId = inspectionId;
                latest.inspectedAt = inspectedAt;
                latest.quantity = quantity;
            }
        }
        if (flagged) recordData.flaggedBy = inspectionId;

        _updateMarginCall($, recordData.loanId);
    }

    function releaseWithConsent(uint256 recordId, bytes32 consentHash) external restricted whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);
        _requireOpen(recordData);
        _release($, recordData, consentHash, true);
    }

    function resolveFlag(uint256 recordId, FlagOutcome outcome, bytes32 reasonHash) external restricted whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);
        uint256 inspectionId = recordData.flaggedBy;
        if (inspectionId == 0) revert SecurityRegistryNotFlagged();

        uint256 loanId = recordData.loanId;
        if (outcome == FlagOutcome.Accepted) {
            _acceptInspection($, recordData, inspectionId);
            recordData.flaggedBy = 0;
        } else if (outcome == FlagOutcome.TopUpRequired) {
            recordData.flaggedBy = 0;
            _requireTopUp($, loanId);
        }

        emit FlagResolved(loanId, recordId, inspectionId, outcome, reasonHash);
        _updateMarginCall($, loanId);
    }

    function recordExtensionConsent(uint256 loanId, uint64 newMaturity, bytes32 consentHash)
        external
        restricted
        whenNotPaused
    {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        _requireLoanNotClosed($, loanId);
        $.extensionConsents[loanId].push(consentHash);

        emit ExtensionConsent(loanId, newMaturity, consentHash);
        _updateMarginCall($, loanId);
    }

    function setTerms(uint256 loanId, Terms calldata newTerms) external restricted whenNotPaused {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        _loanStatus($, loanId);
        if (newTerms.marginCallRatioBps < newTerms.advanceRatioBps) revert SecurityRegistryInvalidRatio();

        Terms storage loanTerms = $.terms[loanId];
        uint64 marginCallAt = loanTerms.marginCallAt;
        $.terms[loanId] = newTerms;
        loanTerms.marginCallAt = marginCallAt;
        $.hasTerms[loanId] = true;

        emit TermsSet(loanId, loanTerms);
        _updateMarginCall($, loanId);
    }

    function revalue(uint256 recordId, uint256 valuePerUnit, bytes32 benchmark, bytes32 reportHash)
        external
        restricted
        whenNotPaused
    {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);

        recordData.hasMark = true;
        recordData.mark = Mark({
            valuePerUnit: valuePerUnit, at: uint64(block.timestamp), benchmark: benchmark, reportHash: reportHash
        });

        emit Revalued(recordData.loanId, recordId, valuePerUnit, benchmark, reportHash);
        _updateMarginCall($, recordData.loanId);
    }

    function checkCoverage(uint256 loanId) external whenNotPaused {
        _updateMarginCall(_getSecurityRegistryStorage(), loanId);
    }

    function setLoanRegistry(address newLoanRegistry) external restricted {
        _setLoanRegistry(_getSecurityRegistryStorage(), newLoanRegistry);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function loanRegistry() external view returns (address) {
        return address(_getSecurityRegistryStorage().loanRegistry);
    }

    function recordNft() external view returns (address) {
        return address(_getSecurityRegistryStorage().recordNft);
    }

    function record(uint256 recordId) external view returns (Record memory) {
        return _existingRecord(_getSecurityRegistryStorage(), recordId);
    }

    function recordIds(uint256 loanId) external view returns (uint256[] memory) {
        return _getSecurityRegistryStorage().openRecords[loanId].values();
    }

    function terms(uint256 loanId) external view returns (Terms memory) {
        return _loanTerms(_getSecurityRegistryStorage(), loanId);
    }

    function latestInspection(uint256 lotId) external view returns (LatestInspection memory) {
        return _getSecurityRegistryStorage().latestInspections[lotId];
    }

    function inspectionContext(uint256 recordId) external view returns (InspectionContext memory) {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        Record storage recordData = _existingRecord($, recordId);
        Terms storage loanTerms = _loanTerms($, recordData.loanId);
        LatestInspection storage latest = $.latestInspections[recordData.lotId];

        return InspectionContext({
            loanId: recordData.loanId,
            lotId: recordData.lotId,
            goods: _isGoods(recordData.protection),
            status: recordData.status,
            referenceQuantity: recordData.referenceQuantity,
            referenceGrade: recordData.referenceGrade,
            toleranceBps: loanTerms.toleranceBps,
            gradeToleranceBps: loanTerms.gradeToleranceBps,
            hasLatest: latest.inspectionId != 0,
            latestQuantity: latest.quantity
        });
    }

    function extensionConsents(uint256 loanId) external view returns (bytes32[] memory) {
        return _getSecurityRegistryStorage().extensionConsents[loanId];
    }

    function collateralValue(uint256 loanId) external view returns (uint256 value) {
        (value,) = _valuation(_getSecurityRegistryStorage(), loanId, 0, 0);
    }

    function coverage(uint256 loanId) external view returns (uint32) {
        SecurityRegistryStorage storage $ = _getSecurityRegistryStorage();
        uint256 debt = _loanDebt($, loanId);
        if (debt == 0) return type(uint32).max;

        (uint256 value,) = _valuation($, loanId, 0, 0);
        return _coverageBps(debt, value);
    }

    function _setLoanRegistry(SecurityRegistryStorage storage $, address newLoanRegistry) private {
        if (newLoanRegistry == address(0)) revert SecurityRegistryZeroAddress();
        if (address($.loanRegistry) == newLoanRegistry) revert SecurityRegistrySameValue();
        $.loanRegistry = ILoanRegistry(newLoanRegistry);

        emit LoanRegistrySet(newLoanRegistry);
    }

    function _updateMarginCall(SecurityRegistryStorage storage $, uint256 loanId) private {
        if (!$.hasTerms[loanId]) return;

        Terms storage loanTerms = $.terms[loanId];
        (uint256 value, bool priceStale) = _valuation($, loanId, 0, loanTerms.priceStaleAfter);
        uint32 ltvBps = _ltvBps(_loanDebt($, loanId), value);

        if (loanTerms.marginCallAt == 0) {
            uint32 marginCallRatioBps = loanTerms.marginCallRatioBps;
            if (ltvBps <= marginCallRatioBps) return;
            if (priceStale) {
                emit PriceStale(loanId, ltvBps, marginCallRatioBps);
                return;
            }

            _openMarginCall(loanId, loanTerms, ltvBps);
        } else if (ltvBps <= loanTerms.advanceRatioBps) {
            loanTerms.marginCallAt = 0;
            emit MarginCallCured(loanId, ltvBps);
        }
    }

    function _openMarginCall(uint256 loanId, Terms storage loanTerms, uint32 ltvBps) private {
        loanTerms.marginCallAt = uint64(block.timestamp);
        emit MarginCall(loanId, ltvBps, loanTerms.marginCallRatioBps, block.timestamp + loanTerms.curePeriod);
    }

    function _requireTopUp(SecurityRegistryStorage storage $, uint256 loanId) private {
        Terms storage loanTerms = _loanTerms($, loanId);
        (uint256 value,) = _valuation($, loanId, 0, 0);
        uint32 ltvBps = _ltvBps(_loanDebt($, loanId), value);
        if (loanTerms.marginCallAt == 0 && ltvBps > loanTerms.advanceRatioBps) {
            _openMarginCall(loanId, loanTerms, ltvBps);
        }
    }

    function _acceptInspection(SecurityRegistryStorage storage $, Record storage recordData, uint256 inspectionId)
        private
    {
        (bool measuresQuantity, uint256 quantity, uint256 grade) = $.recordNft.measured(inspectionId);
        if (measuresQuantity) {
            if (quantity == 0) revert SecurityRegistryInvalidQuantity();
            recordData.referenceQuantity = quantity;
        }
        if (grade != 0) recordData.referenceGrade = grade;
    }

    function _valuation(
        SecurityRegistryStorage storage $,
        uint256 loanId,
        uint256 excludedRecordId,
        uint64 priceStaleAfter
    ) private view returns (uint256 value, bool priceStale) {
        EnumerableSet.UintSet storage openIds = $.openRecords[loanId];
        uint256 length = openIds.length();

        uint256 numerator;
        for (uint256 i; i < length; ++i) {
            uint256 recordId = openIds.at(i);
            Record storage recordData = $.records[recordId];
            if (recordId == excludedRecordId || !_isCounted(recordData)) continue;

            (uint256 term, bool recordPriceStale) =
                _recordTerm(recordData, _countedQuantity($, recordData), priceStaleAfter);
            numerator += term;
            if (recordPriceStale) priceStale = true;
        }
        value = numerator / PAR_VALUE;
    }

    function _recordTerm(Record storage recordData, uint256 countedQuantity, uint64 priceStaleAfter)
        private
        view
        returns (uint256 term, bool priceStale)
    {
        if (!_isGoods(recordData.protection)) return (countedQuantity * PAR_VALUE, false);
        if (!recordData.hasMark) return (0, true);

        priceStale = priceStaleAfter != 0 && block.timestamp - recordData.mark.at > priceStaleAfter;
        term = countedQuantity * recordData.mark.valuePerUnit;
    }

    function _countedQuantity(SecurityRegistryStorage storage $, Record storage recordData)
        private
        view
        returns (uint256 quantity)
    {
        quantity = recordData.referenceQuantity;
        if (!_isGoods(recordData.protection)) return quantity;

        LatestInspection storage latest = $.latestInspections[recordData.lotId];
        if (latest.inspectionId != 0) quantity = Math.min(quantity, latest.quantity);
    }

    function _activate(SecurityRegistryStorage storage $, Record storage recordData, bytes32 evidenceHash) private {
        _addEvidence($, recordData.recordId, ISecurityRecordNft.DocKind.Perfection, evidenceHash);
        recordData.status = RecordStatus.Active;
        recordData.perfectedAt = uint64(block.timestamp);
        recordData.attestedAt = uint64(block.timestamp);
        recordData.attestedBy = msg.sender;
    }

    function _addEvidence(
        SecurityRegistryStorage storage $,
        uint256 recordId,
        ISecurityRecordNft.DocKind kind,
        bytes32 hash
    ) private {
        $.recordNft.addEvidence(recordId, kind, hash);
    }

    function _release(SecurityRegistryStorage storage $, Record storage recordData, bytes32 reasonHash, bool byConsent)
        private
    {
        _close($, recordData, RecordStatus.Released);

        emit RecordReleased(recordData.loanId, recordData.recordId, reasonHash, byConsent);
        _updateMarginCall($, recordData.loanId);
    }

    function _close(SecurityRegistryStorage storage $, Record storage recordData, RecordStatus status) private {
        recordData.status = status;
        $.openRecords[recordData.loanId].remove(recordData.recordId);
        $.recordNft.burn(recordData.recordId);
    }

    function _assignLot(SecurityRegistryStorage storage $, uint256 loanId, uint256 lotId, NewRecord calldata newRecord)
        private
        returns (uint256)
    {
        Lot storage lotData;
        if (lotId == 0) {
            lotId = ++$.lotCount;
            lotData = $.lots[lotId];
            lotData.loanId = loanId;
        } else {
            if (lotId > $.lotCount) revert SecurityRegistryNonExistentLot();
            lotData = $.lots[lotId];
            if (lotData.loanId != loanId) revert SecurityRegistryWrongLot();
        }

        if (_isGoods(newRecord.protection)) {
            if (!lotData.hasGoodsUnit) {
                lotData.hasGoodsUnit = true;
                lotData.goodsUnit = newRecord.unit;
            } else if (lotData.goodsUnit != newRecord.unit) {
                revert SecurityRegistryUnitMismatch();
            }
        }
        return lotId;
    }

    function _requireReleasable(SecurityRegistryStorage storage $, Record storage recordData) private view {
        if (
            recordData.status == RecordStatus.PendingPerfection
                || recordData.protection == Protection.InsuranceLossPayee
        ) return;

        uint256 loanId = recordData.loanId;
        ILoanRegistry.LoanMoney memory money = _loanMoney($, loanId);
        if (money.outstanding == 0) return;

        uint32 advanceRatioBps = _loanTerms($, loanId).advanceRatioBps;
        (uint256 value,) = _valuation($, loanId, recordData.recordId, 0);
        if (_ltvBps(money.outstanding + money.accruedInterest, value) > advanceRatioBps) {
            revert SecurityRegistryLtvTooHigh();
        }
    }

    function _lotCounted(SecurityRegistryStorage storage $, uint256 loanId, uint256 lotId) private view returns (bool) {
        EnumerableSet.UintSet storage openIds = $.openRecords[loanId];
        uint256 length = openIds.length();
        for (uint256 i; i < length; ++i) {
            Record storage recordData = $.records[openIds.at(i)];
            if (recordData.lotId == lotId && _isCounted(recordData)) return true;
        }
        return false;
    }

    function _requireLoanNotClosed(SecurityRegistryStorage storage $, uint256 loanId) private view {
        if (_loanStatus($, loanId) == ILoanRegistry.LoanStatus.Closed) revert SecurityRegistryLoanClosed();
    }

    function _loanStatus(SecurityRegistryStorage storage $, uint256 loanId)
        private
        view
        returns (ILoanRegistry.LoanStatus)
    {
        return $.loanRegistry.status(loanId);
    }

    function _loanMoney(SecurityRegistryStorage storage $, uint256 loanId)
        private
        view
        returns (ILoanRegistry.LoanMoney memory)
    {
        return $.loanRegistry.loanMoney(loanId);
    }

    function _loanDebt(SecurityRegistryStorage storage $, uint256 loanId) private view returns (uint256) {
        ILoanRegistry.LoanMoney memory money = _loanMoney($, loanId);
        return money.outstanding + money.accruedInterest;
    }

    function _loanTerms(SecurityRegistryStorage storage $, uint256 loanId) private view returns (Terms storage) {
        if (!$.hasTerms[loanId]) revert SecurityRegistryNoTerms();
        return $.terms[loanId];
    }

    function _existingRecord(SecurityRegistryStorage storage $, uint256 recordId)
        private
        view
        returns (Record storage)
    {
        if (recordId == 0 || recordId > $.recordCount) {
            revert SecurityRegistryNonExistentRecord();
        }
        return $.records[recordId];
    }

    function _requireOpen(Record storage recordData) private view {
        RecordStatus status = recordData.status;
        if (status == RecordStatus.Released || status == RecordStatus.Enforced) {
            revert SecurityRegistryWrongRecordStatus();
        }
    }

    function _requireStatus(Record storage recordData, RecordStatus status) private view {
        if (recordData.status != status) revert SecurityRegistryWrongRecordStatus();
    }

    function _isCounted(Record storage recordData) private view returns (bool) {
        return recordData.status == RecordStatus.Active && _counts(recordData.protection);
    }

    function _validateNewRecord(NewRecord calldata newRecord) private pure {
        bool goods = _isGoods(newRecord.protection);
        if (newRecord.referenceQuantity == 0) revert SecurityRegistryInvalidQuantity();
        if (goods == (newRecord.unit == Unit.Usd)) revert SecurityRegistryInvalidUnit();
        if (!goods) {
            if (bytes(newRecord.details.region).length != 0 || newRecord.details.siteHash != 0) {
                revert SecurityRegistryInvalidLocation();
            }
            if (bytes(newRecord.details.commodity).length != 0) revert SecurityRegistryInvalidCommodity();
        }
    }

    function _ltvBps(uint256 debt, uint256 value) private pure returns (uint32) {
        if (debt == 0) return 0;
        if (value == 0) return type(uint32).max;
        return _toBps(Math.ceilDiv(debt * BPS_ONE, value));
    }

    function _coverageBps(uint256 debt, uint256 value) private pure returns (uint32) {
        return _toBps(value * BPS_ONE / debt);
    }

    function _toBps(uint256 bps) private pure returns (uint32) {
        return uint32(Math.min(bps, type(uint32).max));
    }

    function _isGoods(Protection protection) private pure returns (bool) {
        return protection <= Protection.CollateralManagement;
    }

    function _counts(Protection protection) private pure returns (bool) {
        return protection != Protection.InsuranceLossPayee;
    }
}
