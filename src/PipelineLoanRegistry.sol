// SPDX-License-Identifier: UNLICENSED
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

    function mintLoan(address to, string calldata metadataURI, uint64 initialMaturity, bytes32 location)
        external
        restricted
        returns (uint256 loanId)
    {
        return _mintLoan(to, metadataURI, initialMaturity, location);
    }

    function updateStatus(uint256 loanId, LoanStatus status) external restricted {
        _updateStatus(loanId, status);
    }

    function updateCCR(uint256 loanId, uint32 newCcrBps) external restricted {
        _updateCCR(loanId, newCcrBps);
    }

    function updateLocation(uint256 loanId, bytes32 newLocation) external restricted {
        _updateLocation(loanId, newLocation);
    }

    function recordPayment(
        uint256 loanId,
        uint256 offtakerAmount,
        uint256 seniorPrincipal,
        uint256 seniorInterest,
        uint256 equityAmount
    ) external restricted {
        _recordPayment(loanId, offtakerAmount, seniorPrincipal, seniorInterest, equityAmount);
    }

    function setDefault(uint256 loanId) external restricted {
        _setDefault(loanId);
    }

    function closeLoan(uint256 loanId, ClosureReason reason) external restricted {
        _closeLoan(loanId, reason);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
