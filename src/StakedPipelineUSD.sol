// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPocket} from "./interfaces/IPocket.sol";
import {IStakedPipelineUSD} from "./interfaces/IStakedPipelineUSD.sol";
import {ERC20CheckpointsUpgradeable} from "./stakedPipelineUSD/ERC20CheckpointsUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract StakedPipelineUSD is
    UUPSUpgradeable,
    ERC4626Upgradeable,
    ERC20CheckpointsUpgradeable,
    AccessManagedUpgradeable,
    PausableUpgradeable,
    IStakedPipelineUSD
{
    using SafeERC20 for IERC20;

    event CarvedOut(uint256 indexed loanId, uint256 amount, uint256 moved, uint256 snapshotBlock);
    event Pulled(uint256 amount, uint256 pulled);
    event SharesBurned(address indexed owner, uint256 shares, uint256 assets);
    event PocketSet(address pocket);

    error StakedPipelineUSDCarveOutBlock();
    error StakedPipelineUSDNotConfigured();
    error StakedPipelineUSDZeroAddress();
    error StakedPipelineUSDSameValue();

    /// @custom:storage-location erc7201:pipeline.storage.StakedPipelineUSD
    struct StakedPipelineUSDStorage {
        IPocket pocket;
        uint256 carveOutBlock;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.StakedPipelineUSD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StakedPipelineUSDStorageLocation =
        0xecaca97656fa4b9ea10ef4e716015ee2a861abf104e122b2305c4ee7bc672500;

    function _getStakedPipelineUSDStorage() private pure returns (StakedPipelineUSDStorage storage $) {
        assembly {
            $.slot := StakedPipelineUSDStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 asset, address authority) external initializer {
        __ERC20_init("Staked Pipeline USD", "sPLUSD");
        __ERC4626_init(asset);
        __AccessManaged_init(authority);
    }

    function carveOut(uint256 loanId, uint256 amount) external restricted returns (uint256 moved) {
        StakedPipelineUSDStorage storage $ = _getStakedPipelineUSDStorage();
        IPocket _pocket = $.pocket;
        if (address(_pocket) == address(0)) revert StakedPipelineUSDNotConfigured();

        moved = _sendAssets(address(_pocket), amount);
        $.carveOutBlock = block.number;
        _pocket.open(loanId, moved, block.number, totalSupply());

        emit CarvedOut(loanId, amount, moved, block.number);
    }

    function pull(uint256 amount) external restricted returns (uint256 pulled) {
        pulled = _sendAssets(msg.sender, amount);

        emit Pulled(amount, pulled);
    }

    function burnShares(address owner, uint256 shares) external restricted returns (uint256 assets) {
        assets = previewRedeem(shares);

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(msg.sender, assets);

        emit Withdraw(msg.sender, msg.sender, owner, assets, shares);
        emit SharesBurned(owner, shares, assets);
    }

    function setPocket(address newPocket) external restricted {
        if (newPocket == address(0)) revert StakedPipelineUSDZeroAddress();

        StakedPipelineUSDStorage storage $ = _getStakedPipelineUSDStorage();
        if (address($.pocket) == newPocket) revert StakedPipelineUSDSameValue();
        $.pocket = IPocket(newPocket);

        emit PocketSet(newPocket);
    }

    function pause() external restricted {
        _pause();
    }

    function unpause() external restricted {
        _unpause();
    }

    function pocket() external view returns (address) {
        return address(_getStakedPipelineUSDStorage().pocket);
    }

    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused
        returns (uint256 shares)
    {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused
        returns (uint256 assets)
    {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused
        returns (uint256 shares)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused
        returns (uint256 assets)
    {
        return super.redeem(shares, receiver, owner);
    }

    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable, IERC20Metadata) returns (uint8) {
        return super.decimals();
    }

    function _sendAssets(address to, uint256 amount) private returns (uint256 sent) {
        sent = Math.min(amount, totalAssets());
        if (sent != 0) IERC20(asset()).safeTransfer(to, sent);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20CheckpointsUpgradeable)
    {
        if (_getStakedPipelineUSDStorage().carveOutBlock == block.number) {
            revert StakedPipelineUSDCarveOutBlock();
        }
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
