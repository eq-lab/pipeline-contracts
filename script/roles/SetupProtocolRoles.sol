// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {PipelineLoanRegistry} from "../../src/PipelineLoanRegistry.sol";
import {PipelinePocket} from "../../src/PipelinePocket.sol";
import {StakedPipelineUSD} from "../../src/StakedPipelineUSD.sol";

contract SetupProtocolRoles is Script, Deployments {
    uint64 constant PIPELINE_MINTER_ROLE_ID = uint64(bytes8(keccak256("PIPELINE_MINTER_ROLE")));
    uint64 constant LOAN_REGISTRY_ROLE_ID = uint64(bytes8(keccak256("LOAN_REGISTRY_ROLE")));
    uint64 constant STAKED_PLUSD_ROLE_ID = uint64(bytes8(keccak256("STAKED_PLUSD_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));
        (address loanRegistry,) = readUpgradeable("PipelineLoanRegistry");
        (address stakedPipelineUSD,) = readUpgradeable("StakedPipelineUSD");
        (address pocket,) = readUpgradeable("PipelinePocket");
        (address minter,) = readUpgradeable("PipelineMinter");

        bytes4[] memory registrySelectors = new bytes4[](4);
        registrySelectors[0] = PipelineLoanRegistry.disburse.selector;
        registrySelectors[1] = PipelineLoanRegistry.undisburse.selector;
        registrySelectors[2] = PipelineLoanRegistry.recordPayment.selector;
        registrySelectors[3] = PipelineLoanRegistry.unrecordPayment.selector;

        bytes4[] memory vaultMinterSelectors = new bytes4[](2);
        vaultMinterSelectors[0] = StakedPipelineUSD.pull.selector;
        vaultMinterSelectors[1] = StakedPipelineUSD.burnShares.selector;

        bytes4[] memory pocketMinterSelectors = new bytes4[](2);
        pocketMinterSelectors[0] = PipelinePocket.release.selector;
        pocketMinterSelectors[1] = PipelinePocket.unrelease.selector;

        bytes4[] memory vaultRegistrySelectors = new bytes4[](1);
        vaultRegistrySelectors[0] = StakedPipelineUSD.carveOut.selector;

        bytes4[] memory pocketRegistrySelectors = new bytes4[](1);
        pocketRegistrySelectors[0] = PipelinePocket.burn.selector;

        bytes4[] memory pocketVaultSelectors = new bytes4[](1);
        pocketVaultSelectors[0] = PipelinePocket.open.selector;

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(loanRegistry, registrySelectors, PIPELINE_MINTER_ROLE_ID);
        accessManager.setTargetFunctionRole(stakedPipelineUSD, vaultMinterSelectors, PIPELINE_MINTER_ROLE_ID);
        accessManager.setTargetFunctionRole(pocket, pocketMinterSelectors, PIPELINE_MINTER_ROLE_ID);
        accessManager.grantRole(PIPELINE_MINTER_ROLE_ID, minter, 0);

        accessManager.setTargetFunctionRole(stakedPipelineUSD, vaultRegistrySelectors, LOAN_REGISTRY_ROLE_ID);
        accessManager.setTargetFunctionRole(pocket, pocketRegistrySelectors, LOAN_REGISTRY_ROLE_ID);
        accessManager.grantRole(LOAN_REGISTRY_ROLE_ID, loanRegistry, 0);

        accessManager.setTargetFunctionRole(pocket, pocketVaultSelectors, STAKED_PLUSD_ROLE_ID);
        accessManager.grantRole(STAKED_PLUSD_ROLE_ID, stakedPipelineUSD, 0);
        vm.stopBroadcast();
    }
}
