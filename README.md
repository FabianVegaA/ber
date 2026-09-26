# ber-core

Version-controlled state with machine-checked merge proofs, written in [Bend](https://github.com/bendlang/bend).

ber-core is a convergence + proof primitive on top of MyLSM: content-addressed objects, flat Merkle state trees, linear and three-way (`union-disjoint`) commits, and merge certificates that re-verify independently. It never lies: `merge_commits` returns `MergeSuccess | MergeConflict | MergeUnprovable`, and a certificate asserts nothing it cannot recompute.

## The spec is executable

`LAWS.bend` states the properties, `PROOF.bend` proves them. The full merge truth table — every (base, first, second) presence/value cell — plus certificate accept/reject cases and a reflexivity tower (`Word → U32 → Char → String`) are machine-checked on every commit:

```bash
bend PROOF.bend   # All terms check.
```

No commit lands without a green gate (see `AGENTS.md`). `bolt` lints the tree with `correctness` findings as errors (see `bolt.bend`).

## Quickstart

```python
import Base
import ./src/Staging.bend as Staging
import ./src/History.bend as History
import ./src/LogicalKey.bend as LogicalKey
import ./src/Merging.bend as Merging
import mylsm-lsm-store@0.3.1.0/mylsm.bend as MyLsmStore

def scenario() -> MyLsmStore.Sess<&2, String>:
  do MyLsmStore.Sess<&2, String>:
    staged : LogicalKey.LogicalKey <- Staging.put_record("session_one", "ledger", "record_a", "version_one")
    commit : History.Commit <- History.create_commit("session_one", Nil{}, Nil{})
    read_back : Maybe<&2, String> <- History.read_value_at("ledger", "record_a", History.commit_identifier_of(commit))
    return "done"

def main() -> IO(Unit):
  opened_store = MyLsmStore.open("demo")
  ...
```

See `tests/*_check.bend` for complete runnable scenarios (reads across history, tombstones, diffs, merges, certificate verification).

## Storage layout (MyLSM)

| Key | Value |
|---|---|
| `object/{content_hash}` | canonical JSON ContentObject |
| `tree/{tree_hash}` | canonical JSON StateTreeNode |
| `commit/{commit_id}` | canonical JSON Commit |
| `index/{namespace}/{record}/{commit}` | value hash or `TOMBSTONE` |
| `stage/{session}/{namespace}/{record}` | staged value hash or `TOMBSTONE` |
| `stage-index/{session}` | canonical JSON list of staged keys |

## Pins (hash = trust anchor)

| Package | Pin |
|---|---|
| mylsm | `mylsm-lsm-store@0.3.1.0` = `0x0ae7ac793853e753f5f74c16e06ee078` |
| bend-kit-json | `bend-kit-json@0.3.0.0` = `0xaaa10a97bf5ac6990143da2c863f8a3f` (behind `src/JsonAdapter.bend`) |
| bend-codec-lib | `bend-codec-lib@0.2.0.0` (UTF-8 for the SHA glue) |
| SHA-256 | mylsm's vendored `hub_sha` (FIPS 180-4 proven upstream) — single source, no copy |

## Project map

| File | Responsibility |
|---|---|
| `src/LogicalKey.bend` | key encoding + physical layout builders |
| `src/ContentHash.bend` | SHA-256 hex over UTF-8 bytes (trusted core + tiny glue) |
| `src/JsonAdapter.bend` | sole owner of JSON operations (kit boundary) |
| `src/ContentObject.bend` | content-addressed objects |
| `src/StateTree.bend` | flat sorted tree, hash, serde |
| `src/Staging.bend` | uncommitted working set |
| `src/History.bend` | commits, versioned reads, chain walk |
| `src/Comparison.bend` | membership diff + parallel fan-out |
| `src/Merging.bend` | three-way union-disjoint merge + LCA |
| `src/Certificate.bend` | independent merge verification |
| `src/EqTheory.bend` | reflexivity tower for proofs |

## Benchmarks

```bash
bend benches/compare_bench.bend -o /tmp/compare_bench_bin
/tmp/compare_bench_bin 10000 fan
```

Sequential vs fanned compare; see the v0.3 notes in `docs/superpowers/plans/2026-09-25-ber-core.md`.

## Roadmap

v0.4 `SchemaLaw` extension point, v1.0 frozen API + BendHub board. Design and verification walls documented in `docs/superpowers/specs/`.
