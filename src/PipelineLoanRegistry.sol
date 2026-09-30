// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {LoanRegistryUpgradeable} from "./loanRegistry/LoanRegistryUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineLoanRegistry is UUPSUpgradeable, AccessManagedUpgradeable, LoanRegistryUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority, string calldata erc721Name, string calldata erc721Symbol)
        external
        initializer
    {
        __AccessManaged_init(authority);
        __LoanRegistry_init(erc721Name, erc721Symbol);
    }

    function drawLoan(string calldata metadataURI, ImmutableLoanData calldata economics)
        external
        restricted
        returns (uint256 loanId)
    {
        return _drawLoan(metadataURI, economics);
    }

    function updateMutable(uint256 loanId, LoanStatus newStatus, string calldata metadataURI) external restricted {
        _updateMutable(loanId, newStatus, metadataURI);
    }

    function disburse(uint256 loanId, uint256 amount) external restricted returns (uint256 index) {
        return _disburse(loanId, amount);
    }

    function undisburse(uint256 loanId, uint256 index, uint256 amount) external restricted {
        _undisburse(loanId, index, amount);
    }

    function recordPayment(uint256 loanId, RepaymentData calldata repayment)
        external
        restricted
        returns (uint256 repaymentId)
    {
        return _recordPayment(loanId, repayment);
    }

    function unrecordPayment(uint256 loanId, uint256 repaymentId) external restricted returns (RepaymentData memory) {
        return _unrecordPayment(loanId, repaymentId);
    }

    function rollover(uint256 loanId, uint32 newRate, uint64 newMaturityTimestamp) external restricted {
        _rollover(loanId, newRate, newMaturityTimestamp);
    }

    function amendEconomics(uint256 loanId, uint32 newRate, uint64 newMaturityTimestamp) external restricted {
        _amendEconomics(loanId, newRate, newMaturityTimestamp);
    }

    function setDefault(uint256 loanId) external restricted {
        _setDefault(loanId);
    }

    function writeDown(uint256 loanId, uint256 amount) external restricted {
        _writeDown(loanId, amount);
    }

    function adjustInterest(uint256 loanId, int256 delta, bytes32 reasonHash) external restricted {
        _adjustInterest(loanId, delta, reasonHash);
    }

    function cure(uint256 loanId) external restricted {
        _cure(loanId);
    }

    function closeLoan(uint256 loanId, ClosureReason reason) external restricted {
        _closeLoan(loanId, reason);
    }

    function closeDefaulted(uint256 loanId, ClosureReason reason) external restricted {
        _closeDefaulted(loanId, reason);
    }

    function setCapitalWallet(address newCapitalWallet) external restricted {
        _setCapitalWallet(newCapitalWallet);
    }

    function setStakedPlUsd(address newStakedPlUsd) external restricted {
        _setStakedPlUsd(newStakedPlUsd);
    }

    function setPocket(address newPocket) external restricted {
        _setPocket(newPocket);
    }

    function setMaxFeeBps(uint32 newMaxFeeBps) external restricted {
        _setMaxFeeBps(newMaxFeeBps);
    }

    function setMaxResidual(uint256 newMaxResidual) external restricted {
        _setMaxResidual(newMaxResidual);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
