// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {WhitelistAccessedUpgradeable} from "./whitelist/WhitelistAccessedUpgradeable.sol";
import {WithdrawalQueueUpgradeable} from "./withdrawalQueue/WithdrawalQueueUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineWithdrawalQueue is
    UUPSUpgradeable,
    AccessManagedUpgradeable,
    WithdrawalQueueUpgradeable,
    WhitelistAccessedUpgradeable
{
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority, address whitelistRegistry, address fromToken, address intoToken)
        external
        initializer
    {
        __AccessManaged_init(authority);
        __WithdrawalQueue_init(fromToken, intoToken);
        __WhitelistAccessed_init(whitelistRegistry);
    }

    function claimWithdrawal(uint256 requestId)
        external
        virtual
        override
        onlyAllowed(msg.sender)
        returns (uint256 amount)
    {
        return _claimWithdrawal(requestId);
    }

    function fundWithdrawals(uint256 amount, address source)
        external
        virtual
        override
        restricted
        returns (uint256 claimable)
    {
        return super._fundWithdrawals(amount, source);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
