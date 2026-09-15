# MOUNTAIN MINING PROTOCOL — ARCHITECTURE REVIEW

## Implemented core contracts
- `MountainToken`: fixed-supply ERC-20; mints `1_000_000_000 ether` once to `MiningVault`.
- `MiningPass`: ERC-721 with immutable class caps/powers and active-mining custody lock.
- `MiningVault`: authoritative reward accounting and payout contract.
- `MiningEngine`: orchestration-only claim entrypoint (`claimAndRelease`).

## Not-yet-implemented modules
- `MiningMinter`: still skeleton.
- `MysteryBoxSale`: still skeleton.

## Reward model (approved and implemented)
- `MAX_EMISSION = 1_000_000_000 ether`
- `MAX_MINING_DURATION = 630_720_000`
- `TOTAL_WEIGHTED_POWER = 486_000`
- `reward = floor(power * elapsedSeconds * MAX_EMISSION / (TOTAL_WEIGHTED_POWER * MAX_MINING_DURATION))`
- `elapsedSeconds` is clamped to `MAX_MINING_DURATION`.

## Authority boundaries
- `MiningPass` is authoritative for:
  - active status
  - canonical miner
  - startedAt
  - class power
  - custody state
- `MiningVault` is authoritative for:
  - reward computation
  - `totalEmitted` cap enforcement
  - per-session claim tracking
  - reward disbursement
- `MiningEngine` is authoritative only for orchestration:
  - verifies caller is stored miner
  - calls vault claim/reserve
  - calls pass release
  - calls vault disbursement
  - never mints token and never holds NFT custody

## Constructor dependency graph
- `MiningPass(miningEngine, miningMinter)`
- `MiningVault(miningPass, miningEngine, mountainToken)`
- `MountainToken(initialHolder = miningVault)`
- `MiningEngine(miningPass, miningVault)`
- `MiningMinter()`

Naive sequential deployment creates a constructor cycle (`Pass <-> Engine <-> Vault <-> Token`).

## Immutable deployment architecture
- `ProtocolDeploymentFactory` resolves the cycle without mutable setters.
- Stage 1: deploy `ImmutableProtocolDeployer` with `CREATE2` using salt.
- Stage 2: deploy protocol contracts from that deployer with `CREATE` nonce order.
- Address predictions are available before deployment and asserted during deployment.

## Security constraints preserved
- no mutable dependency setters
- no upgradeability
- no pause/blacklist/emergency withdrawal
- no owner/admin backdoor for reward parameters
- no arbitrary reward/NFT recipient control
