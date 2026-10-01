// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

import {IERC20Managed} from "./IERC20Managed.sol";

interface IPipelineUSD is IERC20Managed {
    function hasAccess(address who) external view returns (bool);
}
