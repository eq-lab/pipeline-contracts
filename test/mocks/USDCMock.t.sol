// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

contract USDCMock is ERC20, Test {
    constructor() ERC20("USDC Mock", "USDCm") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
