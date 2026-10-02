// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {CollateralRegistryUpgradeable} from "../../src/collateralRegistry/CollateralRegistryUpgradeable.sol";

contract SetupCollateralRegistryRoles is Script, Deployments {
    uint64 constant COLLATERAL_TRUSTEE_ROLE_ID = uint64(bytes8(keccak256("COLLATERAL_TRUSTEE_ROLE")));
    uint64 constant COLLATERAL_VALUER_ROLE_ID = uint64(bytes8(keccak256("COLLATERAL_VALUER_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));
        (address collateralRegistry,) = readUpgradeable("PipelineCollateralRegistry");

        bytes4[] memory trusteeSelectors = new bytes4[](9);
        trusteeSelectors[0] = CollateralRegistryUpgradeable.pledge.selector;
        trusteeSelectors[1] = CollateralRegistryUpgradeable.setHaircut.selector;
        trusteeSelectors[2] = CollateralRegistryUpgradeable.setFloor.selector;
        trusteeSelectors[3] = CollateralRegistryUpgradeable.setStage.selector;
        trusteeSelectors[4] = CollateralRegistryUpgradeable.setControl.selector;
        trusteeSelectors[5] = CollateralRegistryUpgradeable.addDoc.selector;
        trusteeSelectors[6] = CollateralRegistryUpgradeable.adjustQuantity.selector;
        trusteeSelectors[7] = CollateralRegistryUpgradeable.release.selector;
        trusteeSelectors[8] = CollateralRegistryUpgradeable.liquidate.selector;

        bytes4[] memory valuerSelectors = new bytes4[](1);
        valuerSelectors[0] = CollateralRegistryUpgradeable.revalue.selector;

        address trustee = address(uint160(uint256(valueOf("CollateralTrustee", false))));
        uint32 trusteeDelay = uint32(uint256(valueOf("CollateralTrustee__Delay", true)));
        address valuer = address(uint160(uint256(valueOf("CollateralValuer", false))));
        uint32 valuerDelay = uint32(uint256(valueOf("CollateralValuer__Delay", true)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(collateralRegistry, trusteeSelectors, COLLATERAL_TRUSTEE_ROLE_ID);
        accessManager.grantRole(COLLATERAL_TRUSTEE_ROLE_ID, trustee, trusteeDelay);
        accessManager.setTargetFunctionRole(collateralRegistry, valuerSelectors, COLLATERAL_VALUER_ROLE_ID);
        accessManager.grantRole(COLLATERAL_VALUER_ROLE_ID, valuer, valuerDelay);
        vm.stopBroadcast();
    }
}
