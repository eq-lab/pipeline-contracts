// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract StakedPipelineUSD is UUPSUpgradeable, ERC4626Upgradeable, AccessManagedUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 asset, address authority) external initializer {
        __ERC20_init("Staked Pipeline USD", "sPLUSD");
        __ERC4626_init(asset);
        __AccessManaged_init(authority);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
