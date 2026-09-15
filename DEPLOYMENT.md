# DEPLOYMENT (DRAFT)

## Objective
Provide reproducible deployment without mutable post-deploy authority.

## Planned sequence (subject to final wiring)
1. Deploy `MiningPass` with immutable class/power/cap constants.
2. Deploy `MiningVault` with immutable references needed for verification.
3. Deploy `MountainToken` and route fixed supply to `MiningVault`.
4. Deploy `MiningMinter` with immutable airdrop/early-access Merkle roots.
5. Deploy `MysteryBoxSale` with immutable sale and randomness configuration.
6. Deploy `MiningEngine` as minimal orchestrator with constrained call surface.

## Constraints
- No mutable admin setters to solve constructor dependency loops.
- No upgradeability.
- No owner-controlled fund withdrawal mechanisms.

## Pending finalization
- Deterministic deployment requirements (if CREATE2 is necessary).
- VRF coordinator/keyHash/subscription parameters on Base.
