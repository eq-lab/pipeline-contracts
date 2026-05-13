// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {IWhitelist} from "../interfaces/IWhitelist.sol";

contract WhitelistAccessUpgradeable is IWhitelist, AccessManagedUpgradeable {
    /// @custom:storage-location erc7201:pipeline.storage.WhitelistAccess
    struct WhitelistAccessStorage {
        mapping(address user => bool) allowed;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.WhitelistAccess")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WhitelistAccessStorageLocation =
        0x182bd4f5522b4dbbdfc5c8885008e977922ca853b80736b1dc36a62345b0ae00;

    function _getWhitelistAccessStorage() private pure returns (WhitelistAccessStorage storage $) {
        assembly {
            $.slot := WhitelistAccessStorageLocation
        }
    }

    event Allowed(address indexed user);
    event Disallowed(address indexed who);

    error WhitelistAccessAlreadyAllowed();
    error WhitelistAccessNoAllowance();

    function __WhitelistAccess_init(address authority) internal onlyInitializing {
        __AccessManaged_init(authority);
        __WhitelistAccess_init_unchained();
    }

    function __WhitelistAccess_init_unchained() internal onlyInitializing {
        _allow(address(0));
    }

    function allow(address user) external restricted {
        _allow(user);
    }

    function disallow(address user) external restricted {
        if (!_isAllowed(user)) revert WhitelistAccessNoAllowance();

        WhitelistAccessStorage storage $ = _getWhitelistAccessStorage();
        delete $.allowed[user];

        emit Disallowed(user);
    }

    function isAllowed(address user) external view returns (bool) {
        return _isAllowed(user);
    }

    function _allow(address user) private {
        WhitelistAccessStorage storage $ = _getWhitelistAccessStorage();
        if ($.allowed[user]) revert WhitelistAccessAlreadyAllowed();

        $.allowed[user] = true;
        emit Allowed(user);
    }

    function _isAllowed(address who) internal view returns (bool) {
        WhitelistAccessStorage storage $ = _getWhitelistAccessStorage();
        return $.allowed[who];
    }
}
