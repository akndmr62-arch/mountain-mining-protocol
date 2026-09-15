# Mountain Mining Protocol (MMP)

This repository currently contains a **security-first architecture skeleton** for a Base-native mining protocol.

## Status
- Architecture review drafted.
- Contract/module boundaries defined.
- Foundry project structure created.
- **Production Solidity logic intentionally not implemented yet.**

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
