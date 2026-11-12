# H-BLD-01 — VERIFY Evidence

- **Hypothesis:** Permissionless `createSubnet` lets an unprivileged attacker self-appoint `claimAdmin` under a victim's `admin` name; `claimAdmin` alone can direct the whole subnet's pending rewards to any address.
- **Target:** BuildersV4 `0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9` on Base (Appendix A, ERC1967 proxy; impl `0x18faef315b40a6d9cf49628f1133b1aa507513b0`, Sourcify exact_match).
- **Fork:** Base block **56101591**, RPC `https://mainnet.base.org` (default in `foundry.toml`; worked first try, no fallback needed, no rate-limiting encountered).
- **PoC:** `verify/test/HBLD01.t.sol` (contract `HBLD01Test`, 2 tests).
- **Date:** 2026-11-12 (verify run; fork block pinned 2026-11-11).
- **Verdict: VERIFIED** — mechanism proven end-to-end on deployed bytecode. Two honest caveats travel with the verdict: (a) the impact bound is **conditional on attracted stake** (the PoC proves what happens *given* a deposit; it does not demonstrate a mechanism that draws a victim deposit); (b) dedup is **RELATED_BUT_DISTINCT** vs Trust TRST-H-2 / TRST-M-2 (see §6) — a triager could still see it as related, so a dedup re-check is required at submission time.

## 1. What the PoC does, step by step

`testAttackerSelfAppointsClaimAdminAndClaimsVictimRewards()`:

1. **Baseline reads at the pin.** System-wide pending `getCurrentSubnetsRewards()` = 87,657.287248152515519722 MOR; BuildersTreasuryV2 balance = 89,318.197106008198306031 MOR.
2. **Step 1 — permissionless creation.** The unprivileged attacker (`0xe8273784EF0CeDB342E7f389c18d7C888Ce01941`, `vm.addr(0xA77A)`, a fresh Foundry test key controlling nothing on mainnet) calls `createSubnet` with `admin` = the live "DRM3 Labs Corp." admin `0xC647d4080549603F8C779b9Dd28E53C62300aeA2` (a reputable third-party address taken from ANALYZE §1.3) and `claimAdmin` = attacker. Subnet name `"Morpheus Builders PoC Subnet HBLD01"` (fresh, no collision). Struct: `unusedStorage1_V4Update = 86_400`, `withdrawLockPeriodAfterDeposit = 604_800` (7 days), `unusedStorage2_V4Update = 0`, `minimalDeposit = 0.001 MOR`; metadata `("hbld01-poc-subnet", "PoC subnet", "https://example.com", "")`. Creation costs gas only (`subnetCreationFeeAmount = 0`, creation op fee = 0). `createSubnet` returns nothing, so the subnet id is derived via `getSubnetId(name)` = `0xd497283f9a2e5773ca54179c82841215e859e779d142db42b6eaee32a4acfbfb`. The test asserts the stored subnet reads back with `admin == 0xC647…aeA2`, `claimAdmin == attacker`, `minimalDeposit == 0.001 MOR`.
3. **Step 2 — victim deposit.** A victim staker (fresh address `vm.addr(0xB0B)`, different from the victim admin) is funded with 100,000 MOR via `deal`, approves BuildersV4, and deposits the full 100,000 MOR into the attacker's subnet. `usersData(victim, subnetId).deposited` and `subnetsData(subnetId).deposited` both read 100,000 MOR. This deposit is the "attracted stake": the test demonstrates what happens GIVEN a deposit into a subnet whose displayed `admin` the victim trusted. It does NOT invent a mechanism that draws the deposit.
4. **Step 3 — accrual.** `vm.warp(block.timestamp + 7 days)`. `getCurrentSubnetRewards(subnetId)` = **525.318357560826420976 MOR**.
5. **Step 4 — attacker claim.** Attacker (as `claimAdmin`) calls `claim(subnetId, attacker)`. Attacker MOR balance goes 0 → **525.318357560826420976 MOR** — exactly the pending read just before the claim. Subnet pending after the claim = **0** exactly.
6. **Step 5 — victim principal intact.** `usersData(victim, subnetId).deposited` is still 100,000 MOR after the claim. After warping +1 more day (lock expired), the victim withdraws the full 100,000 MOR and their balance is restored to exactly 100,000 MOR.
7. **Victim admin never acts.** By construction the test contains no `vm.prank` / `vm.sign` as `VICTIM_ADMIN` (0xC647…aeA2), owner, or multisig anywhere. The admin is a passive bystander whose address is merely named in the struct.

`testRandomAddressCannotClaim()` (control): same subnet + deposit + 7-day warp, then a random address (`0xBEEF`, neither admin nor claimAdmin) calls `claim` and reverts with `"BU: invalid caller"`. This proves the claim power is exactly the {admin, claimAdmin} set — and that the attacker holds it solely by self-appointment.

## 2. Exact forge output

Command (from `verify/`): `~/.foundry/bin/forge test --match-contract HBLD01Test -vvv`

```
Compiling 21 files with Solc 0.8.24
Solc 0.8.24 finished in 981.03ms
Compiler run successful with warnings:
Warning (2018): Function state mutability can be restricted to pure
  --> test/MorpheusFork.t.sol:52:5:
   |
52 |     function signApproval(uint256 privKey, bytes memory approval) internal returns (bytes memory sig) {
   |     ^ (Relevant source part starts here and spans across multiple lines).

Ran 2 tests for test/HBLD01.t.sol:HBLD01Test
[PASS] testAttackerSelfAppointsClaimAdminAndClaimsVictimRewards() (gas: 1525358)
Logs:
  system-wide pending MOR at pin: 87657287248152515519722
  Treasury MOR balance at pin: 89318197106008198306031
  subnet id: 0xd497283f9a2e5773ca54179c82841215e859e779d142db42b6eaee32a4acfbfb
  subnet admin (victim, never acts): 0xC647d4080549603F8C779b9Dd28E53C62300aeA2
  subnet claimAdmin (attacker): 0xe8273784EF0CeDB342E7f389c18d7C888Ce01941
  subnet pending MOR after 7 days: 525318357560826420976
  attacker MOR before claim: 0
  attacker MOR after claim: 525318357560826420976
  attacker gain (MOR): 525318357560826420976
  pending read just before claim (MOR): 525318357560826420976
  subnet pending MOR after claim: 0
  victim MOR after full withdraw: 100000000000000000000000

[PASS] testRandomAddressCannotClaim() (gas: 1022104)
Logs:
  subnet id: 0xd497283f9a2e5773ca54179c82841215e859e779d142db42b6eaee32a4acfbfb
  subnet admin (victim, never acts): 0xC647d4080549603F8C779b9Dd28E53C62300aeA2
  subnet claimAdmin (attacker): 0xe8273784EF0CeDB342E7f389c18d7C888Ce01941
  random caller claim reverted BU: invalid caller

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 4.01s (6.06s CPU time)

Ran 1 test suite in 4.03s (4.01s CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

(The only compiler warning is pre-existing in the shared base file `MorpheusFork.t.sol:52` — `signApproval` mutability — untouched by this work.)

Full suite (`forge test` from `verify/`): **7 passed, 0 failed, 0 skipped** — HBLD01 2 + HDIA01 2 + HDIA02 3. No existing test broke.

```
Ran 2 tests for test/HBLD01.t.sol:HBLD01Test
[PASS] testAttackerSelfAppointsClaimAdminAndClaimsVictimRewards() (gas: 1525358)
[PASS] testRandomAddressCannotClaim() (gas: 1022104)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.13s (6.38ms CPU time)

Ran 2 tests for test/HDIA01.t.sol:HDIA01Test
[PASS] testStolenApprovalFundingAccountLossAtClose() (gas: 2874832)
[PASS] testStolenApprovalOpensSessionForAttacker_VictimLockedOut() (gas: 2565376)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.34s (41.33ms CPU time)

Ran 3 tests for test/HDIA02.t.sol:HDIA02Test
[PASS] testApprovalMsTimestampNeverExpires_1Day() (gas: 2074954)
[PASS] testApprovalMsTimestampNeverExpires_365Days() (gas: 2074953)
[PASS] testApprovalSecondsTimestampExpires() (gas: 1584225)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 1.34s (42.15ms CPU time)

Ran 3 test suites in 1.35s (3.81s CPU time): 7 tests passed, 0 failed, 0 skipped (7 total tests)
```

## 3. Before/after balances (MOR, exact wei from the run)

| Quantity | Before | After |
| --- | --- | --- |
| Attacker MOR balance | 0 | 525.318357560826420976 |
| Subnet pending rewards (`getCurrentSubnetRewards`) | 525.318357560826420976 (read just before claim) | 0 |
| Victim staker recorded principal (`usersData.deposited`) | 100,000 (before claim) | 100,000 (after claim — unchanged) |
| Victim staker MOR balance | 0 (fully deposited) | 100,000 (after full withdraw, +1 day past lock) |
| System-wide pending (`getCurrentSubnetsRewards` at pin) | 87,657.287248152515519722 | — |
| BuildersTreasuryV2 MOR balance at pin | 89,318.197106008198306031 | — (claim of 525.32 MOR is well inside it) |
| BuildersV4 MOR balance / total deposited at pin | 2,946,079.67 | — |

Assertion used: `assertApproxEqAbs(attackerGain, pendingBeforeClaim, 0.01 ether)` — a 0.01 MOR tolerance to absorb any dust-scale rounding in the inlined cross-subnet split arithmetic. **Observed delta was exactly 0**: attacker gain == pending read, to the wei. Pending after claim was exactly 0 (same 0.01 MOR tolerance, observed delta 0).

## 4. Impact numbers (MOR only — USD unpriced; see §7)

**Demonstrated (this PoC, per subnet):** 100,000 MOR of attracted stake accrues **525.318357560826420976 MOR in 7 days** (≈ **75.0455 MOR/day**), all of which the attacker takes in a single `claim`. The victim's principal is untouched; only their accrued rewards are redirected.

**Observed vs ANALYZE estimate — discrepancy noted honestly:** ANALYZE's pro-rata estimate predicted ≈ 97 MOR/day for a 100,000 MOR stake (3.283% × ~2,859.21 MOR/day system emission), i.e. ≈ 657 MOR over 7 days. The fork measured **525.32 MOR over 7 days (≈ 75.05 MOR/day), ~20% below the pro-rata estimate**. The demonstrated figure governs: the inlined cross-subnet split does not pay the naive pro-rata share (consistent with ANALYZE open question OQ-2 — the split rule is inlined in V4 bytecode, not source-read). All bounds below use the **observed** rate, not the estimate.

**Per-day emission bound (observed):** ≈ 75.0455 MOR/day per 100,000 MOR of attracted stake. Linear 30-day extrapolation (not directly tested for 30 days): ≈ **2,251.37 MOR per 100,000 MOR stake per 30 days**. Scaling with stake is assumed linear (proportional to the subnet's share); only the 100,000 MOR point was measured. A 1,000,000 MOR attracted stake would, under linear scaling, accrue ≈ 750.46 MOR/day (≈ 22,513.7 MOR / 30 days) — untested, stated as scaling arithmetic only.

**Aggregate ceiling (hard caps, defensible):** no single claim can exceed the system-wide pending (**87,657.29 MOR** at the pin) and no claim can exceed the Treasury balance (**89,318.20 MOR** at the pin). The realistic bound is the formula above — it scales with the victim stake the attacker actually attracts.

**Repeatability:** the attacker can claim again as new rewards accrue, indefinitely, at gas cost only (creation was free; each claim is one transaction). The victim admin can in principle rescue the subnet via `editSubnet` to replace `claimAdmin` — but only if they learn the subnet exists; each claim before that is final (funds leave the Treasury to the attacker's receiver).

**What is NOT taken:** stakers' principal (up to 2,946,079.67 MOR held in V4) is not taken by this path — proven by the unchanged `usersData.deposited` and the full 100,000 MOR withdraw after the claim.

## 5. 10-point validation gate checklist

1. **Program rules read end to end — PASS.** Morpheus Bug Bounty Program v2, effective 2026-08-07 (scope.md): smart contracts only, Appendix A addresses only, deployed bytecode only, mandatory Foundry fork PoC asserting a quantified loss, one-page fixed template, report to devs@mor.org.
2. **In Scope rule shown — PASS.** BuildersV4 `0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9` on Base is an Appendix A address (Base — Builders). The PoC targets its deployed bytecode at fork block 56101591 through the listed proxy address.
3. **NOT Out of Scope / Exclusion shown — PASS.** Attacker is unprivileged (fresh test key, no role, no owner/admin/multisig prank, victim admin never acts). Not an admin-key/centralization claim; not MEV-only (the loss is rewards redirected from third-party stakers, not ordering priority); not griefing/DoS without loss (a quantified 525.32 MOR loss is demonstrated); not rounding/dust (525 MOR is material); not a third-party-protocol bug; not repo-only (proven against deployed bytecode). Known-issue caveat: see point 10 / §6 — RELATED_BUT_DISTINCT, not a clean pass on dedup certainty.
4. **All eligibility met — PASS (with one item owned by the operator).** Foundry fork PoC, one command (`forge test`), asserts the loss (attacker balance before/after + pending drained + principal intact), no privileged accounts, fork-only (no mainnet tx, no real keys, no funds moved on mainnet). Remaining eligibility item: the operator must personally run the PoC to a passing result before any submission (program §5) — not yet done.
5. **End-to-end trigger → process → real impact — PASS.** Trigger: unprivileged `createSubnet` naming victim admin + attacker claimAdmin (succeeds). Process: victim deposit → 7-day accrual → attacker `claim` pays full pending to attacker. Real impact: attacker +525.318357560826420976 MOR; subnet pending → 0; victim's accrued rewards are gone (their principal is intact and withdrawable — the loss is rewards, stated exactly).
6. **Live + reproducible — PASS.** Fork of deployed Base bytecode at pinned block 56101591; 2/2 HBLD01 tests pass; full suite 7/7; deterministic (no live RPC state beyond the pinned fork).
7. **Severity matches proven impact — PROGRAM'S CALL (no severity assigned here).** Demonstrated: 525.32 MOR per 100,000 MOR attracted stake per 7 days (≈ 75.05 MOR/day), repeatable, capped by system-wide pending 87,657.29 MOR / Treasury 89,318.20 MOR. Whether that is Low / Medium / High is for the program to decide from the demonstrated effect; this evidence assigns no severity.
8. **Public / broad impact — PASS WITH CONDITION.** The mechanism is permissionless and repeatable against any subnet the attacker creates, and any staker who deposits into such a subnet loses their accrued rewards to the attacker. The scale, however, is **conditional on attracted stake**: the PoC proves the loss given a deposit; it does not demonstrate that victims will in fact deposit (attraction via a reputable displayed `admin` name / name-squatting is a plausible precondition, not a proven one). The bound is therefore stated as conditional, per ANALYZE's own instruction.
9. **Checklist each point — PASS.** This section checks all ten points individually.
10. **Declare 'Valid & Eligible' only after all pass — DECLARED, WITH THE TWO STATED CONDITIONS.** Points 1–9 pass (point 7 by deferring severity to the program, point 8 with the attracted-stake condition). **Valid & Eligible**, conditional on: (a) the impact bound being stated as conditional on attracted stake in any report (no invented victim behaviour); (b) a dedup re-check at submission time, because the RELATED_BUT_DISTINCT label (TRST-H-2 / TRST-M-2) leaves room for a triager to see it as related (§6).

## 6. Dedup caveat (honest statement)

Per `analyze-dedup.md` §5, H-BLD-01 is **RELATED_BUT_DISTINCT** vs Trust TRST-H-2 ("An attacker could make anyone lose their pending rewards", High, Fixed) as primary, and TRST-M-2 ("Creation of subnets is vulnerable to frontrunning, disrupting the migration", Medium, Acknowledged) as adjacent. The distinction argued:

- **vs TRST-H-2 — different root cause, different code, different harm mechanism.** H-2's root is an early-return-zero bug in `getStakerRewards()` (a per-staker view) combined with `_updateStorage()` persisting the zeroed value, reachable via permissionless `collectPendingRewards()` double-call. That code is gone in V4: there is no `getStakerRewards`, no `collectPendingRewards`, and no per-staker `pendingRewards` field — V4 tracks rewards per subnet in `subnetsData` and pays the whole subnet pending in one `claim`. H-BLD-01's root is V4-only: the **new `claimAdmin` role** (no equivalent in V2/V3/`BuilderSubnets`) + permissionless `createSubnet` with no sender binding on `admin`/`claimAdmin` + a `claim` that pays the full subnet pending to an arbitrary receiver. H-2 *destroys* the victim's rewards (sets them to zero); H-BLD-01 *redirects* them to the attacker's receiver. The shared element is only the theme — "an attacker can make a staker lose their pending rewards".
- **vs TRST-M-2 — adjacent by precondition, different root cause and harm.** M-2's harm is migration disruption; V4 has no migration functions at all. Name-squatting/frontrunning is only one possible victim-attraction route — the core root (unbound `claimAdmin` + equal claim power) operates even without any name collision.
- **vs the public BuildersV4 subnet-lock PoC** — not a duplicate: that PoC's attacker is the subnet **admin** (a privileged role under the program's exclusion) raising the withdraw lock to freeze stakers' **principal**; H-BLD-01's attacker is the unprivileged `claimAdmin` taking **rewards**, with the admin as a non-consenting bystander. Different actor, different role, different asset.

**Caveat:** the shared theme with TRST-H-2 is real, and a triager could still treat the identical violated invariant ("a staker loses their pending rewards to an attacker") as the known issue. The RELATED_BUT_DISTINCT label is an argument, not a guarantee. Dedup must be re-checked at submission time against the program's then-current known-issue set.

## 7. What is still needed before any report

1. **Operator personally runs the PoC** (`forge test --match-contract HBLD01Test`, then `forge test`) to a passing result — program §5 requires personal verification; Muse's run does not substitute.
2. **MOR price at report time** — USD impact is deliberately unpriced here (MOR only). The report's IMPACT line needs tokens AND USD with a cited price source at time of writing.
3. **One-page report** in the program's exact §2.2 template (TARGET / INVARIANT / IMPACT / PRECONDITIONS / ATTACK / POC / FIX), with the PRECONDITIONS honestly stating the attracted-stake condition and the impact bound as conditional on it.
4. **Dedup re-check at submission time** (§6) — confirm no newer disclosure or earlier report covers the V4 `claimAdmin` root, and be ready for the triager to contest the TRST-H-2 distinction.
5. **PoC delivery as a public repo/gist link** (program §2.1.6) — the PoC currently lives only in this workspace; publishing is the operator's decision at submission time, not done here.
6. No submission, vendor contact, GitHub issue, or public disclosure has been made from this work.

## 8. Files

- `verify/test/HBLD01.t.sol` — Foundry PoC (contract `HBLD01Test`, 2 tests).
- `verify/hbld01-evidence.md` — this file.
- Shared base reused, unmodified: `verify/test/MorpheusFork.t.sol` (fork setup, MOR `deal`, test keys 0xA11CE / 0xB0B / 0xA77A). H-DIA-01/H-DIA-02 files untouched.

## 9. Notes / limitations

- **Grounding:** bytecode-inferred. BuildersV4 Solidity source text was not retrieved (Sourcify exact_match confirmed; only the ABI + bytecode were available). Every mechanism claim here was proven against the deployed bytecode on the fork, not assumed from repo source. The ABI used for the test interface was fetched from Sourcify for the verified implementation `0x18faef…` and matches the deployed selectors.
- **Observed accrual below the ANALYZE estimate** (§4): 525.32 MOR / 7 days vs ≈ 657 MOR predicted pro-rata. The demonstrated figure governs; the split rule (ANALYZE OQ-2) remains unreversed, but the view-vs-claim equality (exact, to the wei) shows the split is at least self-consistent.
- **Attraction precondition not demonstrated:** the PoC shows the loss given a deposit. Whether victims would deposit into an attacker-created subnet (reputable displayed admin, attractive name, competitive minimalDeposit/lock) is a behavioural precondition, honestly stated as conditional — not a proven fact.
- **Victim-admin rescue:** the named admin could call `editSubnet` to replace `claimAdmin` if they discover the subnet; the PoC does not test that path (it is a mitigation, not a refutation — claims already made are final).
- One compile note: the only warning is pre-existing in the shared base file; no warnings from `HBLD01.t.sol` itself.
