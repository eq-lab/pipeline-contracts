// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";

import {Deployments} from "./base/Deployments.sol";

import {PipelineLoanRegistry} from "../src/PipelineLoanRegistry.sol";
import {StakedPipelineUSD} from "../src/StakedPipelineUSD.sol";
import {WhitelistRegistry} from "../src/WhitelistRegistry.sol";

contract Configure is Script, Deployments {
    function run(string memory tag) external {
        deploymentTag = tag;

        (address loanRegistryProxy,) = readUpgradeable("PipelineLoanRegistry");
        (address stakedPipelineUSDProxy,) = readUpgradeable("StakedPipelineUSD");
        (address whitelistRegistryProxy,) = readUpgradeable("WhitelistRegistry");
        (address pocket,) = readUpgradeable("PipelinePocket");
        (address minter,) = readUpgradeable("PipelineMinter");
        (address withdrawalQueue,) = readUpgradeable("PipelineWithdrawalQueue");

        PipelineLoanRegistry loanRegistry = PipelineLoanRegistry(loanRegistryProxy);
        StakedPipelineUSD stakedPipelineUSD = StakedPipelineUSD(stakedPipelineUSDProxy);
        WhitelistRegistry whitelistRegistry = WhitelistRegistry(whitelistRegistryProxy);

        address capitalWallet = address(uint160(uint256(valueOf("LoanRegistry__CapitalWallet", false))));
        uint32 maxFeeBps = uint32(uint256(valueOf("LoanRegistry__MaxFeeBps", false)));
        uint256 maxResidual = uint256(valueOf("LoanRegistry__MaxResidual", false));
        address treasury = address(uint160(uint256(valueOf("Treasury", false))));

        address[5] memory plUsdHolders = [stakedPipelineUSDProxy, pocket, minter, treasury, withdrawalQueue];

        vm.startBroadcast();
        if (loanRegistry.capitalWallet() != capitalWallet) loanRegistry.setCapitalWallet(capitalWallet);
        if (loanRegistry.maxFeeBps() != maxFeeBps) loanRegistry.setMaxFeeBps(maxFeeBps);
        if (loanRegistry.maxResidual() != maxResidual) loanRegistry.setMaxResidual(maxResidual);
        if (stakedPipelineUSD.pocket() != pocket) stakedPipelineUSD.setPocket(pocket);

        for (uint256 i; i < plUsdHolders.length; ++i) {
            if (!whitelistRegistry.isAllowed(plUsdHolders[i])) whitelistRegistry.allow(plUsdHolders[i]);
        }
        vm.stopBroadcast();
    }
}
