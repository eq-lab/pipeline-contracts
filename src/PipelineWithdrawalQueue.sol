// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {WithdrawalQueueShutdownUpgradeable} from "./withdrawalQueue/WithdrawalQueueShutdownUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineWithdrawalQueue is UUPSUpgradeable, WithdrawalQueueShutdownUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address authority, address verifier, address _plUsd, address _usdc, address assetHolder)
        external
        initializer
    {
        __AccessManaged_init(authority);
        __WithdrawalQueueShutdown_init("PipelineWithdrawalQueue", "v1", verifier, _plUsd, _usdc, assetHolder);
    }

    function setAssetHolder(address newAssetHolder) external virtual override restricted {
        _setAssetHolder(newAssetHolder);
    }

    function usdc() external view returns (address) {
        return _asset();
    }

    function plUsd() external view returns (address) {
        return _share();
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
