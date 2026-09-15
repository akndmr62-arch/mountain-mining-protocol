# MOUNTAIN MINING PROTOCOL — ARCHITECTURE REVIEW

## 1) System architecture
- `MountainToken`: fixed-supply ERC-20 (1,000,000,000 MMP, 18 decimals, no mint after initialization).
- `MiningPass`: ERC-721 with immutable class caps, fixed powers, and canonical mining position state.
- `MysteryBoxSale`: public sale and randomness request/fulfillment flow.
- `MiningVault`: sole MMP reward reserve, reward calculator/enforcer, and CLAIM orchestrator — there is no separate `MiningEngine` or `MiningMinter`; MiningVault calls MiningPass directly.
- Airdrop/early-access `MiningPass` issuance (unrelated to MMP token economics) is authorized via `MiningPass.passDistributor`, a narrowly scoped address bound to immutable Merkle roots and per-wallet allocation bounds; it never touches MMP.

## 2) Contract responsibilities
- `MountainToken`: mint full fixed supply once to `initialHolder` at deployment; a deployment script then performs one ordinary ERC20 transfer of that full balance to `MiningVault`; no future mint path.
- `MiningPass`: enforce total supply, per-class supply, custody lock while mining, and miner/start/power state; releases NFTs only when called by `MiningVault`.
- `MysteryBoxSale`: accept purchase, enqueue class assignment via verifiable randomness, mint only if class cap remains.
- `MiningVault`: compute rewards from authoritative on-chain MiningPass position data, enforce the emission cap, transfer MMP from its own pre-funded balance to the recorded miner, and call `MiningPass.releaseFromMining` for that same miner — all within one atomic `claimAndRelease` call. It never mints and never accepts a caller-supplied reward, power, start time, or recipient.

## 3) Trust assumptions
- Base chain consensus and timestamp progression are honest within normal blockchain assumptions.
- Chainlink VRF (or equivalent Base-supported verifiable randomness provider) remains available and honest.
- OpenZeppelin 5.x primitives are used as-audited without local source modifications.

## 4) Privileged operations
- No mutable admin powers that alter supply caps, mining power table, reward constants, payout routing, or custody rules.
- No owner/admin withdrawal from vault.
- No root updates post-deployment for airdrop/early-access claims.

## 5) Attack surfaces
- Signature authorization entrypoints (EOA + ERC-1271 paths).
- ERC-721 transfer/approval functions under lock conditions.
- Permissionless `claimAndRelease` execution.
- VRF request/fulfillment and retry/liveness mechanism.
- External token/NFT interactions and callback hooks.

## 6) Reentrancy boundaries
- Mining start, claim, vault payout, NFT release, and VRF callback handlers are all non-reentrant boundaries.
- Apply checks-effects-interactions so state is finalized before external calls.
- Avoid nested `nonReentrant` cross-calls that deadlock OZ guard.

## 7) Signature replay model
- EIP-712 typed data: `{miner, tokenId, nonce, deadline}`.
- Domain separator binds `{name, version, chainId, verifyingContract}`.
- Nonce is per-token (or per-position) monotonic and consumed atomically on start.
- ERC-1271 validation must require magic value and reject malformed return data.

## 8) Randomness model
- Public sale assigns classes only from verifiable randomness outputs.
- Buyer and admin cannot choose class; mapping from random word to class bucket is fixed and immutable.
- Retry/liveness must never request a fresh random outcome to replace an unfavorable fulfilled result.
- Inventory accounting must prevent over-mint and minimize bias from depleted classes.

## 9) Custody model
- NFT moves to `MiningPass` internal custody at mining start.
- `ownerOf(tokenId)` is `MiningPass` while active.
- Canonical position getter returns `{miner,startTime,power,active,nonce/...}` for vault verification.
- No approvals to `MiningVault`; MiningVault never holds approvals and cannot pull NFTs by transferFrom — it only calls `MiningPass.releaseFromMining`, which is gated to `onlyMiningVault` and always pays out to the recorded miner.

## 10) Claim atomicity model
- `claimAndRelease(tokenId)` flow, executed entirely inside `MiningVault`: verify -> compute -> update emission/state -> transfer MMP from MiningVault's own balance to stored miner -> call `MiningPass.releaseFromMining(tokenId)` to release the NFT to the stored miner.
- Any failure in payout or release reverts the whole transaction.
- No user-supplied recipient parameters for payout or release; both come from `MiningPass`'s authoritative stored `miner`.

## 11) Deployment dependencies
- The MiningVault<->MiningPass constructor dependency is resolved with a one-time, non-privileged CREATE2 deployer: precompute MiningVault's CREATE2 address, deploy MiningPass with that precomputed address wired in as its immutable `miningVault`, then deploy MiningVault via CREATE2 with MiningPass's real address as an immutable constructor argument. A post-deploy address-match check reverts the entire deployment transaction if the deployed MiningVault address does not equal the precomputed one.
- No mutable setter, owner, or admin role is introduced to resolve this cycle.
- Token supply destination and vault trust anchors are fixed at deployment: `MountainToken` mints the full 1,000,000,000 MMP supply once, in its constructor, to `initialHolder`; a deployment script then performs a single ordinary ERC20 `transfer` of that full balance to `MiningVault`.

## 12) Unresolved issues
- Final VRF provider/interface selection on Base and callback gas budgeting.
- Exact inventory-sampling algorithm under class depletion.
- Final deployment graph (constructor args vs deterministic predeploy requirements).
- Event schema and forensic observability requirements.

## 13) Security invariants
- MMP emitted by vault never exceeds 1,000,000,000 ether.
- Mining reward uses floor division and 20-year elapsed clamp.
- Active mining position implies NFT custody by `MiningPass`.
- Claim always pays and releases to stored miner only.
- Signature must be valid for exact miner/token/nonce/deadline/domain.
- Class and total NFT caps can never be exceeded.
