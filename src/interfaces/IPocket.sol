// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface IPocket {
    function open(uint256 loanId, uint256 amount, uint256 snapshotBlock, uint256 supplyAtSnapshot) external;

    function release(uint256 loanId, uint256 principal, uint256 interest) external returns (uint256 released);

    function unrelease(uint256 loanId, uint256 principal, uint256 interest) external;

    function burn(uint256 loanId, uint256 amount) external returns (uint256 burned);
}
