// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "./base/Deployments.sol";

import {SetupMinters} from "./roles/SetupMinters.sol";
import {SetupBurners} from "./roles/SetupBurners.sol";

import {SetupDepositManagerAdmin} from "./roles/SetupDepositManagerAdmin.sol";
import {SetupEmergencyRole} from "./roles/SetupEmergencyRole.sol";
import {SetupLoanRegistryManager} from "./roles/SetupLoanRegistryManager.sol";
import {SetupWhitelistManagerRole} from "./roles/SetupWhitelistManagerRole.sol";
import {SetupYieldMinterManager} from "./roles/SetupYieldMinterManager.sol";

contract RoleSetup is Script, Deployments {
    function run(string memory tag) external {
        (new SetupMinters()).run(tag);
        (new SetupBurners()).run(tag);

        (new SetupDepositManagerAdmin()).run(tag);
        (new SetupEmergencyRole()).run(tag);
        (new SetupLoanRegistryManager()).run(tag);
        (new SetupWhitelistManagerRole()).run(tag);
        (new SetupYieldMinterManager()).run(tag);
    }
}
