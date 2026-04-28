// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineLoanRegistry} from "../../src/PipelineLoanRegistry.sol";

contract DeployLoanRegistry is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineLoanRegistry";
    }

    function _deployUpgradeable() internal override returns (address) {
        address authority = readPlain("AccessManager");
        string memory name = string(abi.encode(valueOf("LoanRegistry__erc721Name", false)));
        string memory symbol = string(abi.encode(valueOf("LoanRegistry__erc721Symbol", false)));

        Options memory opts;
        return Upgrades.deployUUPSProxy(
            "PipelineLoanRegistry.sol", abi.encodeCall(PipelineLoanRegistry.initialize, (authority, name, symbol)), opts
        );
    }

    /// @notice Standalone entry point: `forge script script/deployers/DeployLoanRegistry.sol --sig "run(string)" <tag>`
    function run(string memory tag) external returns (address proxy, address impl) {
        deploymentTag = tag;
        return deployUpgradeable();
    }
}
