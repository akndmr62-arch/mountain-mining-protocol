# Mountain Mining Protocol (MMP)

This repository currently contains a **security-first architecture skeleton** for a Base-native mining protocol.

## Status
- Architecture review drafted.
- Contract/module boundaries defined.
- Foundry project structure created.
- `MiningPass` custody lifecycle implemented.
- `MiningEngine` + `MiningVault` deterministic reward path implemented with 20-year clamp and 1B cap enforcement.
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
- **CLAIM**: `MiningEngine` reads authoritative position state, `MiningVault` computes and transfers reward to stored miner with floor rounding and global cap clamp, then `MiningPass` releases the NFT to the same stored miner.
- **POST-RELEASE**: NFT is transferable/approvable as a normal ERC-721 again.
