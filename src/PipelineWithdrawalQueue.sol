// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {WhitelistAccessedUpgradeable} from "./whitelist/WhitelistAccessedUpgradeable.sol";
import {WithdrawalQueueShutdownUpgradeable} from "./withdrawalQueue/WithdrawalQueueShutdownUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineWithdrawalQueue is UUPSUpgradeable, WithdrawalQueueShutdownUpgradeable, WhitelistAccessedUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address authority,
        address whitelistRegistry,
        address fromToken,
        address intoToken,
        address intoTokenHolder
    ) external initializer {
        __AccessManaged_init(authority);
        __WithdrawalQueueShutdown_init(fromToken, intoToken, intoTokenHolder);
        __WhitelistAccessed_init(whitelistRegistry);
    }

    function claimWithdrawal(uint256 requestId)
        external
        virtual
        override
        onlyAllowed(msg.sender)
        returns (uint256 amount)
    {
        return _claimWithdrawal(requestId);
    }

    function changeIntoTokenHolder(address newIntoTokenHolder) external virtual override restricted {
        _changeIntoTokenHolder(newIntoTokenHolder);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
