// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

interface IWhitelist {
    function isAllowed(address who) external view returns (bool);
}
