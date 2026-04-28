// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {DeployAccessManager} from "./deployers/DeployAccessManager.sol";
import {DeployWhitelistRegistry} from "./deployers/DeployWhitelistRegistry.sol";
import {DeployPipelineUSD} from "./deployers/DeployPipelineUSD.sol";
import {DeployStakedPipelineUSD} from "./deployers/DeployStakedPipelineUSD.sol";
import {DeployYieldMinter} from "./deployers/DeployYieldMinter.sol";
import {DeployDepositManager} from "./deployers/DeployDepositManager.sol";
import {DeployWithdrawalQueue} from "./deployers/DeployWithdrawalQueue.sol";
import {DeployLoanRegistry} from "./deployers/DeployLoanRegistry.sol";

/// @notice Full Pipeline system deployment (no access setups though)
/// forge script script/Deploy.s.sol --sig "run(string)" <tag>
contract Deploy is Script {
    function run(string memory tag) external {
        console.log("=== Deploying with tag:", tag);

        address accessManager = (new DeployAccessManager(tag)).deployPlain();
        (address whitelistRegistryProxy,) = (new DeployWhitelistRegistry(tag)).deployUpgradeable();
        (address pipelineUSDProxy,) = (new DeployPipelineUSD(tag)).deployUpgradeable();
        (address stakedPipelineUSDProxy,) = (new DeployStakedPipelineUSD(tag)).deployUpgradeable();
        address yieldMinter = (new DeployYieldMinter(tag)).deployPlain();
        (address depositManager,) = (new DeployDepositManager(tag)).deployUpgradeable();
        (address withdrawalQueue,) = (new DeployWithdrawalQueue(tag)).deployUpgradeable();
        (address loanRegistry,) = (new DeployLoanRegistry(tag)).deployUpgradeable();

        console.log("=== Done");
        console.log("AccessManager: ", accessManager);
        console.log("WhitelistRegistry: ", whitelistRegistryProxy);
        console.log("PipelineUSD: ", pipelineUSDProxy);
        console.log("StakedPipelineUSD: ", stakedPipelineUSDProxy);
        console.log("YieldMinter: ", yieldMinter);
        console.log("DepositManager: ", depositManager);
        console.log("WithdrawalQueue: ", withdrawalQueue);
        console.log("LoanRegistry: ", loanRegistry);
    }
}
