// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20Managed} from "../interfaces/IERC20Managed.sol";
import {VerifiedRequestsQueueUpgradeable} from "./VerifiedRequestsQueueUpgradeable.sol";

abstract contract WithdrawalQueueUpgradeable is VerifiedRequestsQueueUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Managed;

    event WithdrawalRequested(address indexed withdrawer, uint256 indexed requestId, uint256 amount, uint256 queued);
    event IntoTokenHolderSet(address indexed intoTokenHolder);

    error WithdrawalQueueZeroAddress();
    error WithdrawalQueueSameValue();
    error WithdrawalQueueTooEarly();

    /// @custom:storage-location erc7201:pipeline.storage.WithdrawalQueue
    struct WithdrawalQueueStorage {
        // cumulative total of all withdrawal requests included the ones that have already been claimed
        uint256 totalQueued;
        // total of all the requests that have been claimed
        uint256 totalClaimed;
        uint256 rate;
        IERC20Managed fromToken;
        IERC20 intoToken;
        address intoTokenHolder;
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
        address _fromToken,
        address _intoToken,
        address _intoTokenHolder
    ) internal onlyInitializing {
        __VerifiedRequestsQueue_init(name, version, verifier);
        __WithdrawalQueue_init_unchained(_fromToken, _intoToken, _intoTokenHolder);
    }

    function __WithdrawalQueue_init_unchained(address _fromToken, address _intoToken, address _intoTokenHolder)
        internal
        onlyInitializing
    {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        $.fromToken = IERC20Managed(_fromToken);
        $.intoToken = IERC20(_intoToken);

        _setIntoTokenHolder(_intoTokenHolder);
    }

    function requestWithdrawal(uint256 amount) external virtual returns (uint256 requestId, uint256 queued) {
        requestId = _enqueueRequest(msg.sender, amount);

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        queued = $.totalQueued + amount;
        $.totalQueued = queued;
        $.queued[requestId] = queued;
        $.fromToken.safeTransferFrom(msg.sender, address(this), amount);

        emit WithdrawalRequested(msg.sender, requestId, amount, queued);
    }

    function claimWithdrawal(uint256 requestId, bytes calldata verifierSignature)
        external
        virtual
        returns (uint256 amount)
    {
        return _claimWithdrawal(requestId, verifierSignature);
    }

    function changeIntoTokenHolder(address newIntoTokenHolder) external virtual;

    function withdrawalRequestQueued(uint256 requestId) external view returns (uint256) {
        return _getWithdrawalQueueStorage().queued[requestId];
    }

    function queueMetadata() external view returns (uint256 totalQueued, uint256 totalClaimed) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        return ($.totalQueued, $.totalClaimed);
    }

    function claimable() public view returns (uint256) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        IERC20 _intoToken = $.intoToken;
        address _intoTokenHolder = $.intoTokenHolder;
        return $.totalClaimed + convertFrom(_intoToken.balanceOf(_intoTokenHolder));
    }

    function isClaimable(uint256 requestId) external view returns (bool) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        return $.queued[requestId] <= claimable();
    }

    function fromToken() external view returns (address) {
        return address(_getWithdrawalQueueStorage().fromToken);
    }

    function intoToken() external view returns (address) {
        return address(_getWithdrawalQueueStorage().intoToken);
    }

    function intoTokenHolder() external view returns (address) {
        return address(_getWithdrawalQueueStorage().intoTokenHolder);
    }

    function convertInto(uint256 fromTokenAmount) public view virtual returns (uint256 intoTokenAmount) {
        return fromTokenAmount;
    }

    function convertFrom(uint256 intoTokenAmount) public view virtual returns (uint256 fromTokenAmount) {
        return intoTokenAmount;
    }

    function _claimWithdrawal(uint256 requestId, bytes calldata verifierSignature)
        internal
        virtual
        returns (uint256 amount)
    {
        uint256 requestAmount = _claimRequest(requestId, verifierSignature);

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        IERC20 _intoToken = $.intoToken;
        address _intoTokenHolder = $.intoTokenHolder;

        uint256 _claimable = $.totalClaimed + convertFrom(_intoToken.balanceOf(_intoTokenHolder));
        if ($.queued[requestId] > _claimable) revert WithdrawalQueueTooEarly();

        amount = convertInto(requestAmount);
        $.totalClaimed += requestAmount;

        _intoToken.safeTransferFrom(_intoTokenHolder, msg.sender, amount);
        $.fromToken.burn(requestAmount);
    }

    function _changeIntoTokenHolder(address newIntoTokenHolder) internal {
        if (_getWithdrawalQueueStorage().intoTokenHolder == newIntoTokenHolder) revert WithdrawalQueueSameValue();
        _setIntoTokenHolder(newIntoTokenHolder);
    }

    function _setIntoTokenHolder(address newIntoTokenHolder) private {
        if (newIntoTokenHolder == address(0)) revert WithdrawalQueueZeroAddress();
        _getWithdrawalQueueStorage().intoTokenHolder = newIntoTokenHolder;

        emit IntoTokenHolderSet(newIntoTokenHolder);
    }
}
