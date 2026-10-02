// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface ILoanRegistry {
    enum LoanStatus {
        Approved,
        Performing,
        WatchList,
        Default,
        Closed
    }

    enum ClosureReason {
        None,
        ScheduledMaturity,
        EarlyRepayment,
        Cancelled,
        Default,
        OtherWriteDown
    }

    struct ImmutableLoanData {
        bytes32 borrowerRef;
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
        uint64 currentMaturityTimestamp;
        uint32 currentRate;
        ClosureReason closureReason;
        bool carvedOut;
        uint256 disbursed;
        uint256 repaid;
        uint256 writtenDown;
        int256 interestAdjustment;
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

    struct LoanMoney {
        uint256 disbursed;
        uint256 repaid;
        uint256 writtenDown;
        uint256 outstanding;
        uint256 accruedInterest;
        bool carvedOut;
    }

    function drawLoan(string calldata metadataURI, ImmutableLoanData calldata economics)
        external
        returns (uint256 loanId);

    function updateMutable(uint256 loanId, LoanStatus newStatus, string calldata metadataURI) external;

    function disburse(uint256 loanId, uint256 amount) external;

    function undisburse(uint256 loanId, uint256 amount) external;

    function recordPayment(uint256 loanId, RepaymentData calldata repayment)
        external
        returns (uint256 repaymentId, bool carvedOut);

    function unrecordPayment(uint256 loanId, uint256 repaymentId) external returns (uint256 principal, uint256 interest);

    function rollover(uint256 loanId, uint32 newRate, uint64 newMaturityTimestamp) external;

    function amendEconomics(uint256 loanId, uint32 newRate, uint64 newMaturityTimestamp) external;

    function setDefault(uint256 loanId) external;

    function writeDown(uint256 loanId, uint256 amount) external;

    function adjustInterest(uint256 loanId, int256 delta, bytes32 reasonHash) external;

    function cure(uint256 loanId) external;

    function closeLoan(uint256 loanId, ClosureReason reason) external;

    function closeDefaulted(uint256 loanId, ClosureReason reason) external;

    function status(uint256 loanId) external view returns (LoanStatus);
    function outstanding(uint256 loanId) external view returns (uint256);
    function loanMoney(uint256 loanId) external view returns (LoanMoney memory);
    function outstandingTotal() external view returns (uint256);
    function unabsorbedTotal() external view returns (uint256);
    function economicsEpoch(uint256 loanId, uint256 epochId) external view returns (EconomicsEpoch memory);
}
