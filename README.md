# Mountain Mining Protocol (MMP)

This repository currently contains a **security-first architecture skeleton** for a Base-native mining protocol.

## Status
- Architecture review drafted.
- Contract/module boundaries defined.
- Foundry project structure created.
- **Production Solidity logic intentionally not implemented yet.**

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
