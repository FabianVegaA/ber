# Compare perf — design (fan-out scaling + sort-merge epic)

Date: 2026-09-26. Branch: `perf/compare-fanout` (from tag-0.1.0.0 lineage + LICENSE). Status: approved for implementation.
Scope: `src/Comparison.bend` hot path only. Out of scope: GPU (`!`, divergent workload per spec §6), ber-cli IO facade, `pack.json`/publish, `SchemaLaw`, parquet-row parsing.

## 1. Diagnosis (measured 2026-09-26, native binary, 12 CPUs)

| N | sequential | fanned (8 threads) | wall speedup |
|---:|---:|---:|---:|
| 100 | 0.46s | 0.02s | noise (startup dominates) |
| 1,000 | 1.11s | 1.16–1.26s | 0.88–0.96x (spawn overhead wins) |
| 10,000 | 115.98s | 114.76s | 1.01x |

Counts agree on every run (`modified = N/5`). The fanned path burns 2x CPU (`user` 229s vs 116s) for 1x wall: both lanes work, but total work doubles. Prime suspect, confirmed in code (`src/Comparison.bend:162-163,177-178,192-193`): both parallel lanes scan the SAME `+reference_entries` list — every element read costs an atomic (`bend guide` warns exactly this), so O(n²) atomic reads serialize the lanes. The fix is the experiment that confirms or kills this theory.

## 2. Task 1 — private per-lane copies (high value, small diff)

Clone the reference list (O(n), negligible vs O(n²) scans) so each lane scans a private spine with zero atomics:

```python
# Copies the spine so each lane scans a private list without atomics.
def copy_entries(source_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match source_entries:
    case Nil{}:
      Nil{}
    case Con{head_entry, remaining_entries}:
      Con{head_entry, copy_entries(remaining_entries)}
```

Applied at the 6 parallel call sites (`fan_added/removed/modified_halves` wrap `reference_entries` in `copy_entries`), e.g.:

```python
even_added odd_added = second_only_entries(copy_entries(reference_entries), even_entries) second_only_entries(copy_entries(reference_entries), odd_entries)
```

PDD: one new law `copy_preserves_length` (`length(copy(x)) == length(x)` on a fixture, `{==}`); the 6 existing fanout-agreement laws must stay green — that IS the behavior-preservation proof. Verify: bench 1k/10k before/after. Expectation if theory holds: wall 10k toward ~60s (ideal 2-way). If wall doesn't move, contention theory dies and we record why.

## 3. Task 2 — threshold retune (trivial, after Task 1)

`comparison_parallel_threshold() = 1024n` with a measured loss zone ≤1k. No law pins its value — safe to change. Set to the crossover re-measured after Task 1 (candidates 4096/8192).

## 4. Task 3 — 4-way fan-out (medium, conditional on scaling evidence)

Only if Task 1 shows lanes scaling: double alternating split into quarters, 4 parallel lets per added/removed/modified, append unions. If lanes still don't scale after private copies → memory-bandwidth-bound → discard WITH data, not opinion.

## 5. Epic — sort-merge O(n log n) with empirical bitonic comparison

The real algorithmic fix (sort once + linear merge instead of quadratic scans). Decided with user: implement BOTH variants behind one interface, decide by measurement, not debate.

- Variant A — sequential merge sort over `List<ChainEntry>` by key (`String.cmp`, already used in `StateTree`). No padding, structural recursion the checker accepts, CPU. Laws: sorted-output-equals-literal on fixtures + differential count laws vs the current path.
- Variant B — vendored bitonic adapted from the Bend `pure_par_sort` demo (fixed 2^d Nat trees, GPU-oriented, proofs cover sum-preservation only — NOT sortedness). Adaptation cost is real: list→padded-tree with a max-key sentinel, `String.cmp` in `mix`, tree→list unpadding preserving the counts the fanout laws pin. No hub package exists; vendor + adapt.
- Protocol: same fixtures, same metrics (wall/user at 1k/10k) + proof cost (laws needed) + code delta as tiebreakers. Winner rule: wall first; within 10%, fewer laws/code wins. Universals stay deferred under the inversion wall either way (concrete instances only).

## 6. Acceptance

`bend PROOF.bend` green after every task (existing agreement laws pin behavior; new laws for new defs); `bolt` 0 errors; every bench table recorded in the plan doc Measurements section; `LAWS.bend` claims reviewed (worker writes, human reviews per standing delegation).

## 7. Sort-merge via confined @unsafe (revives the negative result below)

Update 2026-09-26 (user decision): ship the working sort even under
`@unsafe` as long as results improve. Each `@unsafe` mark cites the forward
reference it needs; behavior is pinned by concrete laws (sorted-output
literal + differential counts vs membership). Boundary note:
`@unsafe` here waives order/termination checking per-def, exactly like kit's
encoder — normalization still closes every `{==}` law (66 green).

Original negative result (superseded, kept for the record): sequential
merge sort + linear diff were first written fully safe and REJECTED — helpers
matching a computed comparison cannot call back into the function needing
the branch result (checker: "live code cannot use it"). So conditional
advance stays inexpressible in SAFE Bend; fixed-structure recursion (bitonic,
membership scans) compiles. Variant B (bitonic) never implemented: sorting
alone is pointless without linear diff, and with linear diff revived under
`@unsafe`, a second variant adds proof cost for no expected gain.

Attempted: sequential merge sort + linear two-pointer diff (Variant A), then
adapted bitonic (Variant B). Variant A was written (~90 lines: merge_order /
merge_dispatch / merge_by_key / sort_split_halves / sort_fuel /
merge_sorted_diff chain) and REJECTED by the checker: "an unfilled law is a
dead claim: live code cannot use it" — safe defs cannot call defs declared
below them, so any helper matching a computed comparison cannot call back
into the function that needs the branch result.

The precise boundary: **recursion whose arguments depend on a computed
comparison (conditional advance) is inexpressible** — this kills linear
merge, recursive merge sort, binary search and trie lookup alike. Control
case proving the rule: the bitonic demo COMPILES because its recursion is
fixed-structure (every node visited unconditionally); comparisons only
SELECT values through arguments (`pick`), never steer recursion. Same
reason our membership diff compiles (full scans + value-select params).

Consequences: the membership-diff shape is final in safe Bend; remaining
levers were parallelism over fixed structure (Tasks 1–3, now obsolete) and
the sorted path (shipped). Variant B WAS later implemented per user request
for an empirical comparison (`vendor/bitonic/`, String keys, `~` sentinel,
4 laws green, counts agreed) and measured: 1.33s at 10k vs 0.15s merge-sort
(~9x slower: 64% padding waste + O(n log²n)). Deleted same commit per epic
rule. This extends the inversion wall (spec §5.1) with a second
language-expressiveness boundary.
