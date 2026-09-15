# MOUNTAIN MINING PROTOCOL — ARCHITECTURE REVIEW

## 1) System architecture
- `MountainToken`: fixed-supply ERC-20 (1,000,000,000 MMP, 18 decimals, no mint after initialization).
- `MiningPass`: ERC-721 with immutable class caps, fixed powers, and canonical mining position state.
- `MiningMinter`: bounded Merkle-based airdrop/early access claim gateway.
- `MysteryBoxSale`: public sale and randomness request/fulfillment flow.
- `MiningVault`: sole MMP reward reserve and reward calculator/enforcer.
- `MiningEngine`: minimal orchestrator for lifecycle calls only.

## 2) Contract responsibilities
- `MountainToken`: mints full fixed supply once to `MiningVault` at deployment; no future mint path.
- `MiningPass`: enforce total supply, per-class supply, custody lock while mining, and miner/start/power state.
- `MiningMinter`: enforce immutable Merkle roots, one-time claim usage, per-wallet allocation bounds.
- `MysteryBoxSale`: accept purchase, enqueue class assignment via verifiable randomness, mint only if class cap remains.
- `MiningVault`: computes rewards from authoritative `MiningPass` position data, clamps elapsed time to 20 years, and enforces global emission cap.
- `MiningEngine`: deterministic calculator/orchestrator; validates caller is stored miner, calls vault payout, then releases NFT via `MiningPass`.
- `MiningPass` mining position includes a monotonic per-token `sessionId`; `MiningVault` marks claimed session IDs to harden session replay protection.

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
- No approvals to `MiningEngine`; engine cannot pull NFTs.

## 10) Claim atomicity model
- `claimAndRelease(tokenId)` flow: verify active position/miner -> vault computes and reserves reward -> release NFT to stored miner -> vault transfers reserved MMP to stored miner.
- Any failure in payout or release reverts whole transaction.
- No user-supplied recipient parameters for payout or release.

## 11) Deployment dependencies
- Avoid circular dependencies via deterministic sequencing and immutable constructor wiring.
- Token supply destination and vault trust anchors are fixed at deployment.
- If deterministic addresses are required, use documented CREATE2 salts and precomputed addresses.

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
