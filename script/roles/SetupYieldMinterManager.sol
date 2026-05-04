// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {PipelineYieldMinterV1} from "../../src/PipelineYieldMinterV1.sol";

contract SetupYieldMinterManager is Script, Deployments {
    uint64 constant YIELD_MINTER_MANAGER_ROLE_ID = uint64(bytes8(keccak256("YIELD_MINTER_MANAGER_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PipelineYieldMinterV1.mintYield.selector;

        address yieldMinter = readPlain("PipelineYieldMinterV1");
        address roleHolder = address(uint160(uint256(valueOf("YieldMinterManager", false))));
        uint32 delay = uint32(uint256(valueOf("YieldMinterManager__Delay", false)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(yieldMinter, selectors, YIELD_MINTER_MANAGER_ROLE_ID);
        accessManager.grantRole(YIELD_MINTER_MANAGER_ROLE_ID, roleHolder, delay);
        vm.stopBroadcast();
    }
}
