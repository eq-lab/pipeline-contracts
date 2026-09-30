// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IStakedPipelineUSD is IERC4626 {
    function carveOut(uint256 loanId, uint256 amount) external returns (uint256 moved);
}
