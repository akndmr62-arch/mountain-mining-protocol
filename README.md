# Mountain Mining Protocol (MMP)

This repository contains a **security-first Base-native mining protocol core** with deterministic reward accounting and immutable deployment wiring.

## Status
- Architecture review drafted.
- Contract/module boundaries defined.
- Foundry project structure created.
- `MiningPass` custody lifecycle implemented.
- `MiningEngine` + `MiningVault` deterministic reward path implemented with 20-year clamp and 1B cap enforcement.
- Immutable cycle-safe deployment mechanism implemented in `ProtocolDeploymentFactory`.
- GitHub Actions Foundry CI added (`forge fmt --check`, `forge build`, `forge test`).
- `MiningMinter` and `MysteryBoxSale` remain intentionally unimplemented skeletons.

## Fixed targets for implementation phase
- Network: Base
- Solidity: `0.8.24`
- OpenZeppelin Contracts: `5.0.2` (exact pin in documentation/config)
- MMP fixed supply / max emission: `1,000,000,000` MMP with `18` decimals
- MiningPass cap: `100,000` NFTs with on-chain per-class caps
- Distribution buckets: `10,000` airdrop / `10,000` early access / `80,000` public sale
- No upgradeability, no owner backdoors, no pause, no blacklist, no `tx.origin`, no timestamp randomness, no emergency withdrawal logic

## Project structure
- `src/`
  - `MountainToken.sol`
  - `MiningPass.sol`
  - `MiningVault.sol`
  - `MiningEngine.sol`
  - `ProtocolDeploymentFactory.sol`
  - `MiningMinter.sol`
  - `MysteryBoxSale.sol`
- `interfaces/`
- `test/`
- `script/`

## Security posture goal
Design for strong resistance against NFT theft, reward theft, replay, over-emission, reentrancy, randomness manipulation, and unauthorized state transitions.

## MiningPass custody lifecycle (v1)
- **MINE**: user-owned Mining Pass is moved into `MiningPass` contract custody and mining starts.
- **MINING**: NFT stays custody-locked (`ownerOf(tokenId) == address(MiningPass)`) while rewards accrue passively from elapsed time.
- **CLAIM**: caller must equal the authoritative stored miner; `MiningEngine` checks this, `MiningVault` reserves deterministic reward from authoritative state, `MiningPass` releases the NFT to the same stored miner, then `MiningVault` pays the reserved reward to that same stored miner.
- **POST-RELEASE**: NFT is transferable/approvable as a normal ERC-721 again.
