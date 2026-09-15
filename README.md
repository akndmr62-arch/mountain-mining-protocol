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
  - `MysteryBoxSale.sol`
- `interfaces/`
- `test/`
- `script/`

## Security posture goal
Design for strong resistance against NFT theft, reward theft, replay, over-emission, reentrancy, randomness manipulation, and unauthorized state transitions.

## MiningPass custody lifecycle (v1)
- **MINE**: user-owned Mining Pass moves into `MiningPass` contract custody and mining starts (EIP-712 authorized, per Part 13).
- **MINING**: NFT stays custody-locked (`ownerOf(tokenId) == address(MiningPass)`) while rewards accrue passively from elapsed time and fixed class power (Part 16, Part 17).
- **CLAIM**: `MiningVault` independently validates the mining state (Part 20), computes the reward itself, enforces the emission cap (`totalEmitted + reward <= 1,000,000,000 MMP`), transfers MMP from its own pre-funded balance to the recorded miner, and instructs `MiningPass` to release the NFT to that same recorded miner. No arbitrary recipient is ever accepted, and no MMP is ever minted at claim time — the full supply is minted once, at deployment, and MiningVault only spends from that fixed balance.
- **POST-RELEASE**: NFT is transferable/approvable as a normal ERC-721 again.
