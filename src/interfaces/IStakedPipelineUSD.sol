// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Checkpoints} from "./IERC20Checkpoints.sol";

interface IStakedPipelineUSD is IERC4626, IERC20Checkpoints {
    function carveOut(uint256 loanId, uint256 amount) external returns (uint256 moved);

    function pull(uint256 amount) external returns (uint256 pulled);

    function burnShares(address owner, uint256 shares) external returns (uint256 assets);
}
