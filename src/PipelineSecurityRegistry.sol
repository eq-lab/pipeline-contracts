// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {SecurityRegistryUpgradeable} from "./securityRegistry/SecurityRegistryUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineSecurityRegistry is UUPSUpgradeable, SecurityRegistryUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority, address loanRegistry, address recordNft) external initializer {
        __AccessManaged_init(authority);
        __SecurityRegistry_init_unchained(loanRegistry, recordNft);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
