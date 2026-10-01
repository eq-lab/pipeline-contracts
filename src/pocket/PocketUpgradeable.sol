// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20Managed} from "../interfaces/IERC20Managed.sol";
import {IPocket} from "../interfaces/IPocket.sol";
import {IStakedPipelineUSD} from "../interfaces/IStakedPipelineUSD.sol";

abstract contract PocketUpgradeable is PausableUpgradeable, IPocket {
    using SafeERC20 for IERC20Managed;

    struct PocketData {
        uint256 snapshotBlock;
        uint256 supplyAtSnapshot;
        uint256 held;
        uint256 releasedTotal;
        uint256 burnedTotal;
        uint256 claimedTotal;
    }

    event PocketOpened(uint256 indexed loanId, uint256 amount, uint256 snapshotBlock, uint256 supplyAtSnapshot);
    event Released(uint256 indexed loanId, uint256 principal, uint256 released, uint256 interest);
    event Unreleased(uint256 indexed loanId, uint256 principal, uint256 interest);
    event Burned(uint256 indexed loanId, uint256 amount, uint256 burned);
    event Claimed(uint256 indexed loanId, address indexed holder, uint256 paid);

    error PocketAlreadyOpened(uint256 loanId);
    error PocketNotOpened(uint256 loanId);
    error PocketAlreadyClaimed(uint256 loanId);
    error PocketExceedsReleased(uint256 loanId, uint256 amount, uint256 releasedTotal);

    /// @custom:storage-location erc7201:pipeline.storage.Pocket
    struct PocketStorage {
        IStakedPipelineUSD stakedPlUsd;
        IERC20Managed plUsd;
        mapping(uint256 loanId => PocketData) pockets;
        mapping(uint256 loanId => mapping(address holder => uint256)) claimed;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.Pocket")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PocketStorageLocation = 0x076a71cb58b3ba44afabe19dbe5f831a3db6c316a6c194e7d48b72a0ce901900;

    function _getPocketStorage() private pure returns (PocketStorage storage $) {
        assembly {
            $.slot := PocketStorageLocation
        }
    }

    function __Pocket_init(address _stakedPlUsd) internal onlyInitializing {
        __Pocket_init_unchained(_stakedPlUsd);
    }

    function __Pocket_init_unchained(address _stakedPlUsd) internal onlyInitializing {
        PocketStorage storage $ = _getPocketStorage();
        $.stakedPlUsd = IStakedPipelineUSD(_stakedPlUsd);
        $.plUsd = IERC20Managed(IERC4626(_stakedPlUsd).asset());
    }

    function claim(uint256 loanId) external whenNotPaused returns (uint256 paid) {
        PocketStorage storage $ = _getPocketStorage();
        PocketData storage pocketData = _openedPocket($, loanId);

        paid = _claimable($, pocketData, loanId, msg.sender);
        if (paid != 0) {
            $.claimed[loanId][msg.sender] += paid;
            pocketData.claimedTotal += paid;
            $.plUsd.safeTransfer(msg.sender, paid);
        }

        emit Claimed(loanId, msg.sender, paid);
    }

    function claimable(uint256 loanId, address holder) external view returns (uint256) {
        PocketStorage storage $ = _getPocketStorage();
        return _claimable($, _openedPocket($, loanId), loanId, holder);
    }

    function claimed(uint256 loanId, address holder) external view returns (uint256) {
        return _getPocketStorage().claimed[loanId][holder];
    }

    function pocket(uint256 loanId) external view returns (PocketData memory) {
        PocketStorage storage $ = _getPocketStorage();
        return _openedPocket($, loanId);
    }

    function stakedPlUsd() external view returns (address) {
        return address(_getPocketStorage().stakedPlUsd);
    }

    function plUsd() external view returns (address) {
        return address(_getPocketStorage().plUsd);
    }

    function _open(uint256 loanId, uint256 amount, uint256 snapshotBlock, uint256 supplyAtSnapshot) internal {
        PocketData storage pocketData = _getPocketStorage().pockets[loanId];
        if (pocketData.snapshotBlock != 0) revert PocketAlreadyOpened(loanId);

        pocketData.snapshotBlock = snapshotBlock;
        pocketData.supplyAtSnapshot = supplyAtSnapshot;
        pocketData.held = amount;

        emit PocketOpened(loanId, amount, snapshotBlock, supplyAtSnapshot);
    }

    function _release(uint256 loanId, uint256 principal, uint256 interest) internal returns (uint256 released) {
        PocketData storage pocketData = _openedPocket(_getPocketStorage(), loanId);

        released = Math.min(principal, pocketData.held);
        pocketData.held -= released;
        pocketData.releasedTotal += released + interest;

        emit Released(loanId, principal, released, interest);
    }

    function _unrelease(uint256 loanId, uint256 principal, uint256 interest) internal {
        PocketStorage storage $ = _getPocketStorage();
        PocketData storage pocketData = _openedPocket($, loanId);

        uint256 amount = principal + interest;
        uint256 releasedTotal = pocketData.releasedTotal;
        if (amount > releasedTotal) revert PocketExceedsReleased(loanId, amount, releasedTotal);
        if (pocketData.claimedTotal != 0) revert PocketAlreadyClaimed(loanId);

        pocketData.held += principal;
        pocketData.releasedTotal = releasedTotal - amount;

        if (interest != 0) $.plUsd.burn(interest);

        emit Unreleased(loanId, principal, interest);
    }

    function _burnHeld(uint256 loanId, uint256 amount) internal returns (uint256 burned) {
        PocketStorage storage $ = _getPocketStorage();
        PocketData storage pocketData = _openedPocket($, loanId);

        burned = Math.min(amount, pocketData.held);
        pocketData.held -= burned;
        pocketData.burnedTotal += burned;

        if (burned != 0) $.plUsd.burn(burned);

        emit Burned(loanId, amount, burned);
    }

    function _claimable(PocketStorage storage $, PocketData storage pocketData, uint256 loanId, address holder)
        private
        view
        returns (uint256)
    {
        uint256 supplyAtSnapshot = pocketData.supplyAtSnapshot;
        if (supplyAtSnapshot == 0) return 0;

        uint256 entitled = Math.mulDiv(
            pocketData.releasedTotal, $.stakedPlUsd.balanceAt(holder, pocketData.snapshotBlock), supplyAtSnapshot
        );
        uint256 alreadyClaimed = $.claimed[loanId][holder];
        return entitled > alreadyClaimed ? entitled - alreadyClaimed : 0;
    }

    function _openedPocket(PocketStorage storage $, uint256 loanId)
        private
        view
        returns (PocketData storage pocketData)
    {
        pocketData = $.pockets[loanId];
        if (pocketData.snapshotBlock == 0) revert PocketNotOpened(loanId);
    }
}
