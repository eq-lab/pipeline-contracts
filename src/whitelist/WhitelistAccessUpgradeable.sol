// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {IWhitelist} from "./IWhitelist.sol";

contract WhitelistAccessUpgradeable is IWhitelist, AccessManagedUpgradeable {
    /// @custom:storage-location erc7201:pipeline.storage.WhitelistAccess
    struct WhitelistAccessStorage {
        mapping(address user => uint256) allowedUntil;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.WhitelistAccess")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WhitelistAccessStorageLocation =
        0x182bd4f5522b4dbbdfc5c8885008e977922ca853b80736b1dc36a62345b0ae00;

    function _getWhitelistAccessStorage() private pure returns (WhitelistAccessStorage storage $) {
        assembly {
            $.slot := WhitelistAccessStorageLocation
        }
    }

    event SystemAddressAllowed(address indexed systemAddress);
    event UserAllowed(address indexed user, uint256 until);
    event Disallowed(address indexed who);

    error WhitelistAccessZeroAddress();
    error WhitelistAccessAlreadyAllowed();
    error WhitelistAccessNoAllowance();

    function __WhitelistAccess_init(address authority) internal onlyInitializing {
        __AccessManaged_init(authority);
        __WhitelistAccess_init_unchained();
    }

    function __WhitelistAccess_init_unchained() internal onlyInitializing {}

    function allowSystemAddress(address systemAddress) external restricted {
        if (systemAddress == address(0)) revert WhitelistAccessZeroAddress();

        WhitelistAccessStorage storage $ = _getWhitelistAccessStorage();
        $.allowedUntil[systemAddress] = type(uint256).max;

        emit SystemAddressAllowed(systemAddress);
    }

    function allowUser(address user, uint256 until) external restricted {
        if (user == address(0)) revert WhitelistAccessZeroAddress();

        WhitelistAccessStorage storage $ = _getWhitelistAccessStorage();
        uint256 current = $.allowedUntil[user];
        if (current >= until) revert WhitelistAccessAlreadyAllowed();

        $.allowedUntil[user] = until;
        emit UserAllowed(user, until);
    }

    function disallow(address who) external restricted {
        if (!_isAllowed(who)) revert WhitelistAccessNoAllowance();

        WhitelistAccessStorage storage $ = _getWhitelistAccessStorage();
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
        WhitelistAccessStorage storage $ = _getWhitelistAccessStorage();
        return $.allowedUntil[who];
    }
}
