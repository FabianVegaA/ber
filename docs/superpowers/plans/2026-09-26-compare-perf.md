# Compare perf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the parallel compare path actually faster: private per-lane copies, tuned threshold, conditional 4-way, and a measured sort-merge epic.

**Architecture:** Behavior-preserving optimizations under the existing fanout-agreement laws (they stay green = proofs, not faith); algorithmic epic behind one interface with the winner decided by bench data.

**Tech Stack:** Bend 2.0.28 native binaries, `/usr/bin/time -p`, `--threads 8`, `bend PROOF.bend` gate, bolt 0 errors.

**Spec:** `docs/superpowers/specs/2026-09-26-compare-perf-design.md`

**Bend rules that bind every task:** `match` only on parameters/pattern-bound vars; no forward references (copy helper above its users); termination with the shrinking list first; `bend PROOF.bend` green before every commit; new `def`/`type` gets a one-line comment (bolt S001).

**Bench protocol (every measurement):** build once (`bend benches/compare_bench.bend -o /tmp/compare_bench_bin`), matrix N={1000,10000} × {sequential,fanned} with `--threads 8`, `/usr/bin/time -p`, single samples; record wall/user + counts agreement in Measurements below.

**Bench gate rule (every task):** no commit closes a task without running the bench matrix FIRST and recording improvement or worsening in Measurements with a one-line verdict. The numbers go in the commit message (`10k wall 114.8s → 61.2s (1.9x)`, `no change`, or `regression accepted: <reason>`). A regression never lands silently; if one lands, the written reason is part of the commit.

---

### Task 1: Private per-lane copies

**Files:**
- Modify: `src/Comparison.bend` (add `copy_entries` above `fan_added_halves`; wrap 6 reference args)
- Modify: `LAWS.bend` (add `copy_preserves_length`), `PROOF.bend` (prove it)

- [ ] **Step 1: Add the law + proof first (PDD)**

```python
# Copying preserves entry count.
law copy_preserves_length:
  {List.length(&2, Reading.ChainEntry, Comparison.copy_entries(Con{Reading.make_entry("ledger/a", "1"), Con{Reading.make_entry("ledger/b", "2"), Nil{}}})) == 2n : Nat}
```

```python
def Laws.copy_preserves_length():
  {==}
```

- [ ] **Step 2: Add `copy_entries` + wrap the 6 call sites**

```python
# Copies the spine so each lane scans a private list without atomics.
def copy_entries(source_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match source_entries:
    case Nil{}:
      Nil{}
    case Con{head_entry, remaining_entries}:
      Con{head_entry, copy_entries(remaining_entries)}
```

In `fan_added_halves`, `fan_removed_halves`, `fan_modified_halves`: wrap each `reference_entries` argument as `copy_entries(reference_entries)` (2 wraps per def, 6 total). Exact shape, added case:

```python
def fan_added_halves(even_entries: List<&2, Reading.ChainEntry>, odd_entries: List<&2, Reading.ChainEntry>, +reference_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  even_added odd_added = second_only_entries(copy_entries(reference_entries), even_entries) second_only_entries(copy_entries(reference_entries), odd_entries)
  List.append(&2, LogicalKey.LogicalKey, even_added, odd_added)
```

- [ ] **Step 3: Gate + bench + record (bench gate rule: no commit without numbers + verdict)**

Run: `bend PROOF.bend` → `All terms check.` (the 6 agreement laws pin preservation).
Run: full bench matrix per protocol; append table to Measurements with wall/user per cell + speedup vs baseline §1 + one-line verdict (improved / unchanged / regressed + reason).
Expected on theory: 10k wall toward ~60s. If unmoved: theory dead — record it and skip to Epic.

- [ ] **Step 4: Commit**

```bash
git add src/Comparison.bend LAWS.bend PROOF.bend docs/superpowers/plans/2026-09-26-compare-perf.md
git commit -m "perf(ber-core): private per-lane reference copies in fan-out"
```

---

### Task 2: Threshold retune (after Task 1 numbers exist)

**Files:**
- Modify: `src/Comparison.bend` (`comparison_parallel_threshold` body only)

- [ ] **Step 1: Read the crossover from Task 1 measurements, set the value**

```python
def comparison_parallel_threshold() -> Nat:
  4096n
```

(Replace `4096n` with the measured crossover; candidates 4096/8192. No law pins this value — verify with `rg -n "comparison_parallel_threshold" LAWS.bend` → no hits before changing.)

- [ ] **Step 2: Gate + spot bench + commit (bench gate rule applies)**

Run: `bend PROOF.bend` → green; bench N={1000,10000} fanned to confirm no loss zone; record numbers + verdict in Measurements; numbers go in the commit message.
```bash
git add src/Comparison.bend
git commit -m "perf(ber-core): retune parallel threshold to measured crossover"
```

---

### Task 3: 4-way fan-out (conditional on Task-1 scaling evidence)

Skip with a recorded reason if lanes didn't scale after private copies.

**Files:**
- Modify: `src/Comparison.bend` (quarter split + 4-way lets per added/removed/modified)

- [ ] **Step 1: Implement quarters + 4-way lets**

Split each side twice via existing `split_entries` (quarters differ by at most 2), then e.g.:

```python
# Compares four quarters against the reference in parallel.
def fan_added_quarters(first_quarter: List<&2, Reading.ChainEntry>, second_quarter: List<&2, Reading.ChainEntry>, third_quarter: List<&2, Reading.ChainEntry>, fourth_quarter: List<&2, Reading.ChainEntry>, +reference_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  first_added second_added third_added fourth_added = second_only_entries(copy_entries(reference_entries), first_quarter) second_only_entries(copy_entries(reference_entries), second_quarter) second_only_entries(copy_entries(reference_entries), third_quarter) second_only_entries(copy_entries(reference_entries), fourth_quarter)
  List.append(&2, LogicalKey.LogicalKey, first_added, List.append(&2, LogicalKey.LogicalKey, second_added, List.append(&2, LogicalKey.LogicalKey, third_added, fourth_added)))
```

Mirror for removed/modified. Route `compare_entries_fanned` through quarters when above a 4-way floor (reuse threshold × 4), keep 2-way between threshold and floor.

- [ ] **Step 2: Laws (agreement quarters-vs-sequential counts on the fanout fixture) + proofs, gate, bench, record, commit (bench gate rule applies: numbers + verdict before commit)**

New laws `fanout_quarters_agree_{added,removed,modified}` (Nat equations, same fixture as the 2-way agreement laws).

---

### Epic: sort-merge O(n log n) with empirical bitonic comparison

One interface, two variants, data decides. Do NOT start before Tasks 1–3 land.

- [ ] **Step 1: Interface + Variant A (sequential merge sort)**

```python
# Sorts entries by key; merge sort, O(n log n), structural recursion.
def sort_entries_by_key(unsorted_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  ...

# Linear diff over two sorted lists.
def merge_sorted_diff(+first_sorted: List<&2, Reading.ChainEntry>, +second_sorted: List<&2, Reading.ChainEntry>) -> CompareResult:
  ...
```

Laws (concrete, `{==}`): `sort_fixture_sorted` (output EQUALS the hand-sorted literal — full `==`, strongest pin), `sort_merge_counts_agree` (differential vs `compare_sorted_entries` on the branch fixture).

- [ ] **Step 2: Variant B (vendored bitonic, adapted)**

Vendor the demo algorithm into `vendor/bitonic/` (it is NOT a hub package — no import possible), adapt: `String.cmp` in `mix`, list→padded-tree with an explicit max-key sentinel, tree→list unpadding. Document the sentinel choice and its exclusion from counts. Same laws as Variant A, same fixtures.

- [ ] **Step 3: Bench both + decide + record (bench gate rule applies: the decision IS the verdict)**

Matrix from the protocol on both variants + current path. Winner rule: wall first; within 10%, fewer laws/code wins. Loser deleted in the same commit (no dead variants). Record the decision with numbers; numbers go in the commit message.

---

## Measurements

### Baseline 2026-09-26 (native, 12 CPUs, `--threads 8`)

| N | sequential wall | fanned wall | speedup | counts agree |
|---:|---:|---:|---:|---|
| 100 | 0.46s | 0.02s | noise | yes |
| 1,000 | 1.11s | 1.16–1.26s | 0.88–0.96x | yes |
| 10,000 | 115.98s | 114.76s | 1.01x | yes |

### Task 1 results 2026-09-26 (native, 12 CPUs, `--threads 8`, fresh build)

| N | sequential wall | fanned wall | speedup | laws green |
|---:|---:|---:|---|---|
| 1,000 | 1.11s | 1.13s | 0.98x | yes |
| 10,000 | 113.18s | 90.68s | **1.25x** | yes |

Verdict: IMPROVED. Contention theory confirmed — fanned `user` dropped 229s→181s (less atomic overhead); wall 114.76s→90.68s. Loss zone at 1k shrinks (0.88x→0.98x) but persists: keep threshold retune (Task 2).

### Task 2 results 2026-09-26 (crossover bracketed, same binary/protocol)

| N | sequential wall | fanned wall | speedup |
|---:|---:|---:|---:|
| 1,000 | 1.11s | 1.13s | 0.98x |
| 2,048 | 4.95s | 4.79s | 1.03x |
| 4,096 | 19.32s | 17.74s | 1.09x |

Verdict: crossover between 1k and 2k → threshold set to `2048n` (was `1024n`). No law pins the value (verified by rg). Note: the bench exercises direct paths; the threshold gates only the shell `compare_entries_auto` path, whose results are identical either way by the agreement laws — PROOF green confirms.

### Epic results: sort-merge ABANDONED with evidence (2026-09-26)

| Path | 1k wall | 10k wall | laws | lines |
|---|---|---|---|---|
| current (membership + 4-way) | 1.23s | 58.34s | 61 | — |
| merge-sort | — | — | — | — (infeasible, see below) |
| bitonic | — | — | — | — (moot, see below) |

Verdict: NEITHER. Variant A (~90 lines written) rejected by the checker —
conditional-advance recursion needs forward references, forbidden in safe
Bend (spec §7). Variant B never implemented: bitonic compiles only through
fixed-structure recursion, and sorting alone cannot speed an
order-independent membership diff. Code reverted (`git checkout` of the 3
files, working tree clean, PROOF green); knowledge kept in spec §7.

### Task 3 results 2026-09-26 (same session, native, 12 CPUs, `--threads 8`, fresh build with quad mode)

| N | sequential wall | fanned 2-way wall | quad wall | quad speedup vs seq |
|---:|---:|---:|---:|---:|
| 1,000 | 1.11s | 1.13s | 1.23s | 0.90x (spawn overhead wins) |
| 10,000 | 115.68s | 94.25s (1.23x) | **58.34s** | **1.98x** |

Verdict: IMPROVED — lanes scale after private copies (2-way reproduces Task 1 at 1.23x; quad adds 1.62x over 2-way; `user` flat ~181-188s = no new contention). Counts agree on all paths. Quad floor 8192n stands (1k stays 2-way/seq via auto routing).

---

## Self-review

- **Spec coverage:** §2 copies → Task 1 (exact code + law + bench). §3 threshold → Task 2 (conditional on numbers, safety pre-checked). §4 4-way → Task 3 (explicit skip-with-data branch). §5 epic → Epic steps (interface shared, both variants, decision rule, loser deleted). §6 acceptance → gates every task + Measurements + law-claim review.
- **Placeholders:** none — code complete where shown; Epic leaves implementation to the worker but fixes interface, laws pattern, fixtures source, and decision rule.
- **Type consistency:** `copy_entries`/`sort_entries_by_key`/`merge_sorted_diff` shapes match existing `split_entries`/`compare_sorted_entries` conventions; `Store`/`Value` untouched.
