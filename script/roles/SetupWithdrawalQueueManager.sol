// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {WithdrawalQueueShutdownUpgradeable} from "../../src/withdrawalQueue/WithdrawalQueueShutdownUpgradeable.sol";
import {WithdrawalQueueUpgradeable} from "../../src/withdrawalQueue/WithdrawalQueueUpgradeable.sol";

contract SetupWithdrawalQueueManager is Script, Deployments {
    uint64 constant WITHDRAWAL_QUEUE_MANAGER_ROLE_ID = uint64(bytes8(keccak256("WITHDRAWAL_QUEUE_MANAGER_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = WithdrawalQueueUpgradeable.setAssetHolder.selector;
        selectors[1] = WithdrawalQueueShutdownUpgradeable.setVerifier.selector;

        (address queue,) = readUpgradeable("PipelineWithdrawalQueue");
        address roleHolder = address(uint160(uint256(valueOf("WithdrawalQueueAdmin", false))));
        uint32 delay = uint32(uint256(valueOf("WithdrawalQueueAdmin__Delay", true)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(queue, selectors, WITHDRAWAL_QUEUE_MANAGER_ROLE_ID);
        accessManager.grantRole(WITHDRAWAL_QUEUE_MANAGER_ROLE_ID, roleHolder, delay);
        vm.stopBroadcast();
    }
}
