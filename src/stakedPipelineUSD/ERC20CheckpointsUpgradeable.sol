// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IERC20Checkpoints} from "../interfaces/IERC20Checkpoints.sol";

abstract contract ERC20CheckpointsUpgradeable is ERC20Upgradeable, IERC20Checkpoints {
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;

    /// @custom:storage-location erc7201:pipeline.storage.ERC20Checkpoints
    struct ERC20CheckpointsStorage {
        mapping(address holder => Checkpoints.Trace208) balanceCheckpoints;
        Checkpoints.Trace208 totalSupplyCheckpoints;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.ERC20Checkpoints")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20CheckpointsStorageLocation =
        0x269f062b4029180c546a4dc1143e31ea7a046a8f064470d2b39ee7d6a91ac400;

    function _getERC20CheckpointsStorage() private pure returns (ERC20CheckpointsStorage storage $) {
        assembly {
            $.slot := ERC20CheckpointsStorageLocation
        }
    }

    function balanceAt(address holder, uint256 blockNumber) public view returns (uint256) {
        return _checkpointAt(_getERC20CheckpointsStorage().balanceCheckpoints[holder], blockNumber, balanceOf(holder));
    }

    function totalSupplyAt(uint256 blockNumber) public view returns (uint256) {
        return _checkpointAt(_getERC20CheckpointsStorage().totalSupplyCheckpoints, blockNumber, totalSupply());
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        uint256 fromBalanceBefore = balanceOf(from);
        uint256 toBalanceBefore = balanceOf(to);
        uint256 totalSupplyBefore = totalSupply();

        super._update(from, to, value);

        ERC20CheckpointsStorage storage $ = _getERC20CheckpointsStorage();
        if (from != address(0)) _writeCheckpoint($.balanceCheckpoints[from], fromBalanceBefore, balanceOf(from));
        if (to != address(0)) _writeCheckpoint($.balanceCheckpoints[to], toBalanceBefore, balanceOf(to));
        _writeCheckpoint($.totalSupplyCheckpoints, totalSupplyBefore, totalSupply());
    }

    function _writeCheckpoint(Checkpoints.Trace208 storage checkpoints, uint256 valueBefore, uint256 value) private {
        if (valueBefore == value) return;
        if (checkpoints.length() == 0 && valueBefore != 0) checkpoints.push(0, valueBefore.toUint208());
        checkpoints.push(block.number.toUint48(), value.toUint208());
    }

    function _checkpointAt(Checkpoints.Trace208 storage checkpoints, uint256 blockNumber, uint256 current)
        private
        view
        returns (uint256)
    {
        if (checkpoints.length() == 0) return current;
        return checkpoints.upperLookupRecent(blockNumber.toUint48());
    }
}
