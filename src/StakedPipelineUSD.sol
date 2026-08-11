// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract StakedPipelineUSD is UUPSUpgradeable, ERC4626Upgradeable, AccessManagedUpgradeable, PausableUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 asset, address authority) external initializer {
        __ERC20_init("Staked Pipeline USD", "sPLUSD");
        __ERC4626_init(asset);
        __AccessManaged_init(authority);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256 shares) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256 assets) {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256 shares)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256 assets)
    {
        return super.redeem(shares, receiver, owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
