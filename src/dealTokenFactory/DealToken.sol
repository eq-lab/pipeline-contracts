// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DealToken is ERC20 {
    address public immutable factory;

    error DealTokenOnlyFactory();
    error DealTokenNonTransferrable();

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        factory = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        _onlyFactory();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _onlyFactory();
        _burn(from, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert DealTokenNonTransferrable();
        super._update(from, to, value);
    }

    function _onlyFactory() private view {
        if (msg.sender != factory) revert DealTokenOnlyFactory();
    }
}
