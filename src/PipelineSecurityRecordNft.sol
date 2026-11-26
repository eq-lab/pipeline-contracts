// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.34;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ISecurityRecordNft} from "./interfaces/ISecurityRecordNft.sol";
import {ISecurityRegistry} from "./interfaces/ISecurityRegistry.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract PipelineSecurityRecordNft is UUPSUpgradeable, AccessManagedUpgradeable, ERC721Upgradeable, ISecurityRecordNft {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_DOCS_PER_RECORD = 16;
    uint256 public constant MAX_INSPECTIONS_PER_RECORD = 64;
    uint256 private constant BPS_ONE = 10_000;

    event SecurityRegistrySet(address securityRegistry);
    event DocAdded(uint256 indexed loanId, uint256 indexed recordId, DocKind kind, bytes32 hash);
    event InspectionRecorded(
        uint256 indexed loanId,
        uint256 indexed recordId,
        uint256 indexed inspectionId,
        uint256 lotId,
        address inspector,
        InspectionKind kind
    );
    event InspectionApproved(
        uint256 indexed loanId,
        uint256 indexed recordId,
        uint256 indexed inspectionId,
        address approvedBy,
        int32 varianceReferenceBps,
        int32 variancePreviousBps,
        int32 varianceGradeBps,
        bool outOfTolerance
    );
    event RecordFlagged(uint256 indexed loanId, uint256 indexed recordId, uint256 inspectionId);
    event InspectorsSet(address[] inspectors);

    error SecurityRecordNftOnlySecurityRegistry();
    error SecurityRecordNftNonTransferable();
    error SecurityRecordNftZeroAddress();
    error SecurityRecordNftSameValue();
    error SecurityRecordNftTooManyDocs();
    error SecurityRecordNftNonExistentInspection();
    error SecurityRecordNftNotGoodsRecord();
    error SecurityRecordNftWrongRecordStatus();
    error SecurityRecordNftNotInspector();
    error SecurityRecordNftInvalidInspectionDate();
    error SecurityRecordNftTooManyInspections();
    error SecurityRecordNftAlreadyApproved();
    error SecurityRecordNftSameOperator();
    error SecurityRecordNftDirectCallOnly();

    /// @custom:storage-location erc7201:pipeline.storage.SecurityRecordNft
    struct SecurityRecordNftStorage {
        ISecurityRegistry securityRegistry;
        mapping(uint256 recordId => RecordDetails) details;
        uint256 inspectionCount;
        EnumerableSet.AddressSet inspectors;
        mapping(uint256 inspectionId => Inspection) inspections;
        mapping(uint256 recordId => uint256[]) recordInspections;
    }

    // keccak256(abi.encode(uint256(keccak256("pipeline.storage.SecurityRecordNft")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SecurityRecordNftStorageLocation =
        0x8c39f9119d499504a2753ca3666978185c9ed0fdcbc9244b0e34cd89c5ba4200;

    function _getSecurityRecordNftStorage() private pure returns (SecurityRecordNftStorage storage $) {
        assembly {
            $.slot := SecurityRecordNftStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address authority) external initializer {
        __AccessManaged_init(authority);
        __ERC721_init("Pipeline Security Registry", "PLSR");
    }

    function mint(address to, uint256 recordId, RecordDetails calldata newDetails) external {
        _onlySecurityRegistry();
        if (newDetails.docs.length > MAX_DOCS_PER_RECORD) revert SecurityRecordNftTooManyDocs();

        _getSecurityRecordNftStorage().details[recordId] = newDetails;
        _mint(to, recordId);
    }

    function burn(uint256 recordId) external {
        _onlySecurityRegistry();
        _burn(recordId);
    }

    function addEvidence(uint256 recordId, DocKind kind, bytes32 hash) external {
        _onlySecurityRegistry();
        _getSecurityRecordNftStorage().details[recordId].docs.push(Doc({kind: kind, hash: hash}));
    }

    function addDoc(uint256 recordId, DocKind kind, bytes32 hash) external restricted {
        uint256 loanId = _context(recordId).loanId;

        Doc[] storage docs = _getSecurityRecordNftStorage().details[recordId].docs;
        if (docs.length >= MAX_DOCS_PER_RECORD) revert SecurityRecordNftTooManyDocs();
        docs.push(Doc({kind: kind, hash: hash}));

        emit DocAdded(loanId, recordId, kind, hash);
        _checkCoverage(loanId);
    }

    function recordInspection(uint256 recordId, NewInspection calldata newInspection)
        external
        restricted
        returns (uint256 inspectionId)
    {
        _requireDirectCall();
        SecurityRecordNftStorage storage $ = _getSecurityRecordNftStorage();
        ISecurityRegistry.InspectionContext memory context = _context(recordId);
        _requireCanInspect($, context, newInspection);

        uint256[] storage inspectionIds = $.recordInspections[recordId];
        if (inspectionIds.length >= MAX_INSPECTIONS_PER_RECORD) revert SecurityRecordNftTooManyInspections();
        inspectionId = ++$.inspectionCount;
        inspectionIds.push(inspectionId);

        Inspection storage inspectionData = $.inspections[inspectionId];
        inspectionData.inspectionId = inspectionId;
        inspectionData.recordId = recordId;
        inspectionData.lotId = context.lotId;
        inspectionData.inspector = newInspection.inspector;
        inspectionData.kind = newInspection.kind;
        inspectionData.inspectedAt = newInspection.inspectedAt;
        inspectionData.enteredBy = msg.sender;
        inspectionData.enteredAt = uint64(block.timestamp);
        inspectionData.quantity = newInspection.quantity;
        inspectionData.grade = newInspection.grade;
        inspectionData.siteHash = newInspection.siteHash;
        inspectionData.certificateHash = newInspection.certificateHash;
        inspectionData.region = newInspection.region;
        inspectionData.certificateNo = newInspection.certificateNo;

        emit InspectionRecorded(
            context.loanId, recordId, inspectionId, context.lotId, newInspection.inspector, newInspection.kind
        );
        _checkCoverage(context.loanId);
    }

    function approveInspection(uint256 inspectionId) external restricted {
        _requireDirectCall();
        SecurityRecordNftStorage storage $ = _getSecurityRecordNftStorage();
        Inspection storage inspectionData = _existingInspection($, inspectionId);
        if (inspectionData.approvedBy != address(0)) revert SecurityRecordNftAlreadyApproved();
        if (inspectionData.enteredBy == msg.sender) revert SecurityRecordNftSameOperator();

        uint256 recordId = inspectionData.recordId;
        ISecurityRegistry.InspectionContext memory context = _context(recordId);
        ISecurityRegistry.LatestInspection memory latest = $.securityRegistry.latestInspection(context.lotId);

        uint256 quantity = inspectionData.quantity;
        uint64 inspectedAt = inspectionData.inspectedAt;
        (int32 varianceReferenceBps, int32 varianceGradeBps) = _referenceVariances(inspectionData, context);
        int32 variancePreviousBps;
        bool becameLatest;
        if (inspectionData.kind != InspectionKind.SamplingAssay) {
            bool hasLatest = latest.inspectionId != 0;
            if (hasLatest) variancePreviousBps = _varianceBps(quantity, latest.quantity);
            becameLatest = !hasLatest || inspectedAt >= latest.inspectedAt;
        }

        inspectionData.approvedBy = msg.sender;
        inspectionData.approvedAt = uint64(block.timestamp);
        inspectionData.varianceReferenceBps = varianceReferenceBps;
        inspectionData.variancePreviousBps = variancePreviousBps;
        inspectionData.varianceGradeBps = varianceGradeBps;

        bool outOfTolerance = _isOutOfTolerance(context, varianceReferenceBps, variancePreviousBps, varianceGradeBps);

        emit InspectionApproved(
            context.loanId,
            recordId,
            inspectionId,
            msg.sender,
            varianceReferenceBps,
            variancePreviousBps,
            varianceGradeBps,
            outOfTolerance
        );

        ISecurityRegistry.RecordStatus status = context.status;
        bool standsIn =
            status == ISecurityRegistry.RecordStatus.Released || status == ISecurityRegistry.RecordStatus.Enforced;
        bool flagged = outOfTolerance && !standsIn;
        if (flagged) emit RecordFlagged(context.loanId, recordId, inspectionId);
        uint256 countedRecordId;
        if (becameLatest || standsIn) countedRecordId = _flagCountedRecord(inspectionData, context, standsIn);

        $.securityRegistry
            .applyInspection(recordId, inspectionId, inspectedAt, quantity, becameLatest, flagged, countedRecordId);
    }

    function setInspectors(address[] calldata newInspectors) external restricted {
        SecurityRecordNftStorage storage $ = _getSecurityRecordNftStorage();
        if (PausableUpgradeable(address($.securityRegistry)).paused()) revert PausableUpgradeable.EnforcedPause();

        EnumerableSet.AddressSet storage panel = $.inspectors;
        panel.clear();
        for (uint256 i; i < newInspectors.length; ++i) {
            panel.add(newInspectors[i]);
        }

        emit InspectorsSet(newInspectors);
    }

    function setSecurityRegistry(address newSecurityRegistry) external restricted {
        if (newSecurityRegistry == address(0)) revert SecurityRecordNftZeroAddress();

        SecurityRecordNftStorage storage $ = _getSecurityRecordNftStorage();
        if (address($.securityRegistry) == newSecurityRegistry) revert SecurityRecordNftSameValue();
        $.securityRegistry = ISecurityRegistry(newSecurityRegistry);

        emit SecurityRegistrySet(newSecurityRegistry);
    }

    function securityRegistry() external view returns (address) {
        return address(_getSecurityRecordNftStorage().securityRegistry);
    }

    function details(uint256 recordId) external view returns (RecordDetails memory) {
        _requireExistingRecord(recordId);
        return _getSecurityRecordNftStorage().details[recordId];
    }

    function measured(uint256 inspectionId)
        external
        view
        returns (bool measuresQuantity, uint256 quantity, uint256 grade)
    {
        Inspection storage inspectionData = _getSecurityRecordNftStorage().inspections[inspectionId];
        return (inspectionData.kind != InspectionKind.SamplingAssay, inspectionData.quantity, inspectionData.grade);
    }

    function inspection(uint256 inspectionId) external view returns (Inspection memory) {
        return _existingInspection(_getSecurityRecordNftStorage(), inspectionId);
    }

    function inspections(uint256 recordId) external view returns (Inspection[] memory result) {
        SecurityRecordNftStorage storage $ = _getSecurityRecordNftStorage();
        uint256[] storage inspectionIds = $.recordInspections[recordId];

        result = new Inspection[](inspectionIds.length);
        for (uint256 i; i < inspectionIds.length; ++i) {
            result[i] = $.inspections[inspectionIds[i]];
        }
    }

    function inspectors() external view returns (address[] memory) {
        return _getSecurityRecordNftStorage().inspectors.values();
    }

    function approve(address, uint256) public pure override {
        revert SecurityRecordNftNonTransferable();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert SecurityRecordNftNonTransferable();
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (to != address(0) && _ownerOf(tokenId) != address(0)) revert SecurityRecordNftNonTransferable();
        return super._update(to, tokenId, auth);
    }

    function _checkCoverage(uint256 loanId) private {
        _getSecurityRecordNftStorage().securityRegistry.checkCoverage(loanId);
    }

    function _context(uint256 recordId) private view returns (ISecurityRegistry.InspectionContext memory) {
        return _getSecurityRecordNftStorage().securityRegistry.inspectionContext(recordId);
    }

    function _flagCountedRecord(
        Inspection storage inspectionData,
        ISecurityRegistry.InspectionContext memory context,
        bool standsIn
    ) private returns (uint256) {
        uint256 countedRecordId = context.countedRecordId;
        if (countedRecordId == 0 || countedRecordId == inspectionData.recordId) return 0;

        ISecurityRegistry.InspectionContext memory counted = _context(countedRecordId);
        if (!counted.goods) return 0;

        (int32 referenceBps, int32 gradeBps) = _referenceVariances(inspectionData, counted);
        if (!standsIn) gradeBps = 0;
        if (!_isOutOfTolerance(context, referenceBps, inspectionData.variancePreviousBps, gradeBps)) return 0;

        emit RecordFlagged(context.loanId, countedRecordId, inspectionData.inspectionId);
        return countedRecordId;
    }

    function _requireExistingRecord(uint256 recordId) private view {
        _context(recordId);
    }

    function _requireCanInspect(
        SecurityRecordNftStorage storage $,
        ISecurityRegistry.InspectionContext memory context,
        NewInspection calldata newInspection
    ) private view {
        if (!context.goods) {
            revert SecurityRecordNftNotGoodsRecord();
        }

        ISecurityRegistry.RecordStatus status = context.status;
        if (
            status != ISecurityRegistry.RecordStatus.PendingPerfection
                && status != ISecurityRegistry.RecordStatus.Active
        ) {
            revert SecurityRecordNftWrongRecordStatus();
        }
        if (!$.inspectors.contains(newInspection.inspector)) revert SecurityRecordNftNotInspector();
        if (newInspection.inspectedAt > block.timestamp) revert SecurityRecordNftInvalidInspectionDate();
    }

    function _requireDirectCall() private view {
        if (msg.sender == authority()) revert SecurityRecordNftDirectCallOnly();
    }

    function _existingInspection(SecurityRecordNftStorage storage $, uint256 inspectionId)
        private
        view
        returns (Inspection storage)
    {
        if (inspectionId == 0 || inspectionId > $.inspectionCount) revert SecurityRecordNftNonExistentInspection();
        return $.inspections[inspectionId];
    }

    function _onlySecurityRegistry() private view {
        if (msg.sender != address(_getSecurityRecordNftStorage().securityRegistry)) {
            revert SecurityRecordNftOnlySecurityRegistry();
        }
    }

    function _referenceVariances(Inspection storage inspectionData, ISecurityRegistry.InspectionContext memory context)
        private
        view
        returns (int32 quantityBps, int32 gradeBps)
    {
        if (inspectionData.kind != InspectionKind.SamplingAssay) {
            quantityBps = _varianceBps(inspectionData.quantity, context.referenceQuantity);
        }
        uint256 grade = inspectionData.grade;
        if (grade != 0 && context.referenceGrade != 0) gradeBps = _varianceBps(grade, context.referenceGrade);
    }

    function _isOutOfTolerance(
        ISecurityRegistry.InspectionContext memory context,
        int32 referenceBps,
        int32 previousBps,
        int32 gradeBps
    ) private pure returns (bool) {
        return SignedMath.abs(referenceBps) > context.toleranceBps || SignedMath.abs(previousBps) > context.toleranceBps
            || SignedMath.abs(gradeBps) > context.gradeToleranceBps;
    }

    function _varianceBps(uint256 found, uint256 base) private pure returns (int32) {
        if (base == 0) return 0;

        uint256 difference = found > base ? found - base : base - found;
        uint256 maxBps = uint256(uint32(type(int32).max));
        uint256 bps = difference / base >= maxBps
            ? maxBps
            : Math.min((Math.mulDiv(difference, 2 * BPS_ONE, base) + 1) / 2, maxBps);
        return found < base ? -int32(uint32(bps)) : int32(uint32(bps));
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
