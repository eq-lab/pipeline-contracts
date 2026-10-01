// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface IDealTokenFactory {
    function syncDebt(uint256 loanId) external;
}
