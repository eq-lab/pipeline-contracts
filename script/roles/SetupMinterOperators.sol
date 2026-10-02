// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {Deployments} from "../base/Deployments.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {MinterUpgradeable} from "../../src/minter/MinterUpgradeable.sol";

contract SetupMinterOperators is Script, Deployments {
    uint64 constant MINT_CALLER_ROLE_ID = uint64(bytes8(keccak256("MINT_CALLER_ROLE")));
    uint64 constant MINTER_OPS_ROLE_ID = uint64(bytes8(keccak256("MINTER_OPS_ROLE")));

    function run(string memory tag) external {
        deploymentTag = tag;

        AccessManager accessManager = AccessManager(readPlain("AccessManager"));
        (address minter,) = readUpgradeable("PipelineMinter");

        bytes4[] memory mintSelectors = new bytes4[](3);
        mintSelectors[0] = MinterUpgradeable.recordWireIn.selector;
        mintSelectors[1] = MinterUpgradeable.repay.selector;
        mintSelectors[2] = MinterUpgradeable.recordIncome.selector;

        bytes4[] memory opsSelectors = new bytes4[](12);
        opsSelectors[0] = MinterUpgradeable.assignWireIn.selector;
        opsSelectors[1] = MinterUpgradeable.returnWireIn.selector;
        opsSelectors[2] = MinterUpgradeable.disburse.selector;
        opsSelectors[3] = MinterUpgradeable.reverseDisburse.selector;
        opsSelectors[4] = MinterUpgradeable.reverseRepay.selector;
        opsSelectors[5] = MinterUpgradeable.settleWireOut.selector;
        opsSelectors[6] = MinterUpgradeable.cancelWireOut.selector;
        opsSelectors[7] = MinterUpgradeable.openRamp.selector;
        opsSelectors[8] = MinterUpgradeable.closeRamp.selector;
        opsSelectors[9] = MinterUpgradeable.recordExpense.selector;
        opsSelectors[10] = MinterUpgradeable.recordCorrection.selector;
        opsSelectors[11] = MinterUpgradeable.correctVaultMint.selector;

        address mintCaller = address(uint160(uint256(valueOf("MintCaller", false))));
        uint32 mintCallerDelay = uint32(uint256(valueOf("MintCaller__Delay", true)));
        address minterOps = address(uint160(uint256(valueOf("MinterOps", false))));
        uint32 minterOpsDelay = uint32(uint256(valueOf("MinterOps__Delay", true)));

        vm.startBroadcast();
        accessManager.setTargetFunctionRole(minter, mintSelectors, MINT_CALLER_ROLE_ID);
        accessManager.grantRole(MINT_CALLER_ROLE_ID, mintCaller, mintCallerDelay);
        accessManager.setTargetFunctionRole(minter, opsSelectors, MINTER_OPS_ROLE_ID);
        accessManager.grantRole(MINTER_OPS_ROLE_ID, minterOps, minterOpsDelay);
        vm.stopBroadcast();
    }
}
