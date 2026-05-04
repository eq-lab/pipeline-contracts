// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {PipelineUSD} from "../../src/PipelineUSD.sol";

contract SetupMinters is Script, Deployments {
    uint64 constant MINTER_ROLE_ID = uint64(bytes8(keccak256("MINTER_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PipelineUSD.mint.selector;

        (address pipelineUSD,) = readUpgradeable("PipelineUSD");
        (address depositManager,) = readUpgradeable("PipelineDepositManager");
        address yieldMinter = readPlain("PipelineYieldMinterV1");

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(pipelineUSD, selectors, MINTER_ROLE_ID);
        accessManager.grantRole(MINTER_ROLE_ID, yieldMinter, 0);
        accessManager.grantRole(MINTER_ROLE_ID, depositManager, 0);
        vm.stopBroadcast();
    }
}
