// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {PipelineUSD} from "../../src/PipelineUSD.sol";

contract SetupBurners is Script, Deployments {
    uint64 constant BURNER_ROLE_ID = uint64(bytes8(keccak256("BURNER_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PipelineUSD.burn.selector;

        (address pipelineUSD,) = readUpgradeable("PipelineUSD");
        (address withdrawalQueue,) = readUpgradeable("PipelineWithdrawalQueue");

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(pipelineUSD, selectors, BURNER_ROLE_ID);
        accessManager.grantRole(BURNER_ROLE_ID, withdrawalQueue, 0);
        vm.stopBroadcast();
    }
}
