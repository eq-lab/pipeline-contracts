// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IWhitelist} from "./IWhitelist.sol";

contract WhitelistAccessedUpgradeable is Initializable {
    error NoAccess(address);

    /// @custom:storage-location erc7201:pipeline.storage.WhitelistAccessedUpgradeable
    struct WhitelistAccessedUpgradeableStorage {
        IWhitelist whitelist;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.WhitelistAccessedUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WhitelistAccessedUpgradeableStorageLocation =
        0x0aa2995f16453e24c759093de880b78ca381101f9c2462dd5613aa009eb34100;

    function _getWhitelistAccessedUpgradeableStorage()
        private
        pure
        returns (WhitelistAccessedUpgradeableStorage storage $)
    {
        assembly {
            $.slot := WhitelistAccessedUpgradeableStorageLocation
        }
    }

    function __WhitelistAccessUpgradeable_init(address whitelist) internal onlyInitializing {
        WhitelistAccessedUpgradeableStorage storage $ = _getWhitelistAccessedUpgradeableStorage();
        $.whitelist = IWhitelist(whitelist);
    }

    modifier onlyAllowed(address who) {
        if (!_isAllowed(who)) revert NoAccess(who);
        _;
    }

    function _isAllowed(address who) internal returns (bool) {
        WhitelistAccessedUpgradeableStorage storage $ = _getWhitelistAccessedUpgradeableStorage();
        return $.whitelist.isAllowed(who);
    }
}
