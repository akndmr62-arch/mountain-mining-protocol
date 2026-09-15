# SECURITY REVIEW (PRE-IMPLEMENTATION)

This document captures required architecture findings **before** production Solidity implementation.

## Remaining architectural conflicts
- VRF liveness/failure policy must avoid outcome bias when fulfillment is delayed or fails.
- Public-sale class allocation under depleted inventory requires a deterministic, bias-resistant mapping rule.

## Resolved architectural conflicts
- MiningVault<->MiningPass constructor wiring order (previously "must avoid circular dependencies without introducing mutable trust-boundary setters") is resolved via the one-time, non-privileged CREATE2 deployer pattern described in DEPLOYMENT.md and ARCHITECTURE_REVIEW.md §11; no mutable setter, owner, or admin role is introduced.
- The prior CLAIM description ("MiningEngine computes reward, MiningMinter mints MMP, then MiningPass releases the NFT") violated Part 22/26 (Engine must not calculate reward, determine recipient, or mint MMP; no future minting capability). `MiningEngine` and `MiningMinter` have been removed; `MiningVault` alone computes reward, enforces the emission cap, and transfers MMP from its own pre-funded balance, then calls `MiningPass.releaseFromMining` directly.

## Trust assumptions
- Base network consensus and timestamp progression follow normal blockchain assumptions.
- Verifiable randomness provider on Base (e.g., Chainlink VRF) is available and correct.
- OpenZeppelin Contracts 5.x pinned exact release is used without local behavioral modification.

## Privileged operations
- No privilege may mint arbitrary NFTs or MMP, alter class power/caps, alter mining rules, or redirect claims.
- No privilege may withdraw vault emissions, pause users, blacklist users, or upgrade contracts.
- Any operational sale-phase controls must be narrowly scoped and immutable where possible.

## Attack surfaces
- EIP-712 start-mining authorization (EOA + ERC-1271 paths).
- NFT custody start/lock/release lifecycle.
- Claim lifecycle and emission accounting boundaries.
- Randomness request/fulfillment path for mystery-box class assignment.
- Phase allocation enforcement (10k airdrop / 10k early / 80k public).

## Reentrancy boundaries
- Mining start path touching custody state.
- Claim path combining reward payout and NFT release.
- Randomness fulfillment callbacks that can trigger mint/state transitions.
- Any external token/NFT transfers must follow checks-effects-interactions and guarded boundaries.

## Signature replay surfaces
- Cross-chain or cross-contract replay if domain separation is incomplete.
- Nonce replay if nonce is not consumed atomically on successful authorization.
- Miner/token mismatch replay if signature payload omits strict `miner` and `tokenId` binding.
- Deadline bypass if expired signatures are not rejected.

## Randomness manipulation surfaces
- Buyer prediction or preselection of class before randomness finalization.
- Admin influence over mapping from random output to class.
- Re-request/retry policy that could replace unfavorable fulfilled outcomes.
- Inventory-edge manipulation when class caps are near exhaustion.

## Deployment risks
- Constructor dependency cycles that tempt unsafe mutable setter patterns. Resolved via a one-time, non-privileged CREATE2 deployer (precomputed `MiningVault` address passed into `MiningPass`, `MiningPass`'s real address passed into `MiningVault`'s CREATE2-deployed constructor, post-deploy address-match check reverting the whole transaction on mismatch); no mutable setter, owner, or admin role is introduced.
- Incorrect deployment sequence causing invalid immutable references.
- Misconfigured VRF parameters on Base (coordinator, keyHash, subscription).
- Incorrect initial token/vault wiring that could break hard cap enforcement assumptions.
