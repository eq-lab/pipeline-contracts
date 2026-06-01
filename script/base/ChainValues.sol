// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

contract ChainValues {
    uint256 constant MAINNET_CHAIN_ID = 1;
    uint256 constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant HOODI_CHAIN_ID = 560048;
    uint256 constant ANVIL_CHAIN_ID = 31337;

    error UnknownChainId(uint256 chainId);
    error UnknownChainValue(uint256 chainId, string valueName);

    mapping(uint256 chainId => string) chainNames;
    mapping(uint256 chainId => mapping(string valueName => bytes32)) values;

    constructor() {
        _loadChainNames();
        _loadHoodiValues();
        _loadAnvilValues();
    }

    function nameOf(uint256 chainId) internal view returns (string memory chainName) {
        chainName = chainNames[chainId];
        if (bytes(chainName).length == 0) revert UnknownChainId(chainId);
    }

    function valueOf(string memory valueName, bool zeroAllowed) internal view returns (bytes32 value) {
        value = values[block.chainid][valueName];
        if (!zeroAllowed && value == bytes32(0)) revert UnknownChainValue(block.chainid, valueName);
    }

    function _loadChainNames() private {
        chainNames[MAINNET_CHAIN_ID] = "mainnet";
        chainNames[SEPOLIA_CHAIN_ID] = "sepolia";
        chainNames[HOODI_CHAIN_ID] = "hoodi";
        chainNames[ANVIL_CHAIN_ID] = "anvil";
    }

    function _loadHoodiValues() private {
        values[HOODI_CHAIN_ID]["AccessManagerOwner"] =
            bytes32(uint256(uint160(0xFE1748f511583f6c9349f672593E6312BeDfcE40)));
        values[HOODI_CHAIN_ID]["Treasury"] = bytes32(uint256(uint160(0xFE1748f511583f6c9349f672593E6312BeDfcE40)));
        values[HOODI_CHAIN_ID]["Custodian"] = bytes32(uint256(uint160(0x0D5367AcD773339653858E73C2023199485FDe6c)));

        values[HOODI_CHAIN_ID]["USDC"] = bytes32(uint256(uint160(0xe198F1EEF83Dd613B874FC3c2D5BAf6C8a4A4597)));

        // =========== DepositManagerConfig ===========
        values[HOODI_CHAIN_ID]["DepositManager__MinDeposit"] = bytes32(uint256(1_000_000_000));
        values[HOODI_CHAIN_ID]["DepositManager__RateLimit__TxLimit"] = bytes32(uint256(5_000_000_000_000));
        values[HOODI_CHAIN_ID]["DepositManager__RateLimit__WindowLimit"] = bytes32(uint256(10_000_000_000_000));
        values[HOODI_CHAIN_ID]["DepositManager__RateLimit__Window"] = bytes32(uint256(86400));
        values[HOODI_CHAIN_ID]["DepositManager__RateLimit__Shift"] = bytes32(uint256(0));
        values[HOODI_CHAIN_ID]["DepositManager__Verifier"] =
            bytes32(uint256(uint160(0xd3b978148e1Ee61b528354f72b39451c46dCA57C)));

        values[HOODI_CHAIN_ID]["LoanRegistry__erc721Name"] = bytes32(bytes("LoanRegistryName"));
        values[HOODI_CHAIN_ID]["LoanRegistry__erc721Symbol"] = bytes32(bytes("LRS"));

        values[HOODI_CHAIN_ID]["WithdrawalQueue__TokenHolderMCP"] =
            bytes32(uint256(uint160(0x0D5367AcD773339653858E73C2023199485FDe6c)));
        values[HOODI_CHAIN_ID]["WithdrawalQueue__Verifier"] =
            bytes32(uint256(uint160(0xd3b978148e1Ee61b528354f72b39451c46dCA57C)));

        // =========== Roles ===========
        values[HOODI_CHAIN_ID]["DepositManagerAdmin"] =
            bytes32(uint256(uint160(0xFE1748f511583f6c9349f672593E6312BeDfcE40)));
        values[HOODI_CHAIN_ID]["DepositManagerAdmin__Delay"] = bytes32(uint256(0));

        values[HOODI_CHAIN_ID]["WithdrawalQueueAdmin"] =
            bytes32(uint256(uint160(0xFE1748f511583f6c9349f672593E6312BeDfcE40)));
        values[HOODI_CHAIN_ID]["DWithdrawalQueueAdmin__Delay"] = bytes32(uint256(0));

        values[HOODI_CHAIN_ID]["EmergencyRole"] = bytes32(uint256(uint160(0xFE1748f511583f6c9349f672593E6312BeDfcE40)));
        values[HOODI_CHAIN_ID]["EmergencyRole__Delay"] = bytes32(uint256(0));

        values[HOODI_CHAIN_ID]["LoanRegistryManager"] =
            bytes32(uint256(uint160(0xFE1748f511583f6c9349f672593E6312BeDfcE40)));
        values[HOODI_CHAIN_ID]["LoanRegistryManager__Delay"] = bytes32(uint256(0));

        values[HOODI_CHAIN_ID]["WhitelistManager"] =
            bytes32(uint256(uint160(0xd3b978148e1Ee61b528354f72b39451c46dCA57C)));
        values[HOODI_CHAIN_ID]["WhitelistManager__Delay"] = bytes32(uint256(0));

        values[HOODI_CHAIN_ID]["YieldMinterManager"] =
            bytes32(uint256(uint160(0xFE1748f511583f6c9349f672593E6312BeDfcE40)));
        values[HOODI_CHAIN_ID]["YieldMinterManager__Delay"] = bytes32(uint256(0));
    }

    function _loadAnvilValues() private {
        // Default anvil signers
        values[ANVIL_CHAIN_ID]["AccessManagerOwner"] =
            bytes32(uint256(uint160(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266)));
        values[ANVIL_CHAIN_ID]["Treasury"] = bytes32(uint256(uint160(0x70997970C51812dc3A010C7d01b50e0d17dc79C8)));
        values[ANVIL_CHAIN_ID]["Custodian"] = bytes32(uint256(uint160(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC)));

        values[ANVIL_CHAIN_ID]["USDC"] = bytes32(uint256(uint160(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)));

        // =========== DepositManagerConfig ===========
        values[ANVIL_CHAIN_ID]["DepositManager__MinDeposit"] = bytes32(uint256(1_000_000_000));
        values[ANVIL_CHAIN_ID]["DepositManager__RateLimit__TxLimit"] = bytes32(uint256(5_000_000_000_000));
        values[ANVIL_CHAIN_ID]["DepositManager__RateLimit__WindowLimit"] = bytes32(uint256(10_000_000_000_000));
        values[ANVIL_CHAIN_ID]["DepositManager__RateLimit__Window"] = bytes32(uint256(86400));
        values[ANVIL_CHAIN_ID]["DepositManager__RateLimit__Shift"] = bytes32(uint256(0));

        values[ANVIL_CHAIN_ID]["LoanRegistry__erc721Name"] = bytes32(bytes("LoanRegistryName"));
        values[ANVIL_CHAIN_ID]["LoanRegistry__erc721Symbol"] = bytes32(bytes("LRS"));
    }
}
