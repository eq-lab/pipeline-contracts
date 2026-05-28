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

    function drawLoan(
        address to,
        string calldata metadataURI,
        ImmutableLoanData calldata immutableLoanData,
        uint32 initialCcrBps,
        string calldata location
    ) external restricted returns (uint256 loanId) {
        return _drawLoan(to, metadataURI, immutableLoanData, initialCcrBps, location);
    }

    function updateStatus(uint256 loanId, LoanStatus status) external restricted {
        _updateStatus(loanId, status);
    }

    function updateCCR(uint256 loanId, uint32 newCcrBps) external restricted {
        _updateCCR(loanId, newCcrBps);
    }

    function updateLocation(uint256 loanId, string calldata newLocation) external restricted {
        _updateLocation(loanId, newLocation);
    }

    function recordPayment(uint256 loanId, RepaymentData calldata repaymentData)
        external
        restricted
        returns (uint256 repaymentId)
    {
        return _recordPayment(loanId, repaymentData);
    }

    function setDefault(uint256 loanId, uint32 ccrBps) external restricted {
        _setDefault(loanId, ccrBps);
    }

    function closeLoan(uint256 loanId, ClosureReason reason) external restricted {
        _closeLoan(loanId, reason);
    }

    function markMinted(uint256 loanId, uint256 repaymentId) external restricted {
        _markMinted(loanId, repaymentId);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
