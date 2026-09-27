# ber-core

ber-core is a library that merges data states changed separately and mathematically proves the result correct, instead of just trusting that it is. Written in [Bend](https://github.com/bendlang/bend), on top of MyLSM.

What it does: given two versions of the same dataset (rows, records, any key-value pair), it computes their difference, combines them, and returns a verifiable certificate that the combination loses and corrupts nothing — or it tells you explicitly when it cannot guarantee that.

Who uses it: not the end user, but whoever builds tools on top — developers of a version control system for data (`ber-cli`), collaborative editors, multi-leader databases, or systems where a silently wrong merge is unacceptable (finance, ML, infrastructure as code).

It never lies: `merge_commits` returns `MergeSuccess | MergeConflict | MergeUnprovable`, and a certificate asserts nothing it cannot recompute.

## The spec is executable

`LAWS.bend` states the properties, `PROOF.bend` proves them. The full merge truth table — every (base, first, second) presence/value cell — plus certificate accept/reject cases and a reflexivity tower (`Word → U32 → Char → String`) are machine-checked on every commit:

```bash
bend PROOF.bend   # All terms check.
```

No commit lands without a green gate (see `AGENTS.md`). `bolt` lints the tree with `correctness` findings as errors (see `bolt.bend`).

## Quickstart

One import for the public API (`ber.bend`), one each for the session and value types:

```python
import Base
import ./ber.bend as Ber
import ./src/Store.bend as Store
import ./src/Value.bend as Value

def print_report(run_pair: Store.Handle & String) -> IO(Unit):
  match run_pair:
    case (unused_store, report_text):
      IO.print(report_text)

def main() -> IO(Unit):
  opened_store : Store.Handle = Store.open_store("demo")
  print_report(Store.run_op(&2, String, opened_store, do Store.Op<&2, String>:
    +base_id : String <- Ber.commit_value("s1", "ledger", "r1", Value.Text{"v1"}, Nil{})
    +first_id : String <- Ber.commit_value("s1", "ledger", "r1", Value.Text{"v2"}, Con{base_id, Nil{}})
    +second_id : String <- Ber.commit_value("s1", "ledger", "r2", Value.Text{"w1"}, Con{base_id, Nil{}})
    read_back : Maybe<&2, Value.Value> <- Ber.read_value_at("ledger", "r1", first_id)
    diff_line : String <- Ber.compare_summary(first_id, second_id)
    merge_line : String <- Ber.merge_and_verify(first_id, second_id)
    return Ber.format_report(read_back, diff_line, merge_line)))
```

Values are multi-type (`Text`, structured `Object`, binary `Blob`), never bare text — see `src/Value.bend`. See `tests/*_check.bend` for complete runnable scenarios (reads across history, tombstones, diffs, merges, certificate verification).

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
| bend-codec-lib | `bend-codec-lib@0.2.0.0` (UTF-8 for the SHA glue, hex for binary values) |
| SHA-256 | mylsm's vendored `hub_sha` (FIPS 180-4 proven upstream) — single source, no copy |

## Project map

| File | Responsibility |
|---|---|
| `ber.bend` | public API: domain delegates + composed operations |
| `src/Store.bend` | session monad (`Op`/`Handle`); the only file naming MyLSM |
| `src/Value.bend` | multi-type stored values (text, document, blob) |
| `src/LogicalKey.bend` | key encoding + physical layout builders |
| `src/ContentHash.bend` | SHA-256 hex over UTF-8 bytes (trusted core + tiny glue) |
| `src/JsonAdapter.bend` | sole owner of JSON operations (kit boundary) |
| `src/ContentObject.bend` | content-addressed objects |
| `src/StateTree.bend` | flat sorted tree, hash, serde |
| `src/Staging.bend` | uncommitted working set |
| `src/History.bend` | commits, versioned reads, chain walk |
| `src/Comparison.bend` | sorted-path diff (default) + membership oracle |
| `src/Merging.bend` | three-way union-disjoint merge + LCA |
| `src/Certificate.bend` | independent merge verification |
| `src/EqTheory.bend` | reflexivity tower for proofs |

## Benchmarks

```bash
bend benches/compare_bench.bend -o /tmp/compare_bench_bin
/tmp/compare_bench_bin --threads 8 10000 sort   # sorted path (default)
/tmp/compare_bench_bin --threads 8 10000        # sequential reference
```

Sequential reference vs sorted-path compare; numbers in `docs/superpowers/plans/2026-09-26-compare-perf.md`.

## Roadmap

v0.4 `SchemaLaw` extension point, v1.0 frozen API + BendHub board. Design and verification walls documented in `docs/superpowers/specs/`.
