// SPDX-License-Identifier: UNLICENSED
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

    struct MutableLoanData {
        LoanStatus status;
        uint32 ccrBps; // collateral coverage ratio, basis points
        bytes32 location; // warehouse/port short code or coordinates digest
        uint64 maturity; // unix timestamp; may be extended
        ClosureReason closureReason; // set only on transition → Closed
    }
}
