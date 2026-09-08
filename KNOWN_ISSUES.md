# Known Issues

This document tracks security and design issues identified in the susu contracts through self-review. It is maintained as a transparent record of the protocol's current weaknesses and the path to resolving them.

Issues are formatted in the style of an audit finding: **Description**, **Impact**, **Status**, and **Notes** where relevant. Severity follows standard auditing convention (Critical / High / Medium / Low / Informational).

Status legend:

- `open` — identified, not yet addressed
- `in-progress` — actively being worked on
- `fixed` — resolved, with the commit/PR referenced

---

## Critical

### C-01: `claim()` pays out entire contract balance, including collateral

**Description.** The `_availablePot()` helper returns `i_asset.balanceOf(address(this))`, which is the contract's full token balance, contributions *and* all posted collateral pooled together. The first claimant of a pool can therefore drain the collateral that other members posted as a security deposit, leaving subsequent claimants with an empty pot.

**Impact.** A member claiming in an early round can walk away with both the round's contributions and other members' collateral, breaking the pool. Critical because it makes the contract fundamentally unsafe to use as-is.

**Status.** `open`. Round-pot bucket separation is the planned fix: contributions accumulate into an explicit per-round bucket; collateral is tracked separately and never enters payout math.

---

### C-02: Fee-on-transfer / rebasing token assumption

**Description.** `contribute()` validates that `amount == i_contribution * hands` and then calls `safeTransferFrom(amount)`, but never measures the post-transfer balance delta. If `i_asset` is a fee-on-transfer or rebasing token, the contract receives less than `amount` and the pot is silently underfunded each round.

**Impact.** Final claimants of a pool receive a short pot or revert on insufficient balance. Critical because some major stablecoins (USDT) retain transfer-fee mechanics in their code that could be enabled.

**Status.** `open`. Fix path: either restrict `i_asset` to an allowlist of known-standard ERC20s at the factory, or measure `balanceBefore`/`balanceAfter` on every inbound transfer and accept the actual delta.

---

## High

### H-01: `setRotation` can race the VRF fulfillment

**Description.** `setRotation` requires the pool to be `Locked` and `!s_poolReady`. Between `requestOrder` (which sets `s_poolReady = false`) and `fulfillHandOrder` (which sets it back to true), both conditions are satisfied — meaning the organizer can call `setRotation` and overwrite the rotation while a VRF request is in flight, bypassing randomness with a manually chosen order. `setRotation` also does not set `s_orderRequested`, so this is a clean bypass.

**Impact.** An organizer can manipulate the payout order in their favor (or in favor of a colluding member) by racing the VRF callback. Defeats the purpose of using Chainlink VRF.

**Status.** `open`. Fix path: add `!s_orderRequested` guard to `setRotation`, and require the two ordering mechanisms to be mutually exclusive.

---

### H-02: `requestOrder` has no access control

**Description.** `requestOrder` is `external` with no caller restrictions. Anyone — including non-members — can trigger a VRF request, which costs LINK on the subscription side and locks `s_orderRequested = true`, preventing the organizer from falling back to `setRotation`.

**Impact.** Griefing vector: an attacker can drain VRF subscription funds and block the organizer's fallback path with a single transaction.

**Status.** `open`. Fix path: restrict to `onlyOrganizer` (or at minimum `onlyMember`).

---

### H-03: No collateral withdrawal or slashing mechanism

**Description.** `postCollateral` allows members to deposit collateral, but there is no function to withdraw it after pool completion and no `slash` function to convert it into missing contributions on default. Collateral is one-way in.

**Impact.** Once a pool ends, all posted collateral is permanently trapped. Additionally, the security guarantee that collateral is supposed to provide (deterrent against early-claim-then-default) does not exist — collateral sits in the contract but cannot be used to make defrauded members whole.

**Status.** `open`. Slash design discussed; pending the foundation work (round-pot separation, claim-time lien recording) before implementation.

---

## Medium

### M-01: `isEligibleForHand` doesn't verify the member has paid the current round

**Description.** Eligibility gates on `collateral >= requiredCollateral(...)` but does not check `roundsPaid >= s_currentHand`. A member could skip `contribute()` for their own payout round and still claim.

**Impact.** Combined with C-01, a member can withdraw the entire balance without paying their own round's contribution. Independently of C-01, this allows a member to free-ride one round per pool.

**Status.** `open`. Trivially fixable once round-pot separation lands; the pot-completeness check naturally enforces this.

---

### M-02: `s_poolReady` flag has shifting semantics

**Description.** The boolean `s_poolReady` is written in three places (`join` when capacity is reached, `setRotation`, `fulfillHandOrder`) with two different meanings: "all members have joined" in the first case, and "rotation is set" in the latter two. An inline comment in the contract even acknowledges this ("now 'ready' means 'order set'"). A single boolean carrying two meanings is a classic source of state-machine bugs.

**Impact.** Existing logic happens to handle this correctly, but the ambiguity makes future changes fragile and is itself a latent bug.

**Status.** `open`. Fix path: split into `s_allJoined` and `s_rotationSet`, each with a single unambiguous meaning.

---

### M-03: Multi-hand member rotation handling

**Description.** `_indexOf(s_rotation, user)` returns only the *first* match. For a multi-hand member, this hides their additional positions in the rotation. `getMemberHand(user)` returns only their earliest hand.

**Impact.** View functions report misleading data for multi-hand members. More importantly, `requiredCollateral` is called with the first matching turn rather than the member's full combined exposure across all their hand positions — under-charging collateral for multi-hand members.

**Status.** `open`. Tied to the combined-obligation model decision: a multi-hand member's collateral requirement should be summed across all their remaining hand positions, not computed against a single `k1`.

---

### M-04: ~~`contributedRounds` field has muddy semantics~~ *(fixed)*

**Description.** The original `contributedRounds` field was incremented by `hands` in both `join()` and `contribute()`, conflating "rounds participated in" with "hand-rounds paid." This made it impossible to express the predicate "has member M paid everything they owe up to round R?" — which is the predicate `slash` requires.

**Impact.** Any future `slash` function built on the old counter would have needed off-chain or organizer judgment to determine delinquency, which is exactly the trust hole `slash` must not have.

**Status.** `fixed`. Renamed to `roundsPaid` with one unambiguous meaning: the number of rounds for which the member has paid their full `hands * contribution`. The `hands` multiplier now lives only in the money math (`amount == i_contribution * hands`), not in the counter. See commit history.

---

## Low

### L-01: Integer division in contribution amount

**Description.** `i_contribution = p.poolAmount / p.poolSize` silently truncates. For non-divisible values (e.g., `poolAmount = 100`, `poolSize = 3`), per-round pot totals 99 rather than 100.

**Impact.** Dust loss per round; cumulative over a full pool. Pool participants receive slightly less than the advertised `poolAmount`.

**Status.** `open`. Fix path: require `poolAmount % poolSize == 0` in the factory, or document the dust behavior in protocol docs.

---

### L-02: Duplicate zero-address check in constructor

**Description.** Constructor reverts on `oracle == address(0)`, then later contains a second check guarded by `isCollateralEnabled(...) && oracle == address(0)` — the second check can never fire because the first would have already reverted.

**Impact.** Dead code. No security impact, but suggests the oracle-required logic is unclear in intent.

**Status.** `open`. Fix path: decide whether oracle is unconditionally required or only required when collateral is enabled, and remove whichever check is redundant.

---

## Informational

### I-01: Missing events on state-changing functions

**Description.** `postCollateral`, `setRotation`, `start`, and `setVRFManager` do not emit events.

**Impact.** Off-chain indexing, monitoring, and post-mortem auditing are harder than they need to be.

**Status.** `open`. Fix path: emit an event for every state-mutating external function.

---

### I-02: `block.timestamp` used for round-interval gating

**Description.** Round advancement uses `block.timestamp`, which validators can manipulate within roughly a 12-second window.

**Impact.** No meaningful impact at the susu cadence (weekly/monthly intervals). Listed for completeness because auditors will always flag `block.timestamp` usage.

**Status.** `acknowledged`. No fix planned — manipulation window is negligible relative to round length.

---

### I-03: `uint8 i` loop counter at hand-count boundary

**Description.** The `for (uint8 i; i < hands; i++)` loop in `join()` uses a `uint8` counter. At `hands == 255` (the type maximum), the final `i++` does not overflow because the loop exits when `i == hands`, but it sits at the edge of the type.

**Impact.** Currently safe due to pool-size bounds (`MAX_POOL_SIZE = 25`), but using `uint256` for loop counters is the conventional safe pattern and is also gas-cheaper post-0.8.20.

**Status.** `open`. Fix path: change loop counter to `uint256`.