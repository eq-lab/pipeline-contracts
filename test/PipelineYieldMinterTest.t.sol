// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {PipelineYieldMinterV1} from "../src/PipelineYieldMinterV1.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract PipelineYieldMinterTest is PipelineTestSetUp {
    function setUp() public override {
        super.setUp();

        vm.prank(whitelistAdmin);
        whitelistRegistry.allowSystemAddress(address(sPlUsd));
    }

    function test_setUp() public view {
        assertEq(yieldMinter.authority(), address(authority));
        assertEq(yieldMinter.mintAuthority(), yieldMinterAuthority);
        assertEq(yieldMinter.stakedPlUsd(), address(sPlUsd));
        assertEq(address(yieldMinter.plUsd()), address(plUsd));
    }

    function test_mintYield(uint256 amount) public {
        vm.assume(amount != 0);

        uint256 totalAssetsBefore = sPlUsd.totalAssets();

        uint256 nonce = yieldMinter.nextNonce();
        bytes memory signature = _createSignature(amount, nonce, yieldMinterAuthorityPrivateKey);

        vm.prank(yieldMinterManager);
        yieldMinter.mintYield(amount, signature);

        assertEq(sPlUsd.totalAssets(), totalAssetsBefore + amount);
        assertEq(yieldMinter.nextNonce(), nonce + 1);

        // replay revert assertion
        vm.prank(yieldMinterManager);
        vm.expectPartialRevert(PipelineYieldMinterV1.PipelineYieldMinterV1UnauthorizedSigner.selector);
        yieldMinter.mintYield(amount, signature);
    }

    function test_wrongSigner(uint256 wrongSignerPk) public {
        vm.assume(
            wrongSignerPk != yieldMinterAuthorityPrivateKey && wrongSignerPk != 0 && wrongSignerPk < SECP256K1_ORDER
        );

        bytes memory wrongSignature = _createSignature(1_000_000_000_000, yieldMinter.nextNonce(), wrongSignerPk);

        vm.prank(yieldMinterManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PipelineYieldMinterV1.PipelineYieldMinterV1UnauthorizedSigner.selector, vm.addr(wrongSignerPk)
            )
        );
        yieldMinter.mintYield(1_000_000_000_000, wrongSignature);
    }

    function test_zeroAmountRevert() public {
        uint256 nonce = yieldMinter.nextNonce();
        bytes memory signature = _createSignature(0, nonce, yieldMinterAuthorityPrivateKey);

        vm.prank(yieldMinterManager);
        vm.expectRevert(abi.encodeWithSelector(PipelineYieldMinterV1.PipelineYieldMinterV1ZeroAmount.selector));
        yieldMinter.mintYield(0, signature);
    }

    function _createSignature(uint256 yieldAmount, uint256 nonce, uint256 privateKey)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 structHash = keccak256(abi.encode(yieldMinter.YIELD_MINT_TYPEHASH(), yieldAmount, nonce));

        bytes32 domainSeparator = yieldMinter.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
