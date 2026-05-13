// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {WithdrawalQueueShutdownUpgradeable} from "./withdrawalQueue/WithdrawalQueueShutdownUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineWithdrawalQueue is UUPSUpgradeable, WithdrawalQueueShutdownUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address authority,
        address verifier,
        address fromToken,
        address intoToken,
        address intoTokenHolder
    ) external initializer {
        __AccessManaged_init(authority);
        __WithdrawalQueueShutdown_init("PipelineWithdrawalQueue", "v1", verifier, fromToken, intoToken, intoTokenHolder);
    }

    function claimWithdrawal(uint256 requestId, bytes calldata verifierSignature)
        external
        virtual
        override
        returns (uint256 amount)
    {
        return _claimWithdrawal(requestId, verifierSignature);
    }

    function changeIntoTokenHolder(address newIntoTokenHolder) external virtual override restricted {
        _changeIntoTokenHolder(newIntoTokenHolder);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
