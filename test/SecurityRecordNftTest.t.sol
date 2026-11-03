// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ISecurityRecordNft} from "../src/interfaces/ISecurityRecordNft.sol";
import {PipelineSecurityRecordNft} from "../src/PipelineSecurityRecordNft.sol";

import {PipelineTestSetUp} from "./PipelineTestSetUp.t.sol";

contract SecurityRecordNftTest is PipelineTestSetUp {
    function test_securityRegistryMintsAndBurns() public {
        address holder = makeAddr("holder");

        vm.expectEmit(address(securityRecordNft));
        emit IERC721.Transfer(address(0), holder, 7);

        vm.prank(address(securityRegistry));
        securityRecordNft.mint(holder, 7, _details());
        assertEq(securityRecordNft.ownerOf(7), holder);
        assertEq(securityRecordNft.balanceOf(holder), 1);

        vm.expectEmit(address(securityRecordNft));
        emit IERC721.Transfer(holder, address(0), 7);

        vm.prank(address(securityRegistry));
        securityRecordNft.burn(7);
        assertEq(securityRecordNft.balanceOf(holder), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 7));
        securityRecordNft.ownerOf(7);
    }

    function testFuzz_onlySecurityRegistryMintsAndBurns(address caller) public {
        vm.assume(caller != address(securityRegistry));

        vm.prank(address(securityRegistry));
        securityRecordNft.mint(makeAddr("holder"), 7, _details());

        vm.startPrank(caller);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftOnlySecurityRegistry.selector);
        securityRecordNft.mint(caller, 8, _details());
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftOnlySecurityRegistry.selector);
        securityRecordNft.burn(7);
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftOnlySecurityRegistry.selector);
        securityRecordNft.addEvidence(7, ISecurityRecordNft.DocKind.Other, bytes32(0));
        vm.stopPrank();
    }

    function test_mintRejectsTooManyDocs() public {
        ISecurityRecordNft.RecordDetails memory newDetails = _details();
        newDetails.docs = new ISecurityRecordNft.Doc[](securityRecordNft.MAX_DOCS_PER_RECORD() + 1);

        vm.prank(address(securityRegistry));
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftTooManyDocs.selector);
        securityRecordNft.mint(makeAddr("holder"), 7, newDetails);
    }

    function test_setSecurityRegistry() public {
        address newSecurityRegistry = makeAddr("newSecurityRegistry");

        vm.expectEmit(address(securityRecordNft));
        emit PipelineSecurityRecordNft.SecurityRegistrySet(newSecurityRegistry);

        vm.startPrank(admin);
        securityRecordNft.setSecurityRegistry(newSecurityRegistry);
        assertEq(securityRecordNft.securityRegistry(), newSecurityRegistry);

        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftZeroAddress.selector);
        securityRecordNft.setSecurityRegistry(address(0));
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftSameValue.selector);
        securityRecordNft.setSecurityRegistry(newSecurityRegistry);
        vm.stopPrank();

        vm.prank(address(securityRegistry));
        vm.expectRevert(PipelineSecurityRecordNft.SecurityRecordNftOnlySecurityRegistry.selector);
        securityRecordNft.mint(admin, 1, _details());
    }

    function test_upgraderUpgrades() public {
        PipelineSecurityRecordNft newImplementation = new PipelineSecurityRecordNft();

        vm.prank(upgrader);
        UUPSUpgradeable(address(securityRecordNft)).upgradeToAndCall(address(newImplementation), "");

        bytes32 implementation = vm.load(address(securityRecordNft), ERC1967Utils.IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(implementation))), address(newImplementation));
        assertEq(securityRecordNft.securityRegistry(), address(securityRegistry));
    }

    function _details() private pure returns (ISecurityRecordNft.RecordDetails memory newDetails) {
        newDetails.commodity = "Copper cathodes";
    }
}
