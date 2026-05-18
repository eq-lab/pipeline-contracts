// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {WhitelistAccessUpgradeable} from "./whitelist/WhitelistAccessUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract WhitelistRegistry is UUPSUpgradeable, WhitelistAccessUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority) external initializer {
        __WhitelistAccess_init(authority);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
