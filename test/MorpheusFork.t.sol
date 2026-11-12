// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

/// @notice Shared fork-test base for the Morpheus (mor.org) VERIFY phase.
/// @dev Fork: Base mainnet, pinned block 56101591 (2026-11-11 15:24:53 UTC).
///      All tests are fork-only. No mainnet transactions, no real keys.
///      Provider/user/attacker keys below are fresh Foundry test keys
///      (vm.addr / vm.sign); they control nothing on mainnet.
contract MorpheusForkTest is Test {
    uint256 internal constant FORK_BLOCK = 56101591;

    address internal constant DIAMOND = 0x6aBE1d282f72B474E54527D93b979A4f64d3030a;
    address internal constant MOR = 0x7431aDa8a591C955a994a21710752EF9b882b8e3;
    address internal constant BUILDERS_V4 = 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9;
    address internal constant BUILDERS_TREASURY = 0x9eba628581896ce086cb8f1A513ea6097A8FC561;
    address internal constant BUILDERS_REWARD_POOL = 0xDC99a8596e395E52aba2BD08C623E1e428Dc3980;

    IERC20 internal constant MOR_TOKEN = IERC20(MOR);

    // Fresh, PoC-controlled keys (test-only, never mainnet keys).
    uint256 internal constant PROVIDER_KEY = 0xA11CE; // 0xa11ce
    uint256 internal constant VICTIM_KEY = 0xB0B; // 0xb0b
    uint256 internal constant ATTACKER_KEY = 0xA77A; // 0xa77a

    address internal provider = vm.addr(PROVIDER_KEY);
    address internal victim = vm.addr(VICTIM_KEY);
    address internal attacker = vm.addr(ATTACKER_KEY);

    function setUpFork() internal {
        vm.createSelectFork("base", FORK_BLOCK);
    }

    /// @dev Fund an address with MOR on the fork (forge-std `deal` writes
    ///      the ERC20 balance slot; falls back to nothing — caller must check).
    function fundMOR(address to, uint256 amount) internal {
        deal(MOR, to, amount);
    }

    /// @dev Build a provider approval exactly as the production provider node
    ///      does (Go: abi.encode(bidId, chainId, userAddr, uint128 timestamp),
    ///      timestamp in MILLISECONDS via UnixMilli()).
    function buildApproval(bytes32 bidId, address user, uint128 timestamp) internal pure returns (bytes memory) {
        return abi.encode(bidId, uint256(8453), user, timestamp);
    }

    /// @dev Sign an approval the way the provider node does:
    ///      EIP-191 personal-sign of keccak256(approval)
    ///      (Go SignEthMessageV2 == keccak256("\x19Ethereum Signed Message:\n32"
    ///      ++ keccak256(approval)), signed; v adjusted to 27/28 by vm.sign).
    function signApproval(uint256 privKey, bytes memory approval) internal returns (bytes memory sig) {
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(approval)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    /// @dev Register a provider + model + bid on the fork, all with the
    ///      PoC-controlled provider key. Returns the bidId.
    ///      pricePerSecond must be within [1e10, 1e16] wei/s.
    function setupProviderBid(uint256 pricePerSecond) internal returns (bytes32 bidId) {
        // Fund the provider with MOR for stakes + bid fee.
        fundMOR(provider, 100 ether);
        vm.startPrank(provider);
        MOR_TOKEN.approve(DIAMOND, type(uint256).max);
        // providerRegister(provider, amount=0.2 MOR min stake, endpoint)
        IDiamond(DIAMOND).providerRegister(provider, 0.2 ether, "https://poc.example");
        // modelRegister(owner, baseModelId, ipfsCID, fee, amount=0.1 MOR min stake, name, tags)
        bytes32 baseModelId = keccak256("poc-model");
        bytes32 modelId = IDiamond(DIAMOND).getModelId(provider, baseModelId);
        string[] memory tags = new string[](0);
        IDiamond(DIAMOND).modelRegister(provider, baseModelId, bytes32(0), 0, 0.1 ether, "poc-model", tags);
        // postModelBid(provider, modelId, pricePerSecond) — pulls 0.3 MOR bid fee
        bidId = IDiamond(DIAMOND).postModelBid(provider, modelId, pricePerSecond);
        vm.stopPrank();
    }
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
}

interface IDiamond {
    function providerRegister(address, uint256, string calldata) external;
    function modelRegister(address, bytes32, bytes32, uint256, uint256, string calldata, string[] calldata) external;
    function getModelId(address, bytes32) external pure returns (bytes32);
    function postModelBid(address, bytes32, uint256) external returns (bytes32);
    function openSession(address, uint256, bool, bytes calldata, bytes calldata) external returns (bytes32);
    function closeSession(bytes calldata, bytes calldata) external;
    function getFundingAccount() external view returns (address);
    function getBid(bytes32) external view returns (address provider, bytes32 modelId, uint256 pricePerSecond, uint256 nonce, uint128 createdAt, uint128 deletedAt);
    function isBidActive(bytes32) external view returns (bool);
    function stakeToStipend(uint256, uint128) external view returns (uint256);
    function getSessionEnd(uint256, uint256, uint128) external view returns (uint128);
    function getMaxSessionDuration() external view returns (uint128);
    function getComputeBalance(uint128) external view returns (uint256);
    function totalMORSupply(uint128) external view returns (uint256);
}
