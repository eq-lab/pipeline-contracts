// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {DealTokenFactoryUpgradeable} from "./dealTokenFactory/DealTokenFactoryUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineDealTokenFactory is UUPSUpgradeable, DealTokenFactoryUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority, address loanRegistry, address collateralRegistry) external initializer {
        __AccessManaged_init(authority);
        __DealTokenFactory_init_unchained(loanRegistry, collateralRegistry);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
