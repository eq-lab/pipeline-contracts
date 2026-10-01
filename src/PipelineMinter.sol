// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {MinterUpgradeable} from "./minter/MinterUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineMinter is UUPSUpgradeable, MinterUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address authority,
        address stakedPlUsd,
        address loanRegistry,
        address treasury,
        address factory,
        address pocket,
        address usdc,
        RateLimitConfig calldata rateLimitConfig
    ) external initializer {
        __AccessManaged_init(authority);
        __RateLimiter_init_unchained(rateLimitConfig);
        __Minter_init_unchained(stakedPlUsd, loanRegistry, treasury, factory, pocket, usdc);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
