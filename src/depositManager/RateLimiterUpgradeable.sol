// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

contract RateLimiterUpgradeable is Initializable, AccessManagedUpgradeable {
    struct RateLimitConfig {
        uint256 txLimit;
        uint256 windowLimit;
        uint256 window;
        uint256 shift;
    }

    event TxLimitIncreased(uint256 newTxLimit);
    event TxLimitDecreased(uint256 newTxLimit);
    event WindowLimitIncreased(uint256 newWindowLimit);
    event WindowLimitDecreased(uint256 newWindowLimit);
    event RateLimitApplied(uint256 timestamp, uint256 updatedWindowCumulativeMint);

    error RateLimiterExceedsTxLimit();
    error RateLimiterExceedsWindowLimit();
    error RateLimiterWrongValue();

    /// @custom:storage-location erc7201:pipeline.storage.RateLimiter
    struct RateLimiterStorage {
        RateLimitConfig rateLimitConfig;
        uint256 lastMintTimestamp;
        uint256 windowCumulativeMint;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.RateLimiter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RateLimiterStorageLocation =
        0xab9123373c6f5ba0e1acfc1be7fd147df31f22e1ccc5a2acf1c43716d0e9ba00;

    function _getRateLimiterStorage() private pure returns (RateLimiterStorage storage $) {
        assembly {
            $.slot := RateLimiterStorageLocation
        }
    }

    function __RateLimiter_init(address authority, RateLimitConfig calldata _rateLimitConfig)
        internal
        onlyInitializing
    {
        __AccessManaged_init(authority);
        __RateLimiter_init_unchained(_rateLimitConfig);
    }

    function __RateLimiter_init_unchained(RateLimitConfig calldata _rateLimitConfig) internal onlyInitializing {
        if (_rateLimitConfig.window == 0) revert RateLimiterWrongValue();
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        $.rateLimitConfig = _rateLimitConfig;
    }

    function increaseTxLimit(uint256 newTxLimit) external restricted {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.rateLimitConfig.txLimit >= newTxLimit) revert RateLimiterWrongValue();

        $.rateLimitConfig.txLimit = newTxLimit;
        emit TxLimitIncreased(newTxLimit);
    }

    function decreaseTxLimit(uint256 newTxLimit) external restricted {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.rateLimitConfig.txLimit <= newTxLimit) revert RateLimiterWrongValue();

        $.rateLimitConfig.txLimit = newTxLimit;
        emit TxLimitDecreased(newTxLimit);
    }

    function increaseWindowLimit(uint256 newWindowLimit) external restricted {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.rateLimitConfig.windowLimit >= newWindowLimit) revert RateLimiterWrongValue();

        $.rateLimitConfig.windowLimit = newWindowLimit;
        emit WindowLimitIncreased(newWindowLimit);
    }

    function decreaseWindowLimit(uint256 newWindowLimit) external restricted {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        if ($.rateLimitConfig.windowLimit <= newWindowLimit) revert RateLimiterWrongValue();

        $.rateLimitConfig.windowLimit = newWindowLimit;
        emit WindowLimitDecreased(newWindowLimit);
    }

    function rateLimitConfig() external view returns (RateLimitConfig memory) {
        return _getRateLimiterStorage().rateLimitConfig;
    }

    function lastMintTimestamp() external view returns (uint256) {
        return _getRateLimiterStorage().lastMintTimestamp;
    }

    function windowCumulativeMint() external view returns (uint256) {
        return _currentWindowCumulativeMint();
    }

    function _applyRateLimits(uint256 amount) internal {
        RateLimiterStorage storage $ = _getRateLimiterStorage();

        if ($.rateLimitConfig.txLimit < amount) revert RateLimiterExceedsTxLimit();

        uint256 currentWindowCumulativeMint = _currentWindowCumulativeMint();
        if (currentWindowCumulativeMint + amount > $.rateLimitConfig.windowLimit) {
            revert RateLimiterExceedsWindowLimit();
        }

        $.lastMintTimestamp = block.timestamp;
        uint256 updatedWindowCumulativeMint = currentWindowCumulativeMint + amount;
        $.windowCumulativeMint = currentWindowCumulativeMint + amount;

        emit RateLimitApplied(block.timestamp, updatedWindowCumulativeMint);
    }

    function _currentWindowCumulativeMint() internal view returns (uint256) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();

        uint256 window = $.rateLimitConfig.window;
        uint256 shift = $.rateLimitConfig.shift;

        uint256 currentWindowIndex = (block.timestamp + shift) / window;
        uint256 prevMintWindowIndex = ($.lastMintTimestamp + shift) / window;

        return currentWindowIndex == prevMintWindowIndex ? $.windowCumulativeMint : 0;
    }
}
