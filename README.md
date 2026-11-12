# H-BLD-01 PoC — BuildersV4 unbound claimAdmin

Foundry proof of concept for a Morpheus BuildersV4 finding: permissionless
`createSubnet` lets an unprivileged caller name any address as `admin` while
appointing itself `claimAdmin`, and `claimAdmin` alone can direct the whole
subnet's pending rewards to any address.

Target: BuildersV4 `0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9` on Base
(Appendix A, ERC1967 proxy; impl `0x18faef315b40a6d9cf49628f1133b1aa507513b0`).

## Run

```sh
forge test -vvv
```

Fork: Base mainnet, pinned block 56101591. RPC is `https://mainnet.base.org`
(see `[rpc_endpoints]` in `foundry.toml`). If it rate-limits, pass a
fallback explicitly:

```sh
forge test --fork-url https://base-rpc.publicnode.com --fork-block-number 56101591 -vvv
```

## What the test proves

`test/HBLD01.t.sol` (`HBLD01Test`, 2 tests):

1. `testAttackerSelfAppointsClaimAdminAndClaimsVictimRewards` — an
   unprivileged attacker creates a subnet naming the live "DRM3 Labs Corp."
   admin as `admin` and itself as `claimAdmin`; a victim deposits 100,000
   MOR; after 7 days the attacker claims 525.318357560826420976 MOR exactly
   (pending read just before the claim, delta 0 to the wei) while the
   victim's 100,000 MOR principal stays intact and withdrawable.
2. `testRandomAddressCannotClaim` (control) — a random address calling
   `claim` reverts with `"BU: invalid caller"`.

Fork only. No mainnet transactions, no real keys, no funds moved. Every key
in the tests is a fresh Foundry test key that controls nothing on mainnet.

## Files

- `test/HBLD01.t.sol` — the PoC.
- `test/MorpheusFork.t.sol` — shared base: fork setup and MOR funding via `deal`.
- `hbld01-evidence.md` — full evidence, balances, and the validation checklist.
