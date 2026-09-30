// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface IPocket {
    function burn(uint256 loanId, uint256 amount) external returns (uint256 burned);
}
