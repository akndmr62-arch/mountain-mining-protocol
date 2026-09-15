# MOUNTAIN MINING PROTOCOL — FINAL ARCHITECTURE REVIEW (PRE-IMPLEMENTATION)

This document is a second-pass architecture review performed **after** the PR #5 direction
(remove `MiningEngine`/`MiningMinter`, make `MiningVault` the sole atomic CLAIM authority) was
accepted, but **before** PR #5 is merged and **before** any production Solidity is written.

No production Solidity is added by this document. All contracts referenced below remain
skeletons (`src/MiningVault.sol`, `src/MountainToken.sol`, `src/MysteryBoxSale.sol`) except
`MiningPass.sol`, which already has a v1 implementation that is amended here only at the
specification level (constructor arg naming, EIP-712 authorization, custody rules).

---

## 0. Final contract list

| Contract | Role | State |
|---|---|---|
| `MountainToken` (MMP) | Fixed-supply ERC-20, no admin, no mint path | skeleton |
| `MiningPass` | ERC-721, custodial mining, class/phase caps, EIP-712 start, vault-only release | v1 implemented, must be revised (see §1, §5) |
| `MiningVault` | Sole CLAIM authority: reward math, emission cap, MMP payout, NFT release trigger | skeleton |
| `PassSaleController` (**new**, replaces unrestricted `passDistributor` role) | Bounded, per-phase-authorized minting gateway; the only address MiningPass trusts as `passDistributor` | **new contract required**, not yet designed in code |
| `AirdropClaim` (**new**, sub-module of `PassSaleController` or standalone) | Immutable dual-Merkle-root claim gateway for Airdrop + EarlyAccess phases | **new contract required** |
| `MysteryBoxSale` | Public-sale purchase + VRF-driven class assignment, calls `PassSaleController`/`MiningPass` for PublicSale phase only | skeleton, **BLOCKED** on randomness provider (see §4) |
| `Create2Deployer` (**new**, one-shot factory) | Resolves `MiningPass` <-> `MiningVault` constructor cycle | **new contract required**, not yet implemented |

`MiningEngine` and `MiningMinter` remain removed, per PR #5. No contract other than `MiningVault`
may call `releaseFromMining`. No contract other than the bounded distribution contracts may call
`mintMiningPass`.

---

## 1. MiningPass — final state model and call graph

### 1.1 Storage (final)

```
uint256 public constant MAX_TOTAL_SUPPLY = 100_000;

// class caps (immutable via pure function, unchanged from v1):
// Stone 40_000 / Obsidian 25_000 / Iron 15_000 / Steel 10_000 /
// Titanium 6_000 / Diamond 3_000 / Mithril 1_000  (sums to 100_000)

// class powers (immutable via pure function, unchanged from v1):
// Stone 1 / Obsidian 2 / Iron 4 / Steel 8 / Titanium 16 / Diamond 32 / Mithril 64

// phase caps (immutable via pure function, unchanged from v1):
// Airdrop 10_000 / EarlyAccess 10_000 / PublicSale 80_000  (sums to 100_000)

address public immutable miningVault;       // sole caller of releaseFromMining
address public immutable passDistributor;   // sole caller of mintMiningPass (see §2)

uint256 private _nextTokenId;
bool    private _lifecycleTransfer;         // custody-transfer reentrancy/bypass guard

mapping(uint256 => MiningClass)  private _tokenClass;      // immutable per token after mint
mapping(uint256 => MiningState)  private _miningStates;     // {miner, startedAt, active}
mapping(uint8   => uint32)       private _classMinted;
mapping(uint8   => uint32)       private _phaseMinted;

// NEW for EIP-712 mining authorization:
mapping(address => uint256) public nonces;   // per-miner monotonic nonce, consumed on `mine`
bytes32 private constant _MINE_TYPEHASH =
    keccak256("Mine(address miner,uint256 tokenId,uint256 nonce,uint256 deadline)");
// domain separator per EIP-712 / OZ EIP712 base contract (name="MountainMiningPass", version="1")
```

`MiningState{miner,startedAt,active}` is the **only** authoritative source `MiningVault` may read
(`getMiningPosition(tokenId)`); `miner` is "original miner recorded" and is the only valid release
recipient.

### 1.2 Call graph (final)

```
passDistributor (bounded contracts only, §2)
   └─ MiningPass.mintMiningPass(to, classId, phase)
         - enforces MAX_TOTAL_SUPPLY, class cap, phase cap
         - mints ERC-721 to `to`
         - records immutable classId for tokenId

EOA or ERC-1271 wallet (token owner) + off-chain relayer
   └─ MiningPass.mine(tokenId, miner, nonce, deadline, signature)
         - requires ownerOf(tokenId) == miner
         - requires !active
         - verifies EIP-712 signature via SignatureChecker.isValidSignatureNow(miner, digest, signature)
         - requires nonce == nonces[miner]++ (consumed atomically)
         - requires block.timestamp <= deadline
         - sets state {miner, startedAt=now, active=true}
         - _lifecycleTransfer=true; _transfer(miner, address(this), tokenId); _lifecycleTransfer=false
         - emits MiningStarted

MiningVault (only)
   └─ MiningPass.releaseFromMining(tokenId)
         - onlyMiningVault
         - requires active
         - reads/clears state, resets miner/startedAt/active
         - _lifecycleTransfer=true; _transfer(address(this), storedMiner, tokenId); _lifecycleTransfer=false
         - emits MiningStopped
         - NOTE: releaseFromMining does NOT take a recipient argument — the recipient is always
           the `miner` value that MiningPass itself stored at `mine()` time, never a MiningVault-
           or caller-supplied address.

Anyone (view-only)
   └─ isMining / miningStartedAt / miningOwner / miningClass / miningPower / getMiningPosition
   └─ classMinted / phaseMinted / totalMinted / classCap / classPower / phaseCap
```

### 1.3 Transfer / approval rules (final, strengthened)

- `_update` override: any transfer where `to == address(this)` or `from == address(this)` reverts
  unless `_lifecycleTransfer` is set by `mine`/`releaseFromMining` internally. This blocks
  `safeTransferFrom`/`transferFrom` custody bypass by any external account, including
  `passDistributor` or `miningVault` themselves (they can only reach custody through the
  dedicated functions, not raw transfers).
- `approve`/`setApprovalForAll` (the latter must be overridden too, not just `approve`) revert or
  are neutralized while `active == true`, so an approved operator can never pull a mining NFT out
  of custody or transfer it away pre-mining once mining starts. **v1 currently overrides only
  `approve`; `setApprovalForAll` must also be gated** — this is a required fix before production
  implementation:
  - Option A (chosen): override `_update` is already sufficient by itself to block the *transfer*,
    so a pre-existing operator approval becomes inert while `active`. Approval-bypass is therefore
    prevented at the transfer layer, not the approval layer, which is intentionally simpler and
    cannot be circumvented by a stale operator approval set before mining started.
  - `approve(...)` while `active` still additionally reverts (defense in depth, matches v1).
- No approval, operator, or owner call can ever invoke `_transfer` while `active == true`; only
  `mine` (entry) and `releaseFromMining` (exit) can, and both flip `_lifecycleTransfer` for the
  single call.

### 1.4 EIP-712 mining authorization

See §5 below (kept in one place to avoid duplication) — the `mine` signature model fully replaces
the current v1 direct `msg.sender == ownerOf` check with a signature-based flow, while still
requiring `ownerOf(tokenId) == miner` (custodial mining is owner-authorized, but authorization is
proven by an off-chain-signable, replay-protected message rather than requiring the owner to be
`msg.sender`, enabling relayers/paymasters without giving up control).

---

## 2. passDistributor constraint model

**Problem:** a single `passDistributor` address with unrestricted
`mintMiningPass(to, classId, phase)` is a full trust escalation: it can mint any class, in any
phase, to itself, without bound.

**Resolution: `MiningPass.passDistributor` is never an EOA and never a general-purpose sale
contract.** It is one narrowly-scoped immutable contract, `PassSaleController`, which is the
**only** address `MiningPass` will accept as `passDistributor`, and it internally delegates class
selection to phase-specific sub-flows that individually cannot violate the constraints:

```
PassSaleController (immutable passDistributor)
 ├─ AirdropClaim module      -> phase = Airdrop      (Merkle-bound, §3)
 ├─ EarlyAccessClaim module  -> phase = EarlyAccess   (Merkle-bound, §3)
 └─ MysteryBoxSale module    -> phase = PublicSale    (VRF-bound, §4)
```

`PassSaleController.mintMiningPass`-facing entrypoint is **not exposed generically**; instead it
exposes three narrow entrypoints, each independently bounded:

```solidity
function claimAirdrop(address to, MiningClass classId, uint256 allocationIndex, bytes32[] proof) external;
function claimEarlyAccess(address to, MiningClass classId, uint256 allocationIndex, bytes32[] proof) external;
function fulfillPublicSaleClass(address to, uint256 requestId, MiningClass classId) external; // callable only by the VRF callback path, internal to MysteryBoxSale (see §4)
```

Each entrypoint independently enforces:

1. **Cannot choose arbitrary rarity for buyers** — `classId` is not a free caller/contract input.
   - Airdrop/EarlyAccess: `classId` is baked into the Merkle leaf
     `keccak256(abi.encode(wallet, allocationIndex, classId, phase))` set immutably at deployment
     (§3). `PassSaleController` only forwards the class encoded in the already-verified leaf; it
     never computes or chooses it.
   - PublicSale: `classId` is not caller-suppliable at purchase time at all. The buyer calls
     `MysteryBoxSale.purchase()` with no class parameter; the class is determined later, solely
     from the VRF random word, by the fixed inventory-mapping algorithm in §4. The only path from
     VRF fulfillment to `PassSaleController` is the VRF coordinator's own callback into
     `MysteryBoxSale`, which is the only account authorized to call
     `fulfillPublicSaleClass`.
2. **Cannot exceed phase allocations** — `MiningPass.mintMiningPass` itself still independently
   enforces `_phaseMinted[phase] < _phaseCap(phase)` (this check is NOT removed; it is
   defense-in-depth even though `PassSaleController` also tracks phase counters, e.g. a running
   `airdropClaimed`/`earlyAccessClaimed`/`publicSaleMinted` counter capped by the immutable
   `10_000`/`10_000`/`80_000` constants at the controller level too).
3. **Cannot bypass airdrop/early allocation limits** — one-time-claim bitmap per
   `allocationIndex` (§3) is checked and set atomically before minting; a wallet/index pair can
   never claim twice, and there is no controller function that mints Airdrop/EarlyAccess NFTs
   without a valid Merkle proof.
4. **Cannot manipulate randomness** — `PassSaleController`/`MysteryBoxSale` never accept a
   caller-supplied random word or class; only the registered VRF callback (§4) may supply the
   fulfillment data, and the callback is itself keyed to a specific outstanding `requestId` that
   was created before the random word could be known.
5. **Cannot mint arbitrary NFTs for itself** — `PassSaleController` has no owner/admin function
   that calls `mintMiningPass(controllerAddressOrAnyAddress, anyClass, anyPhase)`. Every code path
   that reaches `mintMiningPass` is reachable only from an externally-verified claim (Merkle proof
   + unclaimed bitmap) or an externally-verified VRF fulfillment tied to a prior paid purchase
   request. There is no "mint to self" or "mint without payment/proof" function, and
   `PassSaleController` holds no privileged owner key with a generic mint escape hatch.

`MiningPass` constructor takes `passDistributor_` = the deployed `PassSaleController` address
(immutable, one-time, no setter — consistent with the "no mutable setVault/admin setters"
requirement). `PassSaleController` itself has no owner/admin who can rewire which sub-module is
active, its three sub-flows are wired immutably in its own constructor.

---

## 3. Airdrop / Early Access — final Merkle architecture

`PassSaleController` (or an immutable sibling `AirdropClaim` contract it owns as an immutable
reference — architecturally equivalent, the review treats them as one unit for clarity) holds:

```solidity
bytes32 public immutable airdropRoot;      // set once in constructor, no setter, ever
bytes32 public immutable earlyAccessRoot;  // set once in constructor, no setter, ever

mapping(uint256 => uint256) private _airdropClaimedBitmap;      // one-time claim, per allocationIndex
mapping(uint256 => uint256) private _earlyAccessClaimedBitmap;  // one-time claim, per allocationIndex

uint32 public airdropMinted;      // <= 10_000, mirrors MiningPass phase counter for defense-in-depth
uint32 public earlyAccessMinted;  // <= 10_000
```

- **Immutable roots**: both roots are constructor arguments only. There is no `setAirdropRoot`,
  no `setEarlyAccessRoot`, and no owner/admin role capable of adding one. This directly satisfies
  "do not introduce mutable root setters."
- **Per-wallet allocation**: each leaf commits to
  `keccak256(abi.encode(allocationIndex, wallet, classId))`. `allocationIndex` is a dense,
  pre-assigned index (0..9_999 for Airdrop, 0..9_999 for EarlyAccess) chosen off-chain at
  Merkle-tree-generation time, so each real-world allocation (one class-tagged slot per
  eligible wallet) maps to exactly one leaf and exactly one bitmap bit.
- **One-time claim**: `claimAirdrop`/`claimEarlyAccess` require
  `_getBit(bitmap, allocationIndex) == 0`, set the bit, then verify the Merkle proof against the
  wallet/class/index tuple, then call `MiningPass.mintMiningPass(wallet, classId, phase)`. Bit is
  set **before** the external mint call (checks-effects-interactions), so re-entrancy cannot
  double-claim.
- **Total phase cap**: enforced twice — (a) locally via `airdropMinted++ <= 10_000` /
  `earlyAccessMinted++ <= 10_000` and (b) authoritatively inside `MiningPass.mintMiningPass` via
  `_phaseMinted[phase] < _phaseCap(phase)`. Because each `allocationIndex` is unique and bounded
  to `< 10_000` by construction (the tree only contains 10,000 leaves per phase), the local cap is
  actually unreachable in practice — the design keeps it anyway as defense-in-depth.
- **Class assignment through the same secure randomness model**: Airdrop and EarlyAccess classes
  are **not** randomized — they are pre-committed per wallet in the Merkle tree (this is how
  allowlist-style rarity assignment normally works: the class was decided off-chain, e.g. by a
  prior snapshot/lottery, before the tree was built, and the tree is simply the tamper-evident
  commitment to that decision). This satisfies "class assignment through the same secure
  randomness model" in the sense that the **decision process that produced the off-chain
  allocation list** must itself have used the same bias-resistant randomness source described in
  §4 (e.g., a VRF-seeded shuffle performed once, before the Merkle tree is built and its root
  published) — not a second on-chain randomness call at claim time. This is recorded as a
  **process requirement on tree generation**, not a new on-chain randomness integration, since
  claim-time is deterministic by design (proof-verified, not randomized).

---

## 4. Randomness (MysteryBoxSale) — final specification

**Provider status: BLOCKED.** No Base-mainnet-compatible verifiable-randomness provider
address/subscription/coordinator has been supplied or approved for this repository. Per the
prohibition on inventing provider addresses, and per the requirement to explicitly mark this
BLOCKED when unresolved, this section specifies the interface and lifecycle only; no concrete
coordinator address, key hash, or subscription ID may be hardcoded until provided.

> RANDOMNESS: BLOCKED — Base VRF/provider configuration unresolved.

### 4.1 Randomness provider interface (abstract, provider-agnostic)

```solidity
interface IRandomnessProvider {
    function requestRandomWords(bytes32 keyHash, uint64 subscriptionId, uint16 minConfirmations,
                                 uint32 callbackGasLimit, uint32 numWords) external returns (uint256 requestId);
}

interface IRandomnessConsumer {
    // Called back ONLY by the configured coordinator/provider address.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}
```

`MysteryBoxSale` implements `IRandomnessConsumer`, holds `immutable coordinator` (VRF coordinator
address — to be supplied once Base provider is finalized, never guessed) and forwards
provider-agnostic fulfillment to an internal `_fulfill(requestId, randomWords)`.

### 4.2 Request lifecycle

```
1. buyer calls purchase(quantity) with payment
2. contract validates: PublicSale phase not exhausted (80_000 cap, checked against
   MiningPass.phaseMinted(PublicSale) at minimum, mirrored locally), payment correct
3. contract records PendingPurchase{buyer, quantity, fulfilled=false} keyed by a locally
   generated purchaseId, THEN calls coordinator.requestRandomWords(...) and stores
   requestIdToPurchaseId[requestId] = purchaseId
4. buyer funds/payment are held in escrow by MysteryBoxSale (not yet minted, not yet released)
5. coordinator invokes rawFulfillRandomWords(requestId, randomWords) asynchronously
6. _fulfill: requires msg.sender == coordinator; requires requestIdToPurchaseId[requestId] != 0
   and purchase not yet fulfilled; marks fulfilled=true (checks-effects-interactions);
   for each unit in quantity, derives a class via the depletion-aware algorithm (4.3) from the
   random word(s), then calls PassSaleController.fulfillPublicSaleClass(buyer, requestId, classId)
   -> MiningPass.mintMiningPass(buyer, classId, PublicSale)
7. On success, escrowed payment is either consumed (kept by protocol) — no refund path is a
   randomness bypass, since class does not affect price under a mystery-box model. Any refund
   logic is out of scope for randomness fairness.
```

### 4.3 Request ID tracking / pending purchase state

```solidity
struct PendingPurchase { address buyer; uint16 quantity; bool fulfilled; uint64 requestedAt; }
mapping(uint256 requestId => PendingPurchase) public pendingPurchases;
```

`requestId` is the coordinator-issued identifier; there is no locally-invented ID that could
collide or be spoofed. `pendingPurchases[requestId]` is set strictly before the external
`requestRandomWords` call so that the callback path always has a matching, already-committed
buyer/quantity to resolve against (buyer cannot be altered after the request is placed).

### 4.4 Fulfillment / failure handling

- **Callback authorization**: `rawFulfillRandomWords` (or provider-equivalent) reverts unless
  `msg.sender == coordinator` (immutable). No other address, including the deployer, owner, or
  `PassSaleController`, can inject a random word.
- **Idempotency**: a `requestId` can only be fulfilled once (`fulfilled` flag checked and set
  atomically before any minting).
- **Provider failure / non-fulfillment (liveness)**: if a provider never calls back (coordinator
  outage, subscription underfunded, etc.), the purchase remains pending indefinitely holding
  escrowed funds. The final design must include an explicit, immutable **timeout + refund**
  path (e.g., after `T` seconds with `!fulfilled`, buyer may reclaim escrowed payment — this does
  **not** re-request randomness or grant a class, it only refunds; it cannot be used to "retry
  until favorable," since a refunded purchase yields no NFT and a fresh purchase is a brand new,
  independent request/escrow). This prevents both indefinite fund lock and "retry for a better
  roll," since there is no roll to discard — the escrowed request is either fulfilled once or
  refunded, never re-rolled.
- **No re-request-on-unfavorable-outcome path exists anywhere in the design.**

### 4.5 Class selection algorithm (bias resistance + inventory depletion)

Given `randomWord` (256-bit, coordinator-verified unbiased/unpredictable output) and the current
**remaining** per-class inventory (`_classCap(class) - _classMinted[class]`, read from
`MiningPass` at fulfillment time, not at request time, since request time predates the
unpredictable word and any state read then would be stale and gameable only in the buyer's favor
if it were fixed before randomness — reading at fulfillment avoids this entirely because the
buyer cannot influence the word regardless of when inventory is read):

```
remaining[c] for c in Stone..Mithril   // dynamic remaining counts, sum = totalRemaining
cumulative-weighted selection:
  r = randomWord % totalRemaining
  walk classes in a FIXED, immutable order (Stone..Mithril); subtract remaining[c] from r
  until r < remaining[c]; selected class = c
```

- This is a standard **weighted-without-replacement** draw: each unsold slot across all classes
  is an equally likely outcome (uniform over remaining slots), so the probability of drawing a
  given class equals `remaining[class] / totalRemaining` at that exact fulfillment moment. As
  classes deplete, weights shift automatically and correctly — a fully depleted class has
  `remaining == 0` and can never be selected (division-by-zero/degenerate case: if
  `totalRemaining == 0` for the PublicSale phase, the sale must already be closed/capped by the
  `_phaseCap` check in `mintMiningPass`, so this path is unreachable once 80,000 PublicSale mints
  are exhausted).
- For `quantity > 1` in one purchase, each unit must consume a **fresh, independent word slice**
  (e.g., `keccak256(abi.encode(randomWord, unitIndex))`) and must re-read `remaining[]` after each
  simulated selection within the same fulfillment transaction, so that multiple units in the same
  purchase cannot all draw from stale, pre-decrement inventory (which would bias multi-unit
  purchases toward rare classes as if each draw ignored the others).
- **Bias resistance**: uniform modulo-reduction of a 256-bit word against small remaining totals
  (max 80,000) has negligible modulo bias (bias bound ~ `totalRemaining / 2^256`, effectively
  zero); no additional Fisher-Yates-style rejection sampling is required at this scale, but must
  be re-evaluated if `numWords`/class-count assumptions change.
- **Protection against buyer prediction/manipulation**: buyer supplies no input that affects the
  random word (no client-seed, no buyer-chosen salt mixed into the class-selection input) and the
  class is computed strictly after the coordinator-supplied word is received and authenticated;
  buyer cannot observe the word before it is committed on-chain in the same callback transaction
  that consumes it.
- **Protection against deployer/operator manipulation**: the coordinator address is immutable and
  external to the protocol's own trust boundary (a third-party VRF service); the protocol itself
  never generates or substitutes its own "randomness"; there is no deployer-controlled function
  that can set/override a random word, a class, or `remaining[]` counts.

---

## 5. Mining start — final EIP-712 model

### 5.1 Struct

```solidity
struct Mine {
    address miner;
    uint256 tokenId;
    uint256 nonce;
    uint256 deadline;
}
```

Typehash: `keccak256("Mine(address miner,uint256 tokenId,uint256 nonce,uint256 deadline)")`

### 5.2 Domain

```solidity
EIP712Domain(
    string name,             // "MountainMiningPass"
    string version,          // "1"
    uint256 chainId,          // block.chainid at domain-separator construction (OZ EIP712 caches
                              // and auto-rebuilds on chain fork per OZ 5.x behavior)
    address verifyingContract // address(this) — the MiningPass contract itself
)
```

`MiningPass` inherits OpenZeppelin `EIP712` (name/version fixed at construction) so
`_domainSeparatorV4()` binds `chainId` and `verifyingContract` per EIP-712/EIP-2612 conventions,
preventing cross-chain and cross-contract signature replay.

### 5.3 Verification flow

```solidity
function mine(uint256 tokenId, uint256 deadline, bytes calldata signature) external {
    address miner = ownerOf(tokenId);                 // custodial mining still requires current owner
    if (block.timestamp > deadline) revert ExpiredSignature();
    uint256 nonce = nonces[miner];
    bytes32 structHash = keccak256(abi.encode(_MINE_TYPEHASH, miner, tokenId, nonce, deadline));
    bytes32 digest = _hashTypedDataV4(structHash);
    if (!SignatureChecker.isValidSignatureNow(miner, digest, signature)) revert InvalidSignature();
    nonces[miner] = nonce + 1;                          // atomic consume, before state mutation
    // ... existing active-state / custody-transfer logic unchanged ...
}
```

- `SignatureChecker.isValidSignatureNow` (OZ) transparently supports:
  - **EOA**: `ecrecover(digest, v, r, s) == miner`, standard 65-byte signature.
  - **ERC-1271**: if `miner` is a contract, calls
    `miner.isValidSignature(digest, signature)` and requires the
    `0x1626ba7e` magic value return, supporting smart-contract wallets (e.g., Safe) as miners.
- **Nonce replay protection**: `nonces[miner]` is a strictly increasing per-miner counter,
  incremented before any external interaction, so a captured signature can be used at most once
  and only for the specific `nonce` embedded in it at signing time.
- **Deadline**: signatures expire; expired signatures revert regardless of validity.
- This authorization model still requires `ownerOf(tokenId) == miner` — it does not let a
  non-owner "authorize" mining of someone else's pass; it only replaces "caller must literally be
  `msg.sender == owner`" with "a validly-signed, owner-attributable authorization must be
  presented," enabling relayed/sponsored transactions without weakening custody control.

---

## 6. Atomic CLAIM — MiningVault.claimAndRelease

### 6.1 Storage

```solidity
address public immutable miningPass;    // IMiningPass
address public immutable mountainToken; // IMountainToken / IERC20
uint256 public totalEmitted;            // monotonic, <= 1_000_000_000 ether

uint256 public constant MAX_ELAPSED_SECONDS = 630_720_000; // 20 years
uint256 public constant REWARD_DENOMINATOR = 630_720_000 * 486_000;
uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
```

### 6.2 Flow

```solidity
function claimAndRelease(uint256 tokenId) external nonReentrant {
    IMiningPass.MiningPosition memory pos = IMiningPass(miningPass).getMiningPosition(tokenId);
    if (!pos.active) revert NotMining(tokenId);                       // validate custody/state
    if (IERC721(miningPass).ownerOf(tokenId) != miningPass) revert CustodyViolation(tokenId); // defense-in-depth

    uint256 elapsed = block.timestamp - pos.startedAt;
    if (elapsed > MAX_ELAPSED_SECONDS) elapsed = MAX_ELAPSED_SECONDS;   // clamp

    uint256 reward = (elapsed * pos.power * MAX_SUPPLY) / REWARD_DENOMINATOR; // floor division (Solidity default)

    uint256 newTotal = totalEmitted + reward;
    if (newTotal > MAX_SUPPLY) revert EmissionCapExceeded();           // enforce cap
    totalEmitted = newTotal;                                           // effects before external calls

    address miner = pos.miner;                                        // authoritative recipient, no caller input
    IERC20(mountainToken).transfer(miner, reward);                    // pay from Vault's own balance, never mint
    IMiningPass(miningPass).releaseFromMining(tokenId);                // release NFT, recipient decided by MiningPass itself

    emit Claimed(tokenId, miner, reward, elapsed);
}
```

- **No arbitrary recipient**: `miner` is read from `MiningPass` state, never a parameter.
- **No caller-provided reward**: reward is fully derived from on-chain `pos.power`/`pos.startedAt`
  and `block.timestamp`; nothing from `msg.data` feeds the formula.
- **No MMP mint**: `mountainToken.transfer` moves from `MiningVault`'s pre-funded balance
  (funded once at deployment with the entire fixed supply per §8); `MiningVault` never calls a
  mint function, and `MountainToken` exposes none post-construction.
- **Atomicity**: if the ERC-20 `transfer` or `releaseFromMining` call reverts (e.g.,
  insufficient Vault balance, custody-guard trip), the whole transaction — including the
  `totalEmitted` increment — reverts, so no partial state (emitted-but-not-paid, or
  paid-but-not-released) can persist. Use `nonReentrant` plus checks-effects-interactions
  (state updated before external calls) to also block reentrancy through a malicious
  `mountainToken`/`miningPass` implementation — moot here since both are fixed, audited,
  non-upgradeable contracts, but enforced as defense-in-depth.
- **Permissionless**: `claimAndRelease` has no access control beyond the state checks above —
  anyone may trigger the claim, but the payout/release target is immutable to the call.

---

## 7. CREATE2 deployment proof (MiningPass <-> MiningVault cycle)

### 7.1 The cycle

`MiningPass` needs `miningVault` (the sole `releaseFromMining` caller) as an **immutable**
constructor argument. `MiningVault` needs `miningPass` as an **immutable** constructor argument
(to call `getMiningPosition`/`releaseFromMining`/`ownerOf`). Neither can be deployed first without
knowing the other's address ahead of time — hence CREATE2.

### 7.2 Step-by-step address derivation

1. **A single, non-upgradeable, already-known `Create2Deployer` factory contract** is deployed
   first (ordinary CREATE, address known immediately once deployed, e.g. `factory`).
   `Create2Deployer` exposes one function:
   `deploy(bytes32 salt, bytes memory initCode) external returns (address deployed)`
   which does `assembly { deployed := create2(0, add(initCode, 0x20), mload(initCode), salt) }`
   and reverts the whole call (including any prior deployments performed in the same outer
   transaction via a batched `deployBatch`, see 7.6) if the `create2` call returns `address(0)`.

2. **Predict `MiningVault`'s address before deploying `MiningPass`.**
   `MiningVault`'s init code is `type(MiningVault).creationCode` concatenated with
   ABI-encoded constructor args `(miningPassAddress, mountainTokenAddress)`. Because
   `mountainTokenAddress` can be made known ahead of time too (MountainToken deployed first, or
   itself predicted via CREATE2 the same way — see 7.5), the only address that varies as a
   function of *this* cycle is `miningPassAddress`.

   Standard CREATE2 address formula:
   ```
   address = address(uint160(uint256(keccak256(
       abi.encodePacked(bytes1(0xff), factory, salt, keccak256(initCode))
   ))))
   ```

3. **Predict `MiningPass`'s address first**, since its constructor args
   (`miningVault_`, `passDistributor_`) are exactly the two addresses that must be *fixed before*
   `MiningPass` is deployed, and `passDistributor_` (the `PassSaleController`) can be deployed
   ordinarily beforehand (it does not depend on `MiningPass`'s address... **except that it does**,
   because `PassSaleController` needs to call `MiningPass.mintMiningPass`. This means
   `PassSaleController` also needs `MiningPass`'s address as an immutable constructor arg, so it
   must be predicted too. Concretely, the correct ordering is:

   a. **Predict** `miningPassAddr = predict(factory, saltPass, MiningPass.creationCode ++ abi.encode(predictedVaultAddr, predictedDistributorAddr))`
   b. **Predict** `miningVaultAddr = predict(factory, saltVault, MiningVault.creationCode ++ abi.encode(miningPassAddr, mountainTokenAddr))`
   c. **Predict** `passDistributorAddr = predict(factory, saltDistributor, PassSaleController.creationCode ++ abi.encode(miningPassAddr, airdropRoot, earlyAccessRoot, ...))`

   Steps (a)-(c) are all **pure, off-chain (or on-chain view) computations** — `predict(...)` only
   needs `factory`, a chosen `salt`, and `keccak256(initCode)`; none of it requires the contracts
   to actually exist yet. Since `initCode` for `MiningPass` depends on `miningVaultAddr` and
   `passDistributorAddr` (which are themselves predicted the same way, and those contracts'
   `initCode` depend on `miningPassAddr`), **all three addresses can be computed simultaneously
   off-chain** as a fixed-point: choose `saltPass`, `saltVault`, `saltDistributor` (e.g.,
   `keccak256("MMP.MiningPass.v1")` etc.), then:
   - compute `miningVaultAddr` and `passDistributorAddr` init code hashes using a *not-yet-existing*
     `miningPassAddr` — but `miningPassAddr` itself is `predict(factory, saltPass, keccak256(MiningPass.creationCode ++ abi.encode(miningVaultAddr, passDistributorAddr)))`.
   - This is solvable because CREATE2 addresses depend only on `keccak256(initCode)`, which is a
     pure function of already-known constants (`factory`, chosen salts, contract bytecode, and
     the *other two predicted addresses*). All three equations can be evaluated in one pass with
     no circular runtime dependency, because every input to every hash is computable **off-chain
     before any deployment transaction is sent** — the "cycle" is only a cycle in *deployment
     order*, not in *address computability*, since CREATE2 addresses never depend on the target
     contract's own deployed bytecode/state, only on `(factory, salt, initCodeHash)`, and
     `initCodeHash` only needs the *other* predicted addresses, which are equally pure functions
     of *their* other-predicted-address inputs. Solving the three equations together (standard
     off-chain script, e.g. in `Deploy.s.sol` or a Foundry script using `vm.computeCreate2Address`)
     yields concrete, final `miningPassAddr`, `miningVaultAddr`, `passDistributorAddr` before any
     contract is deployed.

4. **Constructor parameters affecting init code**:
   - `MiningPass`: `(miningVaultAddr, passDistributorAddr)` — both fixed by the off-chain solve.
   - `MiningVault`: `(miningPassAddr, mountainTokenAddr)`.
   - `PassSaleController`: `(miningPassAddr, airdropRoot, earlyAccessRoot, vrfCoordinator, ...)`
     — note `airdropRoot`/`earlyAccessRoot` are **content-addressed into the deployment itself**,
     which is a desirable property: the deployed address becomes a commitment to the exact Merkle
     roots used, an additional integrity property (changing the root would change the predicted
     address, immediately detectable).
   - `MountainToken`: `(initialHolderAddr)` where `initialHolderAddr = miningVaultAddr` (predicted,
     per §8) — so `MountainToken` can also be deployed via the same factory using a predicted
     `miningVaultAddr`, or deployed first via ordinary CREATE if `MiningVault`'s address is
     predicted before `MountainToken` exists (either ordering works since `MountainToken`'s
     address is not, itself, an input to anyone else's init code in this design).

5. **All three (or four, including MountainToken) deployments happen in one transaction**, via
   `Create2Deployer.deployBatch(salts[], initCodes[])` (a single external call that loops over
   `create2` for each entry). This is required — not merely convenient — because between separate
   transactions an attacker could front-run and deploy different bytecode to a predicted address
   for a different salt (address-squatting risk on a public factory), and because partial
   deployment (e.g., `MiningPass` deployed but `MiningVault` deployment fails) would leave
   `MiningPass` permanently wired to a `miningVaultAddr` that is not a contract, this is
   unrecoverable given "no mutable setter" is a hard requirement. Doing all deployments as one
   atomic transaction batch guarantees either the full, mutually-consistent system exists or none
   of it does.

6. **Revert rollback**: yes — if any single `create2` in `deployBatch` fails (returns
   `address(0)`, e.g. due to a salt collision, insufficient value, or a constructor revert inside
   one of the deployed contracts), `Create2Deployer.deploy`/`deployBatch` must explicitly check
   the return value and revert the whole call, and since all of this happens inside one top-level
   transaction, standard EVM semantics roll back **all** state changes performed by that
   transaction, including any contracts that were successfully CREATE2'd earlier in the same
   `deployBatch` loop (contract creation is not "durable" until the top-level transaction
   succeeds). This must be validated by a deployment-script-level Foundry test (`vm.expectRevert`
   on a deliberately-failing batched deploy, then asserting `extcodesize` is zero at all the
   predicted addresses).

7. **Is a separate factory required?** Yes — a minimal, immutable, ownerless
   `Create2Deployer` factory (or Foundry's canonical deterministic deployer, if reused) is
   required, because `CREATE2` is a contract-creation opcode: it must be executed **from** some
   already-deployed contract (or an EOA, which cannot execute `CREATE2` directly — EOAs can only
   perform plain `CREATE` by originating a *deployment transaction*, not `CREATE2`). The factory
   contract itself must have no privileged mint/setter role, must be deployed once, and can be a
   generic reusable deployer (its own address, `factory`, is then a fixed input into every
   predicted-address formula above).

### 7.3 MountainToken funding vs. mint (see §8)

`MountainToken`'s constructor mints the entire fixed supply to `initialHolder` in one shot; if
`initialHolder` is set to the predicted `miningVaultAddr`, `MiningVault` is funded atomically at
`MountainToken`'s own construction, inside the same batched deployment transaction, with no
separate `transfer` step required.

---

## 8. MountainToken — final design (unchanged from problem statement, confirmed against current skeleton)

```solidity
contract MountainToken is ERC20 {
    constructor(address initialHolder) ERC20("Mountain", "MMP") {
        _mint(initialHolder, 1_000_000_000 ether);
    }
}
```

- ERC-20, name `Mountain`, symbol `MMP`, 18 decimals (OZ ERC20 default).
- Exactly `1_000_000_000 ether` (`10**27` base units) minted once, in the constructor.
- `initialHolder` (the predicted `MiningVault` address, per §7) receives the entire supply.
- No future mint: no `mint` function is exposed anywhere in the contract; OZ `ERC20` base has no
  mint entrypoint beyond the internal `_mint`, which is only called once, in the constructor.
- No owner, no admin, no upgradeability, no burn, no pause, no blacklist, no recovery: the
  contract inherits only `ERC20` — no `Ownable`, no `AccessControl`, no `ERC20Burnable`, no
  `ERC20Pausable`, no proxy pattern, and defines no additional functions.

---

## 9. MiningVault — final storage/interfaces (see also §6)

```solidity
interface IMiningVault {
    function claimAndRelease(uint256 tokenId) external;
    function totalEmitted() external view returns (uint256);
}

contract MiningVault is IMiningVault, ReentrancyGuard {
    address public immutable miningPass;
    address public immutable mountainToken;
    uint256 public totalEmitted;

    uint256 public constant MAX_ELAPSED_SECONDS = 630_720_000;
    uint256 public constant REWARD_DENOMINATOR = 630_720_000 * 486_000;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    event Claimed(uint256 indexed tokenId, address indexed miner, uint256 reward, uint256 elapsed);
    error NotMining(uint256 tokenId);
    error CustodyViolation(uint256 tokenId);
    error EmissionCapExceeded();

    constructor(address miningPass_, address mountainToken_) { ... immutable assignment only ... }

    function claimAndRelease(uint256 tokenId) external nonReentrant { /* see §6.2 */ }
}
```

Reward formula (must remain exact, floor division via default Solidity integer division):

```
reward = elapsedSeconds * miningPower * 1_000_000_000 ether / (630_720_000 * 486_000)
```

No other public/external mutating function exists on `MiningVault` — specifically, no
`withdraw`, no `setMiningPass`, no `setMountainToken`, no `pause`, no owner.

---

## 10. Dependency graph

```
MountainToken ──(initialHolder = MiningVault, predicted via CREATE2)──> mints once to MiningVault
     ▲                                                                       │
     │ IMountainToken.transfer (Vault-only, payout)                         │
     │                                                                       ▼
MiningVault <───────────── IMiningPass.getMiningPosition/releaseFromMining ─ MiningPass
     │  claimAndRelease(tokenId)                                             ▲   ▲
     │                                                                       │   │
     │  (immutable: miningPass)                                             │   │ mintMiningPass
     ▼                                                                       │   │ (bounded, phase-checked)
 (pays MMP to recorded miner, releases NFT to recorded miner)                │   │
                                                                              │   │
                                                        onlyMiningVault ──────┘   │
                                                                                   │
                                                          passDistributor ─────────┘
                                                       (= PassSaleController, immutable)
                                                                │
                                     ┌──────────────────────────┼───────────────────────────┐
                                     ▼                          ▼                            ▼
                              AirdropClaim              EarlyAccessClaim               MysteryBoxSale
                            (immutable Merkle root)    (immutable Merkle root)      (VRF coordinator, immutable)
```

`Create2Deployer` sits outside the runtime dependency graph entirely — it is used once, at
deployment, and holds no ongoing privileged relationship to any deployed contract afterward.

---

## 11. State ownership summary

| State | Owner (sole writer) | Readers |
|---|---|---|
| `MiningPass._miningStates` (miner/startedAt/active) | `MiningPass` itself (`mine`/`releaseFromMining`) | `MiningVault` (read-only via `getMiningPosition`) |
| `MiningPass._tokenClass`, class/phase counters | `MiningPass` itself (`mintMiningPass`) | anyone (view) |
| `MiningPass.nonces` | `MiningPass` itself (`mine`) | signature verification only |
| `MiningVault.totalEmitted` | `MiningVault` itself (`claimAndRelease`) | anyone (view) |
| `MountainToken` balances | standard ERC-20 semantics; only `MiningVault`'s balance decreases (via its own `transfer` calls) | anyone (view) |
| `PassSaleController`/`AirdropClaim` claim bitmaps, phase counters | controller/claim contracts themselves | anyone (view) |
| `MysteryBoxSale.pendingPurchases` | `MysteryBoxSale` itself (`purchase`/`_fulfill`) | VRF coordinator triggers `_fulfill` |

No contract in this design ever writes another contract's storage directly; all cross-contract
effects happen through the narrow function calls enumerated in §1.2 and §10.

---

## 12. Custody flow

```
1. NFT minted to buyer/claimant wallet (ownerOf == wallet, active == false)
2. wallet (EOA or ERC-1271) signs Mine(miner, tokenId, nonce, deadline); anyone submits mine(...)
3. MiningPass verifies signature + ownership + !active; sets active=true, miner=wallet,
   startedAt=now; transfers NFT to address(this) (MiningPass) via _lifecycleTransfer guard
4. while active: ownerOf(tokenId) == address(MiningPass); approve()/setApprovalForAll-enabled
   operators cannot move it (see §1.3); miner cannot re-mine (AlreadyMining) or transfer it away
5. MiningVault.claimAndRelease(tokenId) reads active/miner/startedAt/power, pays MMP to miner,
   calls releaseFromMining -> MiningPass transfers NFT from address(this) back to miner,
   active=false, miner/startedAt cleared
6. NFT is once again a freely transferable, ownable ERC-721 in the miner's wallet
```

---

## 13. Claim flow (see §6 for full code-level detail)

```
anyone -> MiningVault.claimAndRelease(tokenId)
   -> MiningPass.getMiningPosition(tokenId)  [view, authoritative]
   -> require active
   -> elapsed = min(now - startedAt, 630_720_000)
   -> reward = floor(elapsed * power * 1e9 ether / (630_720_000 * 486_000))
   -> require totalEmitted + reward <= 1e9 ether; totalEmitted += reward
   -> MountainToken.transfer(miner, reward)     [Vault's own balance, never mint]
   -> MiningPass.releaseFromMining(tokenId)     [recipient = miner, decided by MiningPass, not caller]
   -> atomic: any failure reverts all of the above
```

---

## 14. Randomness flow (see §4 for full detail; summarized)

```
buyer -> MysteryBoxSale.purchase(quantity) [escrow payment]
      -> requestRandomWords(coordinator) -> requestId
      -> pendingPurchases[requestId] = {buyer, quantity, fulfilled=false}
coordinator -> rawFulfillRandomWords(requestId, randomWords)  [onlyCoordinator]
      -> require !fulfilled; fulfilled = true
      -> for each unit: derive sub-word -> weighted-without-replacement class draw against
         live MiningPass remaining-inventory -> PassSaleController.fulfillPublicSaleClass
         -> MiningPass.mintMiningPass(buyer, classId, PublicSale)
(failure path) -> after timeout with !fulfilled, buyer may reclaim escrowed payment (no re-roll)
```

---

## 15. Distribution flow

```
Airdrop (10,000 cap):     wallet + Merkle proof (index, wallet, classId) -> one-time bitmap claim
                           -> MiningPass.mintMiningPass(wallet, classId, Airdrop)
EarlyAccess (10,000 cap):  identical pattern, separate immutable root, separate bitmap, phase=EarlyAccess
PublicSale (80,000 cap):   payment -> VRF request -> VRF fulfillment -> weighted class draw
                           -> MiningPass.mintMiningPass(buyer, classId, PublicSale)
```

All three paths converge on the same `MiningPass.mintMiningPass`, which independently re-enforces
`MAX_TOTAL_SUPPLY`, per-class cap, and per-phase cap regardless of which upstream path called it —
this is the final defense-in-depth backstop against any bug in `PassSaleController` or its
sub-modules.

---

## 16. Unresolved questions

1. **Randomness provider** — Base VRF/verifiable-randomness coordinator address, key hash, and
   subscription funding model are not finalized. **BLOCKED.**
2. **`setApprovalForAll` gating** — confirm whether relying solely on the `_update` custody guard
   (current v1 approach, §1.3) is accepted as sufficient, or whether `setApprovalForAll` should
   also explicitly revert while any of the caller's tokens are mining (note: `setApprovalForAll`
   is not per-token, so a blanket revert-while-any-active-token approach is more invasive; the
   `_update`-only guard is recommended and is believed sufficient, but is flagged for explicit
   sign-off since v1 code currently only guards `approve`, not `setApprovalForAll`, and both must
   be confirmed non-exploitable together in tests).
3. **VRF timeout/refund parameter** (`T` seconds) and whether refund is full-value or
   fee-adjusted — not yet specified.
4. **Multi-unit purchase gas budget** — `callbackGasLimit` sizing for `quantity > 1` fulfillments
   doing multiple `mintMiningPass` calls in one VRF callback is provider/gas-dependent and cannot
   be finalized until the provider (item 1) is resolved.
5. **`PassSaleController` vs. separate `AirdropClaim`/`EarlyAccessClaim` contracts** — this review
   treats them as one logical unit; final code organization (one contract vs. three) is an
   implementation detail that does not change the security model, but must be decided before
   coding begins.
6. **CREATE2 salt values and factory choice** — whether to use a project-specific
   `Create2Deployer` or a canonical, already-deployed deterministic deployer (e.g. the widely-used
   `0x4e59b44847b379578588920cA78FbF26c0B4956C` singleton factory pattern) is unresolved; either
   is compatible with the proof in §7, but must be explicitly chosen.

---

## 17. Security assumptions

- Base L2 sequencer/consensus and `block.timestamp` monotonic progression follow ordinary
  blockchain assumptions (no assumption of sub-second precision).
- The chosen VRF/randomness coordinator, once selected, is honest, live, and its own
  cryptographic proof of fair randomness is correct (external trust boundary, not re-verified by
  this protocol's own code beyond checking `msg.sender == coordinator`).
- OpenZeppelin Contracts 5.0.2 (`ERC721`, `ERC20`, `EIP712`, `SignatureChecker`, `ReentrancyGuard`)
  are used unmodified and are individually correct.
- ERC-1271 wallets used as miners implement `isValidSignature` correctly and do not
  self-approve arbitrary signatures.
- The off-chain Merkle tree generation process for Airdrop/EarlyAccess (including whatever
  randomness informed original class assignment) is performed correctly and its root is published
  before any claims occur; this protocol cannot verify the fairness of tree *construction*, only
  its immutability and one-time-claim enforcement once published.

---

## 18. Attack surfaces

- EIP-712 `mine` authorization: signature malleability, replay across nonce/deadline boundaries,
  ERC-1271 wallets returning stale/cached validity.
- Custody `_update` guard: any code path that could set `_lifecycleTransfer` outside `mine`/
  `releaseFromMining`, or any reentrancy into `mine`/`releaseFromMining` mid-flip.
- `claimAndRelease`: reentrancy via `mountainToken.transfer`/`releaseFromMining` external calls;
  reward-formula overflow (bounded by `uint256` and realistic `power`/`elapsed` ranges — should be
  explicitly tested at `MAX_ELAPSED_SECONDS` and `Mithril` power=64 for headroom).
  `totalEmitted` cap race between concurrent claims (single-threaded EVM makes this
  non-issue on-chain, but must be tested for correct ordering under back-to-back claims).
- `PassSaleController`/claim contracts: Merkle proof forgery (must use OZ `MerkleProof`, correct
  leaf-hash domain separation to prevent second-preimage/tree-structure attacks), bitmap
  off-by-one, double-claim across index reuse.
- `MysteryBoxSale`: coordinator spoofing, requestId collision/reuse, escrow fund lock on
  provider outage, inventory read-time-of-check-vs-use race between multiple pending fulfillments
  in the same block (must confirm class-draw + mint happen atomically within `_fulfill`, no
  cross-transaction gap).
- CREATE2 deployment: front-running a predicted address on a public/shared factory before the
  legitimate batched deployment executes (mitigated by a project-owned, single-use `salt`
  namespace and doing all deployments as one atomic batch, §7).

---

## 19. Test requirements

1. `MiningPass`
   - Exactly 100,000 total cap; 7 class caps sum to 100,000 and are individually enforced.
   - 10,000/10,000/80,000 phase caps individually enforced, sum to 100,000.
   - `mine`/`releaseFromMining` custody transfer correctness; no external `transferFrom`/
     `safeTransferFrom`/`approve`/`setApprovalForAll`-enabled pull can move an active token.
   - EIP-712: valid EOA signature succeeds; valid ERC-1271 signature succeeds; wrong nonce fails;
     expired deadline fails; wrong domain (chainId/verifyingContract) fails; replay of consumed
     nonce fails; signature for a different tokenId/miner fails.
   - Only `miningVault` can call `releaseFromMining`; only `passDistributor` can call
     `mintMiningPass`.
   - Release recipient is always the stored miner, never a caller-supplied address.
2. `MiningVault`
   - Reward formula exact-value tests at multiple `(elapsed, power)` combinations, confirming
     floor division.
   - Elapsed clamp at exactly `630_720_000` seconds.
   - `totalEmitted` cap: last claim that would exceed `1_000_000_000 ether` reverts entirely,
     earlier valid emission state is preserved (not partially applied).
   - Non-active token claim reverts; already-claimed (re-entrant) attempts revert.
   - Fuzz test: random `(power, elapsed)` never produces `reward` causing `totalEmitted` to exceed
     cap without reverting first.
3. `MountainToken`
   - Total supply exactly `1_000_000_000 ether` post-construction; entire supply at
     `initialHolder`; no `mint` selector exists on the ABI; contract has no owner/admin storage.
4. `PassSaleController` / `AirdropClaim` / `EarlyAccessClaim`
   - Valid proof + correct class + unclaimed index succeeds exactly once; replay of the same
     index reverts; tampered class/wallet/index in proof reverts; roots are immutable (no setter
     exists on the ABI).
   - Phase cap enforcement at the controller level and, redundantly, at `MiningPass` level.
5. `MysteryBoxSale`
   - Only coordinator address can call fulfillment; wrong `requestId` reverts; double-fulfillment
     of the same `requestId` reverts.
   - Class draw distribution test (statistical, over many simulated fulfillments) matches
     expected weighting against remaining inventory; depleted class is never drawn.
   - Multi-unit purchase drawing distinct, correctly-decremented inventory per unit within one
     fulfillment.
   - Timeout/refund path returns exact escrowed amount once, cannot be double-refunded, cannot be
     combined with a later fulfillment of the same request.
6. CREATE2 deployment script
   - Predicted addresses (via `vm.computeCreate2Address` or equivalent) match actually-deployed
     addresses for `MiningPass`, `MiningVault`, `PassSaleController`, `MountainToken`.
   - A deliberately-failing batched deploy (e.g., one constructor reverts) leaves zero code at
     all predicted addresses (`extcodesize == 0` for each), proving atomic rollback.
   - End-to-end: after deployment, `MiningPass.miningVault == deployedVaultAddr`,
     `MiningVault.miningPass == deployedPassAddr`, `MountainToken` balance of `MiningVault`
     equals full supply, all with no post-deploy transaction required to "finish wiring."

---

## FINAL ARCHITECTURE STATUS:

**NO-GO**

Rationale: per the explicit instruction to mark NO-GO "if randomness, distribution authority,
EIP-712, atomic claim/release, or CREATE2 deployment remains unresolved" —
(a) **randomness** is explicitly BLOCKED pending a real Base VRF/provider selection (§4, §16.1);
(b) **distribution authority** requires a new contract (`PassSaleController` + Merkle claim
modules) that does not yet exist in code (§2, §0);
(c) **EIP-712** mining authorization is fully specified here (§5) but not yet implemented in
`MiningPass.sol`, which still uses direct `msg.sender == ownerOf` authorization;
(d) **atomic claim/release** is fully specified here (§6) but `MiningVault.sol` remains an empty
skeleton;
(e) **CREATE2 deployment** is proven step-by-step here (§7) but no `Create2Deployer` factory or
deployment script implementation exists yet, and the salt/factory choice is still open (§16.6).

Per the task instructions, no production Solidity is implemented in this pass, and PR #5 remains
unmerged. This document defines the target architecture that must be implemented, and the
specific unresolved items in §16 that must be closed, before status can move to GO.
