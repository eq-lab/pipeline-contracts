// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface ILoanRegistry {
    enum LoanStatus {
        Performing,
        WatchList,
        Default,
        Closed
    }

    enum ClosureReason {
        None,
        ScheduledMaturity,
        EarlyRepayment,
        Default,
        OtherWriteDown
    }

    enum LocationType {
        Vessel,
        Warehouse,
        TankFarm,
        Other
    }

    struct ImmutableLoanData {
        uint256 originalFacilitySize;
        uint256 originalSeniorTranche;
        uint256 originalEquityTranche;
        uint256 originalOfftakerPrice;
        uint32 seniorInterestRate;
        uint64 originationDate;
        uint64 originalMaturityDate;
    }

    struct EconomicsEpoch {
        uint256 accruedInterest;
        uint64 effectiveFrom;
        uint64 maturityDate;
        uint32 seniorInterestRate;
    }

    struct MutableLoanData {
        uint256 nextEconomicsEpochsId;
        uint256 nextRepaymentId;
        LoanStatus status;
        uint32 ccr;
        uint64 lastReportedCCRTimestamp;
        uint64 currentMaturityTimestamp;
        ClosureReason closureReason;
        LocationUpdate currentLocation;
        string metadataURI;
    }

    struct RepaymentData {
        uint256 offtakerReceived;
        uint256 seniorPrincipalRepaid;
        uint256 seniorInterest;
        uint256 equityDistributed;
        uint256 mgmtFee;
        uint256 perfFee;
        uint256 oetAlloc;
    }

    struct LocationUpdate {
        LocationType locationType;
        string locationIdentifier;
        string trackingURL;
        uint64 updatedAt;
    }

    function drawLoan(
        address originator,
        string calldata metadataURI,
        ImmutableLoanData calldata economics,
        uint32 initialCcr,
        LocationUpdate calldata initialLocation
    ) external returns (uint256 loanId);

    function updateMutable(
        uint256 loanId,
        string calldata metadataURI,
        LoanStatus status,
        uint32 newCCR,
        LocationUpdate calldata newLocation
    ) external;

    function recordPayment(uint256 loanId, RepaymentData calldata repaymentUpdate)
        external
        returns (uint256 repaymentId);

    function rollover(uint256 loanId, uint32 newRate, uint64 newMaturityDate) external;

    function amendEconomics(uint256 loanId, uint32 newRate, uint64 newMaturityDate) external;

    function setDefault(uint256 loanId, uint32 ccr) external;

    function closeLoan(uint256 loanId, ClosureReason reason) external;

    function markMinted(uint256 loanId, uint256 repaymentId) external;

    function repaymentData(uint256 loanId, uint256 repaymentId) external view returns (RepaymentData memory);
    function canYieldBeMinted(uint256 loanId, uint256 repaymentId) external view returns (bool);
    function maxInterest(uint256 loanId) external view returns (uint256);
}
