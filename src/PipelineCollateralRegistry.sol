// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {CollateralRegistryUpgradeable} from "./collateralRegistry/CollateralRegistryUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineCollateralRegistry is UUPSUpgradeable, CollateralRegistryUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority, address loanRegistry) external initializer {
        __AccessManaged_init(authority);
        __CollateralRegistry_init_unchained(loanRegistry);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
