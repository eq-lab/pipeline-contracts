// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {PipelineSecurityRecordNft} from "../../src/PipelineSecurityRecordNft.sol";
import {SecurityRegistryUpgradeable} from "../../src/securityRegistry/SecurityRegistryUpgradeable.sol";

contract SetupSecurityRegistryRoles is Script, Deployments {
    uint64 constant SECURITY_AGENT_ROLE_ID = uint64(bytes8(keccak256("SECURITY_AGENT_ROLE")));
    uint64 constant SECURITY_RISK_COUNCIL_ROLE_ID = uint64(bytes8(keccak256("SECURITY_RISK_COUNCIL_ROLE")));
    uint64 constant SECURITY_VALUER_ROLE_ID = uint64(bytes8(keccak256("SECURITY_VALUER_ROLE")));
    uint64 constant SECURITY_INSPECTION_OPERATOR_ROLE_ID =
        uint64(bytes8(keccak256("SECURITY_INSPECTION_OPERATOR_ROLE")));
    uint64 constant SECURITY_TRUSTEE_ROLE_ID = uint64(bytes8(keccak256("SECURITY_TRUSTEE_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));
        (address securityRegistry,) = readUpgradeable("PipelineSecurityRegistry");
        (address recordNft,) = readUpgradeable("PipelineSecurityRecordNft");

        bytes4[] memory agentSelectors = new bytes4[](8);
        agentSelectors[0] = SecurityRegistryUpgradeable.register.selector;
        agentSelectors[1] = SecurityRegistryUpgradeable.perfect.selector;
        agentSelectors[2] = SecurityRegistryUpgradeable.handover.selector;
        agentSelectors[3] = SecurityRegistryUpgradeable.attest.selector;
        agentSelectors[4] = SecurityRegistryUpgradeable.release.selector;
        agentSelectors[5] = SecurityRegistryUpgradeable.reportMandateBreach.selector;
        agentSelectors[6] = SecurityRegistryUpgradeable.startEnforcement.selector;
        agentSelectors[7] = SecurityRegistryUpgradeable.markEnforced.selector;

        bytes4[] memory agentNftSelectors = new bytes4[](1);
        agentNftSelectors[0] = PipelineSecurityRecordNft.addDoc.selector;

        bytes4[] memory riskCouncilSelectors = new bytes4[](3);
        riskCouncilSelectors[0] = SecurityRegistryUpgradeable.setTerms.selector;
        riskCouncilSelectors[1] = SecurityRegistryUpgradeable.releaseWithConsent.selector;
        riskCouncilSelectors[2] = SecurityRegistryUpgradeable.resolveFlag.selector;

        bytes4[] memory riskCouncilNftSelectors = new bytes4[](1);
        riskCouncilNftSelectors[0] = PipelineSecurityRecordNft.setInspectors.selector;

        bytes4[] memory valuerSelectors = new bytes4[](1);
        valuerSelectors[0] = SecurityRegistryUpgradeable.revalue.selector;

        bytes4[] memory operatorSelectors = new bytes4[](2);
        operatorSelectors[0] = PipelineSecurityRecordNft.recordInspection.selector;
        operatorSelectors[1] = PipelineSecurityRecordNft.approveInspection.selector;

        bytes4[] memory trusteeSelectors = new bytes4[](1);
        trusteeSelectors[0] = SecurityRegistryUpgradeable.recordExtensionConsent.selector;

        address agent = address(uint160(uint256(valueOf("SecurityAgent", false))));
        uint32 agentDelay = uint32(uint256(valueOf("SecurityAgent__Delay", true)));
        address riskCouncil = address(uint160(uint256(valueOf("SecurityRiskCouncil", false))));
        uint32 riskCouncilDelay = uint32(uint256(valueOf("SecurityRiskCouncil__Delay", true)));
        address valuer = address(uint160(uint256(valueOf("SecurityValuer", false))));
        uint32 valuerDelay = uint32(uint256(valueOf("SecurityValuer__Delay", true)));
        address operator = address(uint160(uint256(valueOf("SecurityInspectionOperator", false))));
        address secondOperator = address(uint160(uint256(valueOf("SecurityInspectionSecondOperator", false))));
        uint32 operatorDelay = uint32(uint256(valueOf("SecurityInspectionOperator__Delay", true)));
        address trustee = address(uint160(uint256(valueOf("SecurityTrustee", false))));
        uint32 trusteeDelay = uint32(uint256(valueOf("SecurityTrustee__Delay", true)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(securityRegistry, agentSelectors, SECURITY_AGENT_ROLE_ID);
        accessManager.setTargetFunctionRole(recordNft, agentNftSelectors, SECURITY_AGENT_ROLE_ID);
        accessManager.grantRole(SECURITY_AGENT_ROLE_ID, agent, agentDelay);
        accessManager.setTargetFunctionRole(securityRegistry, riskCouncilSelectors, SECURITY_RISK_COUNCIL_ROLE_ID);
        accessManager.setTargetFunctionRole(recordNft, riskCouncilNftSelectors, SECURITY_RISK_COUNCIL_ROLE_ID);
        accessManager.grantRole(SECURITY_RISK_COUNCIL_ROLE_ID, riskCouncil, riskCouncilDelay);
        accessManager.setTargetFunctionRole(securityRegistry, valuerSelectors, SECURITY_VALUER_ROLE_ID);
        accessManager.grantRole(SECURITY_VALUER_ROLE_ID, valuer, valuerDelay);
        accessManager.setTargetFunctionRole(recordNft, operatorSelectors, SECURITY_INSPECTION_OPERATOR_ROLE_ID);
        accessManager.grantRole(SECURITY_INSPECTION_OPERATOR_ROLE_ID, operator, operatorDelay);
        accessManager.grantRole(SECURITY_INSPECTION_OPERATOR_ROLE_ID, secondOperator, operatorDelay);
        accessManager.setTargetFunctionRole(securityRegistry, trusteeSelectors, SECURITY_TRUSTEE_ROLE_ID);
        accessManager.grantRole(SECURITY_TRUSTEE_ROLE_ID, trustee, trusteeDelay);
        vm.stopBroadcast();
    }
}
