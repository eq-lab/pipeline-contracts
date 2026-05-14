// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {DepositManagerUpgradeable} from "./depositManager/DepositManagerUpgradeable.sol";
import {RateLimiterUpgradeable} from "./depositManager/RateLimiterUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineDepositManager is UUPSUpgradeable, RateLimiterUpgradeable, DepositManagerUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address authority,
        address verifier,
        address custodian,
        address depositedToken,
        address mintedToken,
        uint256 minDeposit,
        RateLimitConfig calldata rateLimitConfig
    ) external initializer {
        __AccessManaged_init(authority);
        __RateLimiter_init_unchained(rateLimitConfig);
        __VerifiedRequestsQueue_init("PipelineDepositManager", "v1", verifier);
        __DepositManager_init_unchained(custodian, depositedToken, mintedToken, minDeposit);
    }

    function usdc() external view returns (address) {
        return _depositedToken();
    }

    function plUsd() external view returns (address) {
        return _mintedToken();
    }

    function _preDepositHook(uint256 amount) internal override {
        super._preDepositHook(amount);
        _applyRateLimits(amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
