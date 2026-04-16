// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {IWhitelist} from "./IWhitelist.sol";

contract WhitelistAccessUpgradeable is IWhitelist, AccessManagedUpgradeable {
    /// @custom:storage-location erc7201:pipeline.storage.WhitelistAccessUpgradeable
    struct WhitelistAccessUpgradeableStorage {
        mapping(address user => uint256) allowedUntil;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.WhitelistAccessUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WhitelistAccessUpgradeableStorageLocation =
        0x527bb328bffe78eea48daf21be84fa4cfdefd33b4b7b139e779d572910f8c500;

    function _getWhitelistAccessUpgradeableStorage()
        private
        pure
        returns (WhitelistAccessUpgradeableStorage storage $)
    {
        assembly {
            $.slot := WhitelistAccessUpgradeableStorageLocation
        }
    }

    event SystemAddressAllowed(address indexed systemAddress);
    event UserAllowed(address indexed user, uint256 until);
    event Disallowed(address indexed who);

    error ZeroAddress();
    error AlreadyAllowed();
    error NoAllowance();

    function __WhitelistAccessUpgradeable_init(address authority) internal onlyInitializing {
        __AccessManaged_init(authority);
    }

    function allowSystemAddress(address systemAddress) external restricted {
        if (systemAddress == address(0)) revert ZeroAddress();

        WhitelistAccessUpgradeableStorage storage $ = _getWhitelistAccessUpgradeableStorage();
        $.allowedUntil[systemAddress] = type(uint256).max;

        emit SystemAddressAllowed(systemAddress);
    }

    function allowUser(address user, uint256 until) external restricted {
        if (user == address(0)) revert ZeroAddress();

        WhitelistAccessUpgradeableStorage storage $ = _getWhitelistAccessUpgradeableStorage();
        uint256 current = $.allowedUntil[user];
        if (current >= until) revert AlreadyAllowed();

        $.allowedUntil[user] = until;
        emit UserAllowed(user, until);
    }

    function disallow(address who) external restricted {
        if (!_isAllowed(who)) revert NoAllowance();

        WhitelistAccessUpgradeableStorage storage $ = _getWhitelistAccessUpgradeableStorage();
        delete $.allowedUntil[who];

        emit Disallowed(who);
    }

    function isAllowed(address who) external view returns (bool) {
        return _isAllowed(who);
    }

    function allowedUntil(address who) external view returns (uint256) {
        return _allowedUntil(who);
    }

    function _isAllowed(address who) internal view returns (bool) {
        return _allowedUntil(who) >= block.timestamp;
    }

    function _allowedUntil(address who) internal view returns (uint256) {
        WhitelistAccessUpgradeableStorage storage $ = _getWhitelistAccessUpgradeableStorage();
        return $.allowedUntil[who];
    }
}
