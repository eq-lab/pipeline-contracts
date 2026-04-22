// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {DepositManagerUpgradeable} from "./depositManager/DepositManagerUpgradeable.sol";
import {RateLimiterUpgradeable} from "./depositManager/RateLimiterUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineUSD is UUPSUpgradeable, RateLimiterUpgradeable, DepositManagerUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address authority,
        address custodian,
        address depositedToken,
        address mintedToken,
        uint256 minDeposit,
        RateLimitConfig calldata rateLimitConfig
    ) external initializer {
        __AccessManaged_init(authority);
        __DepositManager_init_unchained(custodian, depositedToken, mintedToken, minDeposit);
        __RateLimiter_init_unchained(rateLimitConfig);
    }

    function _preDepositHook(uint256 amount) internal override {
        super._preDepositHook(amount);
        _applyRateLimits(amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
