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
        Default
    }

    struct ImmutableLoanData {
        uint256 seniorTranche;
        uint256 equityTranche;
        uint256 offtakerPrice;
        uint256 rateBps;
        uint128 originationTimestamp;
        uint128 originalMaturityTimestamp;
        string facility;
    }

    struct MutableLoanData {
        uint256 nextRepaymentId;
        LoanStatus status;
        ClosureReason closureReason;
        RepaymentData repaymentData;
        uint128 currentMaturityDate;
        uint32 ccrBps;
        string location;
    }

    struct RepaymentData {
        uint256 offtakerAmount;
        uint256 equityDistributed;
        uint256 seniorPrincipalRepaid;
        uint256 seniorInterest;
        uint256 mgmtFee;
        uint256 perfFee;
        uint256 oetAlloc;
    }

    function markMinted(uint256 loanId, uint256 repaymentId) external;

    function repaymentData(uint256 loanId, uint256 repaymentId) external view returns (RepaymentData memory);

    function canYieldBeMinted(uint256 loanId, uint256 repaymentId) external view returns (bool);
}
