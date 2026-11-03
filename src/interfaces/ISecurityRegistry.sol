// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

import {ISecurityRecordNft} from "./ISecurityRecordNft.sol";

interface ISecurityRegistry {
    enum Protection {
        EndorsedBl,
        WarehousePledge,
        CollateralManagement,
        AssignedReceivable,
        LcProceeds,
        CashCover,
        Prepayment,
        InsuranceLossPayee
    }

    enum Unit {
        Dmt,
        Mt,
        Bbl,
        Usd
    }

    enum RecordStatus {
        PendingPerfection,
        Active,
        Released,
        UnderEnforcement,
        Enforced
    }

    enum PaymentTerm {
        Lc,
        Dp,
        Da,
        OpenAccount
    }

    enum FlagOutcome {
        Accepted,
        TopUpRequired,
        Escalated
    }

    struct Mark {
        uint256 valuePerUnit;
        uint64 at;
        bytes32 benchmark;
        bytes32 reportHash;
    }

    struct Record {
        uint256 recordId;
        uint256 loanId;
        uint256 lotId;
        Protection protection;
        Unit unit;
        RecordStatus status;
        bool hasMark;
        uint64 perfectedAt;
        uint64 attestedAt;
        address attestedBy;
        uint256 flaggedBy;
        uint256 referenceQuantity;
        uint256 referenceGrade;
        bytes32 commodityHash;
        Mark mark;
    }

    struct NewRecord {
        Protection protection;
        Unit unit;
        uint256 referenceQuantity;
        uint256 referenceGrade;
        ISecurityRecordNft.RecordDetails details;
    }

    struct Terms {
        uint32 advanceRatioBps;
        uint32 marginCallRatioBps;
        uint64 curePeriod;
        uint64 priceStaleAfter;
        PaymentTerm paymentTerm;
        uint64 gracePeriod;
        uint32 defaultRate;
        uint64 attestationInterval;
        uint64 inspectionInterval;
        uint32 toleranceBps;
        uint32 gradeToleranceBps;
        uint64 marginCallAt;
    }

    struct LatestInspection {
        uint256 inspectionId;
        uint64 inspectedAt;
        uint256 quantity;
    }

    struct InspectionContext {
        uint256 loanId;
        uint256 lotId;
        bool goods;
        RecordStatus status;
        uint256 referenceQuantity;
        uint256 referenceGrade;
        uint32 toleranceBps;
        uint32 gradeToleranceBps;
        bool hasLatest;
        uint256 latestQuantity;
    }

    function applyInspection(
        uint256 recordId,
        uint256 inspectionId,
        uint64 inspectedAt,
        uint256 quantity,
        bool measuresQuantity,
        bool flagged
    ) external;
    function checkCoverage(uint256 loanId) external;

    function loanRegistry() external view returns (address);
    function recordNft() external view returns (address);
    function record(uint256 recordId) external view returns (Record memory);
    function recordIds(uint256 loanId) external view returns (uint256[] memory);
    function terms(uint256 loanId) external view returns (Terms memory);
    function latestInspection(uint256 lotId) external view returns (LatestInspection memory);
    function inspectionContext(uint256 recordId) external view returns (InspectionContext memory);
}
