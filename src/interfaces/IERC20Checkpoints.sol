// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface IERC20Checkpoints {
    function balanceAt(address holder, uint256 blockNumber) external view returns (uint256);

    function totalSupplyAt(uint256 blockNumber) external view returns (uint256);
}
