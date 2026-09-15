# INVARIANTS

1. `totalEmitted <= 1_000_000_000 ether` at all times.
2. `MountainToken` total supply is exactly `1_000_000_000 ether`, minted once in the constructor to `initialHolder`, with no mint function reachable after deployment (no owner mint, admin mint, public mint, hidden mint, or supply expansion of any kind).
3. `MiningPass` total minted supply never exceeds `100_000`.
4. Per-class caps are never exceeded:
   - Stone: 40,000
   - Obsidian: 25,000
   - Iron: 15,000
   - Steel: 10,000
   - Titanium: 6,000
   - Diamond: 3,000
   - Mithril: 1,000
5. Distribution buckets are enforced exactly: 10,000 airdrop / 10,000 early / 80,000 public.
6. Active mining position implies `ownerOf(tokenId) == address(MiningPass)` (real custody).
7. Claim payout recipient is always the authoritative stored miner (no `claim(to)`).
8. Released NFT recipient is always the same authoritative stored miner.
9. Reward elapsed time is clamped per period to max `630_720_000` seconds (20 years).
10. Reward math uses floor division only; rounding dust remains unallocated.
11. Mining signature is single-use via consumed nonce, with strict miner+tokenId binding.
12. Signature domain mismatch (`chainId` / verifying contract) invalidates authorization.
13. There is no `MiningEngine` and no `MiningMinter`: only `MiningVault` may ever compute reward, mining power, start time, or recipient, or transfer MMP; `MiningVault` never mints and holds no privileged mint role over `MountainToken`.
14. If mining is active, `miningOwner(tokenId) != address(0)`.
15. If mining is active, `miningStartedAt(tokenId) > 0`.
16. If mining is inactive, `miningStartedAt(tokenId) == 0`.
17. If mining is inactive, `miningOwner(tokenId) == address(0)`.
18. No unauthorized account can release an actively mined NFT from custody.
19. `MiningVault` pays claims only by `transfer` from its own pre-funded MMP balance; it holds no mint capability and calls no mint function on `MountainToken`.
