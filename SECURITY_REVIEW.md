# SECURITY REVIEW (CURRENT STATE)

## Implemented security posture
- Reward parameters are immutable constants.
- Class powers/caps are immutable in `MiningPass`.
- Reward source-of-truth is `MiningVault` using `MiningPass` authoritative mining state.
- `totalEmitted` is cap-clamped to `1_000_000_000 ether`.
- Claim replay is blocked via per-token `sessionId` tracking.
- `sessionId` wrap is blocked (`SessionIdOverflow`).
- Mining custody release is `onlyMiningEngine`.

## Constructor-cycle hardening
- Deployment cycle is resolved with immutable deterministic deployment:
  - `ProtocolDeploymentFactory` (CREATE2 salt)
  - `ImmutableProtocolDeployer` (fixed CREATE nonce order)
- No mutable post-deploy rewiring or privileged setter is introduced.

## Claim lifecycle risks reviewed
- `MiningEngine.claimAndRelease` is non-reentrant.
- `MiningVault.claimReward` and `MiningVault.disburseReward` are non-reentrant.
- Claim ordering is:
  1. reserve reward from authoritative state
  2. release NFT to authoritative miner
  3. disburse reserved MMP to authoritative miner
- Any revert rolls back transaction state.

## Remaining non-core risks
- `MiningMinter` and `MysteryBoxSale` are still skeletons and require separate security review when implemented.
- VRF/public-sale randomness rules are not yet implemented.
