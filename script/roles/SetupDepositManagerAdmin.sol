// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {DepositManagerUpgradeable} from "../../src/depositManager/DepositManagerUpgradeable.sol";
import {RateLimiterUpgradeable} from "../../src/depositManager/RateLimiterUpgradeable.sol";

contract SetupDepositManagerAdmin is Script, Deployments {
    uint64 constant DEPOSIT_MANAGER_ADMIN_ROLE_ID = uint64(bytes8(keccak256("DEPOSIT_MANAGER_ADMIN_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = DepositManagerUpgradeable.setMinDeposit.selector;
        selectors[1] = DepositManagerUpgradeable.setCustodian.selector;
        selectors[2] = RateLimiterUpgradeable.increaseTxLimit.selector;
        selectors[3] = RateLimiterUpgradeable.increaseWindowLimit.selector;

        (address depositManager,) = readUpgradeable("DepositManager");
        address roleHolder = address(uint160(uint256(valueOf("DepositManagerAdmin", false))));
        uint32 delay = uint32(uint256(valueOf("DepositManagerAdmin__Delay", false)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(depositManager, selectors, DEPOSIT_MANAGER_ADMIN_ROLE_ID);
        accessManager.grantRole(DEPOSIT_MANAGER_ADMIN_ROLE_ID, roleHolder, delay);
        vm.stopBroadcast();
    }
}
