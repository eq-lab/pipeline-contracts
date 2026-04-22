// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IWhitelist} from "../interfaces/IWhitelist.sol";

contract WhitelistAccessedUpgradeable is Initializable {
    error WhitelistAccessedNoAccess(address);

    /// @custom:storage-location erc7201:pipeline.storage.WhitelistAccessed
    struct WhitelistAccessedStorage {
        IWhitelist whitelist;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.WhitelistAccessed")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WhitelistAccessedStorageLocation =
        0x54a192f5411cd1027861db70d7b2d56a3f2cedbd801fe36906d589e37dee3b00;

    function _getWhitelistAccessedStorage() private pure returns (WhitelistAccessedStorage storage $) {
        assembly {
            $.slot := WhitelistAccessedStorageLocation
        }
    }

    function __WhitelistAccess_init(address whitelist) internal onlyInitializing {
        __WhitelistAccess_init_unchained(whitelist);
    }

    function __WhitelistAccess_init_unchained(address whitelist) internal onlyInitializing {
        WhitelistAccessedStorage storage $ = _getWhitelistAccessedStorage();
        $.whitelist = IWhitelist(whitelist);
    }

    modifier onlyAllowed(address who) {
        _onlyAllowed(who);
        _;
    }

    function _onlyAllowed(address who) private view {
        if (!_isAllowed(who)) revert WhitelistAccessedNoAccess(who);
    }

    function _isAllowed(address who) internal view returns (bool) {
        WhitelistAccessedStorage storage $ = _getWhitelistAccessedStorage();
        return $.whitelist.isAllowed(who);
    }
}
