# INVARIANTS

1. `totalEmitted <= 1_000_000_000 ether` at all times.
2. Active mining position implies `ownerOf(tokenId) == address(MiningPass)`.
3. Claim payout recipient is always `position.miner`.
4. Released NFT recipient is always `position.miner`.
5. Reward elapsed time is clamped to max `630_720_000` seconds.
6. Reward math uses floor division only.
7. Mining signature is single-use via consumed nonce.
8. Signature domain mismatch (chain/contract) invalidates authorization.
9. Per-class mint count never exceeds configured class cap.
10. Total MiningPass supply never exceeds `100_000`.
