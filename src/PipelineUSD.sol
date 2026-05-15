// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {WhitelistAccessedUpgradeable} from "./whitelist/WhitelistAccessedUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineUSD is
    UUPSUpgradeable,
    ERC20PausableUpgradeable,
    AccessManagedUpgradeable,
    WhitelistAccessedUpgradeable
{
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority, address whitelist) external initializer {
        __ERC20_init("Pipeline USD", "PLUSD");
        __AccessManaged_init(authority);
        __WhitelistAccessed_init(whitelist);
    }

    function mint(address account, uint256 value) external restricted {
        _mint(account, value);
    }

    function burn(uint256 value) external restricted {
        _burn(msg.sender, value);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function enableWhitelist() external restricted {
        _enableWhitelist();
    }

    function disableWhitelist() external restricted {
        _disableWhitelist();
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function _update(address from, address to, uint256 value)
        internal
        virtual
        override
        onlyAllowed(from)
        onlyAllowed(to)
    {
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
