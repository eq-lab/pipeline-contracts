// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {PipelineLoanRegistry} from "../../src/PipelineLoanRegistry.sol";

contract SetupLoanRegistryManager is Script, Deployments {
    uint64 constant LOAN_REGISTRY_MANAGER_ADMIN_ROLE_ID = uint64(bytes8(keccak256("LOAN_REGISTRY_MANAGER_ADMIN_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = PipelineLoanRegistry.drawLoan.selector;
        selectors[1] = PipelineLoanRegistry.updateMutable.selector;
        selectors[2] = PipelineLoanRegistry.rollover.selector;
        selectors[3] = PipelineLoanRegistry.amendEconomics.selector;
        selectors[4] = PipelineLoanRegistry.setDefault.selector;
        selectors[5] = PipelineLoanRegistry.closeLoan.selector;
        selectors[6] = PipelineLoanRegistry.recordPayment.selector;

        (address loanRegistry,) = readUpgradeable("PipelineLoanRegistry");
        address roleHolder = address(uint160(uint256(valueOf("LoanRegistryManager", false))));
        uint32 delay = uint32(uint256(valueOf("LoanRegistryManager__Delay", false)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(loanRegistry, selectors, LOAN_REGISTRY_MANAGER_ADMIN_ROLE_ID);
        accessManager.grantRole(LOAN_REGISTRY_MANAGER_ADMIN_ROLE_ID, roleHolder, delay);
        vm.stopBroadcast();
    }
}
