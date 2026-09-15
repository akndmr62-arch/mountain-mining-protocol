# DEPLOYMENT (DRAFT)

## Objective
Provide reproducible deployment without mutable post-deploy authority.

## Planned sequence (subject to final wiring)
1. Precompute `MiningVault`'s CREATE2 address (one-time, non-privileged deployer pattern).
2. Deploy `MiningPass` with immutable class/power/cap constants and the precomputed `MiningVault` address wired in as its `miningVault` reference.
3. Deploy `MiningVault` via CREATE2 with `MiningPass`'s real address as an immutable constructor argument; revert the whole deployment if the deployed address does not match the precomputed one.
4. Deploy `MountainToken`, minting the full fixed supply of 1,000,000,000 MMP exactly once, in its constructor, to `initialHolder`.
5. Transfer `MountainToken`'s full balance from `initialHolder` to `MiningVault` via a single ordinary ERC20 `transfer`. No mint call is ever made after step 4, and `MountainToken` has no mint function reachable after construction.
6. Deploy `MysteryBoxSale` with immutable sale and randomness configuration.

There is no `MiningEngine` and no `MiningMinter` in this sequence: `MiningVault` is called directly for claims, and `MiningPass`'s airdrop/early-access issuance is authorized via its immutable `passDistributor` address, which is unrelated to MMP supply.

## Constraints
- No mutable admin setters to solve constructor dependency loops.
- No upgradeability.
- No owner-controlled fund withdrawal mechanisms.

## Pending finalization
- VRF coordinator/keyHash/subscription parameters on Base.
