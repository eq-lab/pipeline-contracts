// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface IPocket {
    function open(uint256 loanId, uint256 amount, uint256 snapshotBlock, uint256 supplyAtSnapshot) external;

    function burn(uint256 loanId, uint256 amount) external returns (uint256 burned);
}
