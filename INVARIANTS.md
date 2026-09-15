# INVARIANTS

1. `totalEmitted <= 1_000_000_000 ether` at all times.
2. `MountainToken` total supply is exactly `1_000_000_000 ether` with no post-deployment minting.
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
10. Class powers are fixed and authoritative from `MiningPass`: Stone=1, Obsidian=2, Iron=4, Steel=8, Titanium=16, Diamond=32, Mithril=64.
11. Reward math uses floor division only with deterministic formula:
   - `reward = floor(power * elapsedSeconds * 1_000_000_000 ether / (486_000 * 630_720_000))`
   - `elapsedSeconds = min(block.timestamp - startedAt, 630_720_000)`
   - rounding dust remains unallocated.
12. `MiningVault` is the authoritative emission accounting layer (`totalEmitted`) and clamps each payout so `totalEmitted <= 1_000_000_000 ether`.
13. Engine never becomes authoritative for reward, power, startTime, recipient, or custody.
14. If mining is active, `miningOwner(tokenId) != address(0)`.
15. If mining is active, `miningStartedAt(tokenId) > 0`.
16. If mining is inactive, `miningStartedAt(tokenId) == 0`.
17. If mining is inactive, `miningOwner(tokenId) == address(0)`.
18. No unauthorized account can release an actively mined NFT from custody.
