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

    struct ImmutableLoanData {
        bytes32 docHash; // IPFS/S3 hash of signed facility docs
        uint256 principal; // original facility size, USDC decimals
        address originator; // counterparty that took on the loan
        address borrower; // end beneficiary (may equal originator)
        bytes32 commodity; // short code (e.g. "COCOA-2026-07")
        uint64 originatedAt; // block.timestamp at mint
    }

    struct MutableLoanData {
        LoanStatus status;
        uint32 ccrBps; // collateral coverage ratio, basis points
        bytes32 location; // warehouse/port short code or coordinates digest
        uint64 maturity; // unix timestamp; may be extended
        ClosureReason closureReason; // set only on transition → Closed
    }
}
