// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {WithdrawalQueueUpgradeable} from "./WithdrawalQueueUpgradeable.sol";

abstract contract WithdrawalQueueShutdownUpgradeable is AccessManagedUpgradeable, WithdrawalQueueUpgradeable {
    using Math for uint256;

    uint256 public constant RATE_ONE = 1_000_000;

    event RateSet(uint256 newRate);

    error WithdrawalQueueShutdownInvalidRate();

    /// @custom:storage-location erc7201:pipeline.storage.WithdrawalQueueShutdown
    struct WithdrawalQueueShutdownStorage {
        uint256 rate;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.WithdrawalQueueShutdown")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalQueueShutdownStorageLocation =
        0x26774be7d47e86af0590ea7a846e35ad4743fdd0a1e11c0b871e10a4798e3b00;

    function _getWithdrawalQueueShutdownStorage() private pure returns (WithdrawalQueueShutdownStorage storage $) {
        assembly {
            $.slot := WithdrawalQueueShutdownStorageLocation
        }
    }

    function __WithdrawalQueueShutdown_init(
        string memory name,
        string memory version,
        address verifier,
        address _share,
        address _asset,
        address _assetHolder
    ) internal onlyInitializing {
        __WithdrawalQueue_init(name, version, verifier, _share, _asset, _assetHolder);
        __WithdrawalQueueShutdown_init_unchained();
    }

    function __WithdrawalQueueShutdown_init_unchained() internal onlyInitializing {
        _getWithdrawalQueueShutdownStorage().rate = RATE_ONE;
    }

    function setRate(uint256 newRate) external restricted {
        if (newRate == 0 || newRate > RATE_ONE) revert WithdrawalQueueShutdownInvalidRate();

        _getWithdrawalQueueShutdownStorage().rate = newRate;

        emit RateSet(newRate);
    }

    function setVerifier(address verifier) external restricted {
        _setVerifier(verifier);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function rate() public view returns (uint256) {
        return _getWithdrawalQueueShutdownStorage().rate;
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256 assets) {
        return shares.mulDiv(rate(), RATE_ONE);
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256 shares) {
        return assets.mulDiv(RATE_ONE, rate());
    }
}
