// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {DeployAccessManager} from "./deployers/DeployAccessManager.sol";
import {DeployWhitelistRegistry} from "./deployers/DeployWhitelistRegistry.sol";
import {DeployPipelineUSD} from "./deployers/DeployPipelineUSD.sol";
import {DeployStakedPipelineUSD} from "./deployers/DeployStakedPipelineUSD.sol";
import {DeployPocket} from "./deployers/DeployPocket.sol";
import {DeployLoanRegistry} from "./deployers/DeployLoanRegistry.sol";
import {DeploySecurityRecordNft} from "./deployers/DeploySecurityRecordNft.sol";
import {DeploySecurityRegistry} from "./deployers/DeploySecurityRegistry.sol";
import {DeploySecurityRegistryReader} from "./deployers/DeploySecurityRegistryReader.sol";
import {DeployDealTokenFactory} from "./deployers/DeployDealTokenFactory.sol";
import {DeployMinter} from "./deployers/DeployMinter.sol";
import {DeployMinterReader} from "./deployers/DeployMinterReader.sol";
import {DeployDepositManager} from "./deployers/DeployDepositManager.sol";
import {DeployWithdrawalQueue} from "./deployers/DeployWithdrawalQueue.sol";

/// @notice Full Pipeline system deployment (no access setups though)
/// forge script script/Deploy.s.sol --sig "run(string)" <tag>
contract Deploy is Script {
    function run(string memory tag) external {
        console.log("=== Deploying with tag:", tag);

        address accessManager = (new DeployAccessManager(tag)).deployPlain();
        (address whitelistRegistry,) = (new DeployWhitelistRegistry(tag)).deployUpgradeable();
        (address pipelineUSD,) = (new DeployPipelineUSD(tag)).deployUpgradeable();
        (address stakedPipelineUSD,) = (new DeployStakedPipelineUSD(tag)).deployUpgradeable();
        (address pocket,) = (new DeployPocket(tag)).deployUpgradeable();
        (address loanRegistry,) = (new DeployLoanRegistry(tag)).deployUpgradeable();
        (address securityRecordNft,) = (new DeploySecurityRecordNft(tag)).deployUpgradeable();
        (address securityRegistry,) = (new DeploySecurityRegistry(tag)).deployUpgradeable();
        address securityRegistryReader = (new DeploySecurityRegistryReader(tag)).deployPlain();
        (address dealTokenFactory,) = (new DeployDealTokenFactory(tag)).deployUpgradeable();
        (address minter,) = (new DeployMinter(tag)).deployUpgradeable();
        (new DeployMinterReader(tag)).deployPlain();
        (address depositManager,) = (new DeployDepositManager(tag)).deployUpgradeable();
        (address withdrawalQueue,) = (new DeployWithdrawalQueue(tag)).deployUpgradeable();

        console.log("=== Done");
        console.log("AccessManager: ", accessManager);
        console.log("WhitelistRegistry: ", whitelistRegistry);
        console.log("PipelineUSD: ", pipelineUSD);
        console.log("StakedPipelineUSD: ", stakedPipelineUSD);
        console.log("Pocket: ", pocket);
        console.log("LoanRegistry: ", loanRegistry);
        console.log("SecurityRecordNft: ", securityRecordNft);
        console.log("SecurityRegistry: ", securityRegistry);
        console.log("SecurityRegistryReader: ", securityRegistryReader);
        console.log("DealTokenFactory: ", dealTokenFactory);
        console.log("Minter: ", minter);
        console.log("DepositManager: ", depositManager);
        console.log("WithdrawalQueue: ", withdrawalQueue);
    }
}
