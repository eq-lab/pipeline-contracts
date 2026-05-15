// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20Managed} from "../interfaces/IERC20Managed.sol";
import {VerifiedRequestsQueueUpgradeable} from "../requestsQueue/VerifiedRequestsQueueUpgradeable.sol";

abstract contract WithdrawalQueueUpgradeable is VerifiedRequestsQueueUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Managed;

    event WithdrawalRequested(address indexed withdrawer, uint256 indexed requestId, uint256 amount, uint256 queued);
    event AssetHolderSet(address indexed assetHolder);

    error WithdrawalQueueZeroAddress();
    error WithdrawalQueueSameValue();
    error WithdrawalQueueTooEarly();

    /// @custom:storage-location erc7201:pipeline.storage.WithdrawalQueue
    struct WithdrawalQueueStorage {
        // cumulative total of all withdrawal requests included the ones that have already been claimed
        uint256 totalQueued;
        // total of all the requests that have been claimed
        uint256 totalClaimed;
        IERC20Managed share;
        IERC20 asset;
        address assetHolder;
        mapping(uint256 requestId => uint256) queued;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.WithdrawalQueue")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalQueueStorageLocation =
        0x4cac70af0cf2a7940d95a04f5e319da114dcc73860d034caf69b06ca0a374600;

    function _getWithdrawalQueueStorage() private pure returns (WithdrawalQueueStorage storage $) {
        assembly {
            $.slot := WithdrawalQueueStorageLocation
        }
    }

    function __WithdrawalQueue_init(
        string memory name,
        string memory version,
        address verifier,
        address share,
        address asset,
        address _assetHolder
    ) internal onlyInitializing {
        __VerifiedRequestsQueue_init(name, version, verifier);
        __WithdrawalQueue_init_unchained(share, asset, _assetHolder);
    }

    function __WithdrawalQueue_init_unchained(address share, address asset, address _assetHolder)
        internal
        onlyInitializing
    {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        $.share = IERC20Managed(share);
        $.asset = IERC20(asset);

        _setAssetHolder(_assetHolder);
    }

    function requestWithdrawal(uint256 amount) external virtual returns (uint256 requestId, uint256 queued) {
        requestId = _enqueueRequest(msg.sender, amount);

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        queued = $.totalQueued + amount;
        $.totalQueued = queued;
        $.queued[requestId] = queued;
        $.share.safeTransferFrom(msg.sender, address(this), amount);

        emit WithdrawalRequested(msg.sender, requestId, amount, queued);
    }

    function claimWithdrawal(uint256 requestId, bytes calldata verifierSignature)
        external
        virtual
        returns (uint256 amount)
    {
        return _claimWithdrawal(requestId, verifierSignature);
    }

    function setAssetHolder(address newAssetHolder) external virtual;

    function withdrawalRequestQueued(uint256 requestId) external view returns (uint256) {
        return _getWithdrawalQueueStorage().queued[requestId];
    }

    function queueMetadata() external view returns (uint256 totalQueued, uint256 totalClaimed) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        return ($.totalQueued, $.totalClaimed);
    }

    function claimableAmount() public view returns (uint256) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        return $.totalClaimed + convertToShares($.asset.balanceOf($.assetHolder));
    }

    function isClaimable(uint256 requestId) external view returns (bool) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        Request memory request = requests(requestId);
        return !request.claimed && $.queued[requestId] <= claimableAmount();
    }

    function assetHolder() external view returns (address) {
        return address(_getWithdrawalQueueStorage().assetHolder);
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        return assets;
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        return shares;
    }

    function _claimWithdrawal(uint256 requestId, bytes calldata verifierSignature)
        internal
        virtual
        returns (uint256 amount)
    {
        uint256 requestAmount = _claimRequest(requestId, verifierSignature);

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        IERC20 asset = $.asset;
        address _assetHolder = $.assetHolder;

        uint256 _claimableAmount = $.totalClaimed + convertToShares(asset.balanceOf(_assetHolder));
        if ($.queued[requestId] > _claimableAmount) revert WithdrawalQueueTooEarly();

        amount = convertToAssets(requestAmount);
        $.totalClaimed += requestAmount;

        asset.safeTransferFrom(_assetHolder, msg.sender, amount);
        $.share.burn(requestAmount);
    }

    function _setAssetHolder(address newAssetHolder) internal {
        if (newAssetHolder == address(0)) revert WithdrawalQueueZeroAddress();

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        if ($.assetHolder == newAssetHolder) revert WithdrawalQueueSameValue();
        $.assetHolder = newAssetHolder;

        emit AssetHolderSet(newAssetHolder);
    }

    function _asset() internal view returns (address) {
        return address(_getWithdrawalQueueStorage().asset);
    }

    function _share() internal view returns (address) {
        return address(_getWithdrawalQueueStorage().share);
    }
}
