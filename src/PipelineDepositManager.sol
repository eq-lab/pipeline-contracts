// SPDX-License-Identifier: BUSL-1.1
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
        address _usdc,
        address _plUsd,
        uint256 minDeposit,
        RateLimitConfig calldata rateLimitConfig
    ) external initializer {
        __AccessManaged_init(authority);
        __RateLimiter_init_unchained(rateLimitConfig);
        __VerifiedRequestsQueue_init("PipelineDepositManager", "v1", verifier);
        __DepositManager_init_unchained(custodian, _usdc, _plUsd, minDeposit);
    }

    function usdc() external view returns (address) {
        return _asset();
    }

    function plUsd() external view returns (address) {
        return _share();
    }

    function _preDepositHook(uint256 amount) internal override {
        super._preDepositHook(amount);
        _applyRateLimits(amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
