// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface ICollateralRegistry {
    function cargoQuantity(uint256 loanId) external view returns (uint256);
}
