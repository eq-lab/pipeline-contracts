// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILoanRegistry} from "./interfaces/ILoanRegistry.sol";
import {ISecurityRecordNft} from "./interfaces/ISecurityRecordNft.sol";
import {ISecurityRegistry} from "./interfaces/ISecurityRegistry.sol";

contract PipelineSecurityRegistryReader {
    uint256 private constant PAR_VALUE = 1_000_000;
    uint256 private constant BPS_ONE = 10_000;

    struct RecordView {
        ISecurityRegistry.Record record;
        ISecurityRecordNft.RecordDetails details;
    }

    struct CountedRecord {
        uint256 recordId;
        uint256 countedQuantity;
        uint256 valuePerUnit;
        uint64 markAt;
        bool stale;
        bool flagged;
    }

    struct CoverageDetail {
        uint256 value;
        uint256 staleValue;
        uint256 flaggedValue;
        uint256 debt;
        uint32 coverageBps;
        uint32 ltvBps;
        uint64 marginCallAt;
        uint256 cureBy;
        bool priceStale;
        CountedRecord[] records;
    }

    ISecurityRegistry public immutable securityRegistry;
    ISecurityRecordNft public immutable recordNft;

    constructor(address _securityRegistry) {
        securityRegistry = ISecurityRegistry(_securityRegistry);
        recordNft = ISecurityRecordNft(ISecurityRegistry(_securityRegistry).recordNft());
    }

    function record(uint256 recordId) public view returns (RecordView memory) {
        return RecordView({record: securityRegistry.record(recordId), details: recordNft.details(recordId)});
    }

    function records(uint256 loanId) public view returns (RecordView[] memory result) {
        uint256[] memory openIds = securityRegistry.recordIds(loanId);

        result = new RecordView[](openIds.length);
        for (uint256 i; i < openIds.length; ++i) {
            result[i] = record(openIds[i]);
        }
    }

    function activeRecords(uint256 loanId) external view returns (RecordView[] memory result) {
        result = records(loanId);

        uint256 count;
        for (uint256 i; i < result.length; ++i) {
            if (result[i].record.status == ISecurityRegistry.RecordStatus.Active) result[count++] = result[i];
        }
        assembly ("memory-safe") {
            mstore(result, count)
        }
    }

    function coverageDetail(uint256 loanId) external view returns (CoverageDetail memory detail) {
        ISecurityRegistry.Terms memory loanTerms = securityRegistry.terms(loanId);
        uint256[] memory openIds = securityRegistry.recordIds(loanId);

        CountedRecord[] memory counted = new CountedRecord[](openIds.length);
        uint256 count;
        uint256 numerator;
        uint256 staleNumerator;
        uint256 flaggedNumerator;
        for (uint256 i; i < openIds.length; ++i) {
            ISecurityRegistry.Record memory recordData = securityRegistry.record(openIds[i]);
            if (!_isCounted(recordData)) continue;

            ISecurityRegistry.LatestInspection memory latest = securityRegistry.latestInspection(recordData.lotId);
            uint256 countedQuantity = _countedQuantity(recordData, latest);
            (uint256 term, bool priceStale) = _recordTerm(recordData, countedQuantity, loanTerms.priceStaleAfter);
            bool stale = _isStale(recordData, latest, loanTerms);
            bool flagged = recordData.flaggedBy != 0;

            numerator += term;
            if (stale) staleNumerator += term;
            if (flagged) flaggedNumerator += term;
            if (priceStale) detail.priceStale = true;

            counted[count++] = CountedRecord({
                recordId: recordData.recordId,
                countedQuantity: countedQuantity,
                valuePerUnit: recordData.mark.valuePerUnit,
                markAt: recordData.mark.at,
                stale: stale,
                flagged: flagged
            });
        }
        assembly ("memory-safe") {
            mstore(counted, count)
        }

        ILoanRegistry.LoanMoney memory money = ILoanRegistry(securityRegistry.loanRegistry()).loanMoney(loanId);
        uint256 debt = money.outstanding + money.accruedInterest;
        uint256 value = numerator / PAR_VALUE;
        uint64 marginCallAt = loanTerms.marginCallAt;

        detail.value = value;
        detail.staleValue = staleNumerator / PAR_VALUE;
        detail.flaggedValue = flaggedNumerator / PAR_VALUE;
        detail.debt = debt;
        detail.coverageBps = debt == 0 ? type(uint32).max : _toBps(value * BPS_ONE / debt);
        detail.ltvBps = _ltvBps(debt, value);
        detail.marginCallAt = marginCallAt;
        if (marginCallAt != 0) detail.cureBy = uint256(marginCallAt) + loanTerms.curePeriod;
        detail.records = counted;
    }

    function markAge(uint256 loanId) external view returns (uint64) {
        uint256[] memory openIds = securityRegistry.recordIds(loanId);

        bool counted;
        uint64 oldest;
        for (uint256 i; i < openIds.length; ++i) {
            ISecurityRegistry.Record memory recordData = securityRegistry.record(openIds[i]);
            if (!_isCounted(recordData) || !_isGoods(recordData.protection)) continue;
            if (!recordData.hasMark) return type(uint64).max;

            uint64 at = recordData.mark.at;
            if (!counted || at < oldest) oldest = at;
            counted = true;
        }
        return counted ? uint64(block.timestamp) - oldest : 0;
    }

    function _recordTerm(ISecurityRegistry.Record memory recordData, uint256 countedQuantity, uint64 priceStaleAfter)
        private
        view
        returns (uint256 term, bool priceStale)
    {
        if (!_isGoods(recordData.protection)) return (countedQuantity * PAR_VALUE, false);
        if (!recordData.hasMark) return (0, true);

        priceStale = priceStaleAfter != 0 && block.timestamp - recordData.mark.at > priceStaleAfter;
        term = countedQuantity * recordData.mark.valuePerUnit;
    }

    function _isStale(
        ISecurityRegistry.Record memory recordData,
        ISecurityRegistry.LatestInspection memory latest,
        ISecurityRegistry.Terms memory loanTerms
    ) private view returns (bool) {
        uint64 attestationInterval = loanTerms.attestationInterval;
        if (attestationInterval != 0 && block.timestamp - recordData.attestedAt > attestationInterval) return true;

        ISecurityRegistry.Protection protection = recordData.protection;
        uint64 inspectionInterval = loanTerms.inspectionInterval;
        if (
            inspectionInterval == 0
                || (protection != ISecurityRegistry.Protection.WarehousePledge
                    && protection != ISecurityRegistry.Protection.CollateralManagement)
        ) return false;

        uint64 checkedAt = latest.inspectionId != 0 ? latest.inspectedAt : recordData.perfectedAt;
        return block.timestamp - checkedAt > inspectionInterval;
    }

    function _countedQuantity(
        ISecurityRegistry.Record memory recordData,
        ISecurityRegistry.LatestInspection memory latest
    ) private pure returns (uint256 quantity) {
        quantity = recordData.referenceQuantity;
        if (_isGoods(recordData.protection) && latest.inspectionId != 0) {
            quantity = Math.min(quantity, latest.quantity);
        }
    }

    function _isCounted(ISecurityRegistry.Record memory recordData) private pure returns (bool) {
        return recordData.status == ISecurityRegistry.RecordStatus.Active
            && recordData.protection != ISecurityRegistry.Protection.InsuranceLossPayee;
    }

    function _isGoods(ISecurityRegistry.Protection protection) private pure returns (bool) {
        return protection <= ISecurityRegistry.Protection.CollateralManagement;
    }

    function _ltvBps(uint256 debt, uint256 value) private pure returns (uint32) {
        if (debt == 0) return 0;
        if (value == 0) return type(uint32).max;
        return _toBps(Math.ceilDiv(debt * BPS_ONE, value));
    }

    function _toBps(uint256 bps) private pure returns (uint32) {
        return uint32(Math.min(bps, type(uint32).max));
    }
}
