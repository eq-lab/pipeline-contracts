// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

interface IWhitelist {
    function isAllowed(address who) external returns (bool);
}
