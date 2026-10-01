// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {PocketUpgradeable} from "./pocket/PocketUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelinePocket is UUPSUpgradeable, AccessManagedUpgradeable, PocketUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority, address stakedPlUsd) external initializer {
        __AccessManaged_init(authority);
        __Pocket_init(stakedPlUsd);
    }

    function open(uint256 loanId, uint256 amount, uint256 snapshotBlock, uint256 supplyAtSnapshot) external restricted {
        _open(loanId, amount, snapshotBlock, supplyAtSnapshot);
    }

    function release(uint256 loanId, uint256 principal, uint256 interest)
        external
        restricted
        returns (uint256 released)
    {
        return _release(loanId, principal, interest);
    }

    function unrelease(uint256 loanId, uint256 principal, uint256 interest) external restricted {
        _unrelease(loanId, principal, interest);
    }

    function burn(uint256 loanId, uint256 amount) external restricted returns (uint256 burned) {
        return _burnHeld(loanId, amount);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
