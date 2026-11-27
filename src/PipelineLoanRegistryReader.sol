// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

import {ILoanRegistry} from "./interfaces/ILoanRegistry.sol";
import {LoanRegistryUpgradeable} from "./loanRegistry/LoanRegistryUpgradeable.sol";

contract PipelineLoanRegistryReader {
    using SlotDerivation for bytes32;

    uint256 private constant NEXT_LOAN_ID = 0;
    uint256 private constant MAX_RESIDUAL = 1;
    uint256 private constant OUTSTANDING_TOTAL = 2;
    uint256 private constant UNABSORBED_TOTAL = 3;
    uint256 private constant CAPITAL_WALLET = 4;
    uint256 private constant STAKED_PL_USD = 5;
    uint256 private constant POCKET = 6;
    uint256 private constant MUTABLE_LOAN_DATA = 8;
    uint256 private constant ECONOMICS_EPOCHS = 12;

    LoanRegistryUpgradeable public immutable loanRegistry;
    bytes32 private immutable _loanRegistryStorage;

    constructor(address _loanRegistry) {
        loanRegistry = LoanRegistryUpgradeable(_loanRegistry);
        _loanRegistryStorage = SlotDerivation.erc7201Slot("pipeline.storage.LoanRegistry");
    }

    function nextLoanId() external view returns (uint256) {
        return _read(_field(NEXT_LOAN_ID));
    }

    function mutableLoanData(uint256 loanId) external view returns (ILoanRegistry.MutableLoanData memory loan) {
        bytes32 slot = _existingLoan(loanId);
        uint256 word = _read(slot.offset(2));
        loan.nextEconomicsEpochsId = _read(slot);
        loan.nextRepaymentId = _read(slot.offset(1));
        loan.status = ILoanRegistry.LoanStatus(uint8(word));
        loan.currentMaturityTimestamp = uint64(word >> 8);
        loan.currentRate = uint32(word >> 72);
        loan.closureReason = ILoanRegistry.ClosureReason(uint8(word >> 104));
        loan.carvedOut = uint8(word >> 112) != 0;
        loan.disbursed = _read(slot.offset(3));
        loan.repaid = _read(slot.offset(4));
        loan.writtenDown = _read(slot.offset(5));
        loan.interestAdjustment = int256(_read(slot.offset(6)));
        loan.metadataURI = _string(slot.offset(7));
    }

    function economicsEpoch(uint256 loanId, uint256 epochId)
        external
        view
        returns (ILoanRegistry.EconomicsEpoch memory)
    {
        _existingLoan(loanId);
        bytes32 slot = _field(ECONOMICS_EPOCHS).deriveMapping(loanId).deriveMapping(epochId);
        uint256 word = _read(slot.offset(1));
        return ILoanRegistry.EconomicsEpoch({
            accruedInterest: _read(slot),
            effectiveFrom: uint64(word),
            maturityDate: uint64(word >> 64),
            seniorInterestRate: uint32(word >> 128),
            rateSeconds: uint96(word >> 160)
        });
    }

    function outstandingTotal() external view returns (uint256) {
        return _read(_field(OUTSTANDING_TOTAL));
    }

    function unabsorbedTotal() external view returns (uint256) {
        return _read(_field(UNABSORBED_TOTAL));
    }

    function capitalWallet() external view returns (address) {
        return _address(CAPITAL_WALLET);
    }

    function stakedPlUsd() external view returns (address) {
        return _address(STAKED_PL_USD);
    }

    function pocket() external view returns (address) {
        return _address(POCKET);
    }

    function maxFeeBps() external view returns (uint32) {
        return uint32(_read(_field(POCKET)) >> 160);
    }

    function maxResidual() external view returns (uint256) {
        return _read(_field(MAX_RESIDUAL));
    }

    function _existingLoan(uint256 loanId) private view returns (bytes32) {
        if (loanId >= _read(_field(NEXT_LOAN_ID))) revert LoanRegistryUpgradeable.LoanRegistryNonExistentLoanId();
        return _field(MUTABLE_LOAN_DATA).deriveMapping(loanId);
    }

    function _string(bytes32 slot) private view returns (string memory) {
        uint256 word = _read(slot);
        bool long = word & 1 != 0;
        bytes memory result = new bytes(long ? word >> 1 : (word & 0xff) >> 1);
        bytes32 data = long ? slot.deriveArray() : slot;

        bytes32 chunk;
        for (uint256 i; i < result.length; ++i) {
            if (i % 32 == 0) chunk = bytes32(_read(data.offset(i / 32)));
            result[i] = chunk[i % 32];
        }
        return string(result);
    }

    function _address(uint256 field) private view returns (address) {
        return address(uint160(_read(_field(field))));
    }

    function _field(uint256 field) private view returns (bytes32) {
        return _loanRegistryStorage.offset(field);
    }

    function _read(bytes32 slot) private view returns (uint256) {
        return uint256(loanRegistry.extsload(slot));
    }
}
