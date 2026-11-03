// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface ISecurityRecordNft {
    enum ControlKind {
        Agent,
        CollateralManager,
        StockMonitor,
        Bank
    }

    enum Perfection {
        Endorsement,
        Registration,
        NoticeAndAcknowledgment
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
        LegalOpinion,
        Perfection,
        Proceeds,
        Other
    }

    enum InspectionKind {
        LoadingTally,
        DraftSurvey,
        SamplingAssay,
        DischargeSurvey,
        StockCount
    }

    struct Control {
        ControlKind kind;
        string ref;
    }

    struct Doc {
        DocKind kind;
        bytes32 hash;
    }

    struct RecordDetails {
        Perfection perfection;
        string commodity;
        string region;
        bytes32 siteHash;
        bytes32 releaseCondition;
        Control control;
        Doc[] docs;
    }

    struct Inspection {
        uint256 inspectionId;
        uint256 recordId;
        uint256 lotId;
        address inspector;
        InspectionKind kind;
        uint64 inspectedAt;
        address enteredBy;
        uint64 enteredAt;
        address approvedBy;
        uint64 approvedAt;
        int32 varianceReferenceBps;
        int32 variancePreviousBps;
        int32 varianceGradeBps;
        uint256 quantity;
        uint256 grade;
        bytes32 siteHash;
        bytes32 certificateHash;
        string region;
        string certificateNo;
    }

    struct NewInspection {
        address inspector;
        InspectionKind kind;
        uint64 inspectedAt;
        uint256 quantity;
        uint256 grade;
        bytes32 siteHash;
        bytes32 certificateHash;
        string region;
        string certificateNo;
    }

    function mint(address to, uint256 recordId, RecordDetails calldata newDetails) external;
    function burn(uint256 recordId) external;
    function addEvidence(uint256 recordId, DocKind kind, bytes32 hash) external;

    function details(uint256 recordId) external view returns (RecordDetails memory);
    function measured(uint256 inspectionId)
        external
        view
        returns (bool measuresQuantity, uint256 quantity, uint256 grade);
}
