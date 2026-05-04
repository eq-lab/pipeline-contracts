// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {DepositManagerUpgradeable} from "../../src/depositManager/DepositManagerUpgradeable.sol";
import {RateLimiterUpgradeable} from "../../src/depositManager/RateLimiterUpgradeable.sol";

contract SetupEmergencyRole is Script, Deployments {
    uint64 constant EMERGENCY_ROLE_ID = uint64(bytes8(keccak256("EMERGENCY_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = RateLimiterUpgradeable.decreaseTxLimit.selector;
        selectors[1] = RateLimiterUpgradeable.decreaseWindowLimit.selector;

        (address depositManager,) = readUpgradeable("DepositManager");
        address roleHolder = address(uint160(uint256(valueOf("EmergencyRole", false))));
        uint32 delay = uint32(uint256(valueOf("EmergencyRole__Delay", false)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(depositManager, selectors, EMERGENCY_ROLE_ID);
        accessManager.grantRole(EMERGENCY_ROLE_ID, roleHolder, delay);
        vm.stopBroadcast();
    }
}
