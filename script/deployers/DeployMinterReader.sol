// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {BaseDeployer} from "../base/BaseDeployer.sol";

import {PipelineMinterReader} from "../../src/PipelineMinterReader.sol";

contract DeployMinterReader is BaseDeployer {
    constructor(string memory tag) BaseDeployer(tag) {}

    function key() public pure override returns (string memory) {
        return "PipelineMinterReader";
    }

    function _deployPlain() internal override returns (address) {
        (address minter,) = readUpgradeable("PipelineMinter");
        return address(new PipelineMinterReader(minter));
    }

    function run(string memory tag) external returns (address) {
        deploymentTag = tag;
        return deployPlain();
    }
}
