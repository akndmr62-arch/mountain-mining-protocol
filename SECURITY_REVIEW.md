# SECURITY REVIEW (PRE-IMPLEMENTATION)

## Scope
Pre-implementation security architecture assessment for:
- MountainToken
- MiningPass
- MiningMinter
- MysteryBoxSale
- MiningEngine
- MiningVault

## Key threat categories
- Custody theft (NFT)
- Reward theft (MMP)
- Replay/cross-domain signature abuse
- Reentrancy across payout/release/callback paths
- Randomness manipulation and fulfillment griefing
- Cap bypass (class caps, total NFT caps, token emission cap)

## Security controls required in implementation phase
- EIP-712 + nonce + deadline + chain/contract-bound domain.
- ERC-1271 safe validation path.
- Canonical mining position source in MiningPass and independent Vault verification.
- Strict custody lock while active mining.
- Permissionless claims with fixed recipient = stored miner only.
- Atomic claim+release transaction semantics.
- Verifiable randomness mapping with immutable post-fulfillment handling.
- Checks-effects-interactions and nonReentrant where needed.

## Open security design decisions
- Final VRF integration interface and liveness-retry semantics.
- Class selection algorithm under inventory depletion constraints.
- Deployment ordering strategy avoiding mutable admin setters.
