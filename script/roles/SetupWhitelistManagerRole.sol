// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {WhitelistAccessUpgradeable} from "../../src/whitelist/WhitelistAccessUpgradeable.sol";

contract SetupWhitelistManagerRole is Script, Deployments {
    uint64 constant WHITELIST_MANAGER_ROLE_ID = uint64(bytes8(keccak256("WHITELIST_MANAGER_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = WhitelistAccessUpgradeable.allow.selector;
        selectors[1] = WhitelistAccessUpgradeable.disallow.selector;

        (address whitelistRegistry,) = readUpgradeable("WhitelistRegistry");
        address roleHolder = address(uint160(uint256(valueOf("WhitelistManager", false))));
        uint32 delay = uint32(uint256(valueOf("WhitelistManager__Delay", false)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(whitelistRegistry, selectors, WHITELIST_MANAGER_ROLE_ID);
        accessManager.grantRole(WHITELIST_MANAGER_ROLE_ID, roleHolder, delay);
        vm.stopBroadcast();
    }
}
