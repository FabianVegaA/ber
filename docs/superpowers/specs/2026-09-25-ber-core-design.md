# ber-core — Adjusted spec (ber-core only on top of MyLSM)

Date: 2026-09-25. Status: draft for review before planning.
Scope: exclusively `ber-core` as a pure client of MyLSM. Out of scope: `ber-cli`, CSV/Parquet parsers, networking, auth, dashboard.

Naming convention: public API has NO `ber_` prefix. All code, types, functions, variables use verbose English. No abbreviations (`session_handle`, not `sess`; `namespace_name`, not `ns`; `record_identifier`, not `id`).

Target: Bend 2.0.27 (`bend guide` is authoritative; this spec follows it).

## 1. Positioning (5 minutes)

`ber-core` is the convergence + proof primitive isolated as a Bend library.
It never lies: `merge_commits` returns `MergeSuccess(resulting_commit, certificate) | MergeConflict(conflicting_keys) | MergeUnprovable(reason)`.
All durable state lives in MyLSM. `ber-core` owns no WAL/SSTable.

## 2. MyLSM dependency (fixed)

- `ber-core` imports `mylsm` pinned by hash. No fork, no patch.
- Session level for staging (`stage/...`), session/direct level for reads of `object/...`, `tree/...`, `commit/...`, `index/...`.
- Durability = whatever MyLSM provides. A lost confirmed write is a MyLSM bug, never a `ber-core` bug.
- GPU detection: honor `MYLSM_DEVICE=cpu`. `ber-core` never schedules I/O on GPU.
- PINNED (2026-09-26): `import mylsm-lsm-store@0.3.1.0/mylsm.bend as MyLSM` = hash `0x0ae7ac793853e753f5f74c16e06ee078` (hash is the trust anchor; the readable name is convenience). Import checks green on Bend 2.0.28. Delta v0.3.0.0→v0.3.1.0 verified: top-level API byte-identical; .bend changes additive-only (fail-closed batch checksum verdict, parallel probe counters, SHA vendored under `src/hub_sha/` with the `Window`→`ShaWindow` rename for the Base 2.0.28 collision); effs `.c`/`.js` changes are toolchain-driven (`CID_UNIT`→`CID(Unit)` codegen naming). ber-core reuses `.../src/hub_sha/sha256.bend` by subpath import as its SHA core — single source, no ber-core copy. Previous pins: v0.3.0.0 (`0x8bf6...`), v0.2.0 (`0x7279...`).
- Session shape (correction to earlier drafts): there are NO handles and NO `IO` session effects. State is a monad `Sess{run: Db -> (Db & A)}` — ber-core composes `Sess` actions (`sput/sdel/sbatch/sget`) in `do`-blocks; the monad threads `Db` internally. Point lookups return `Maybe` (deleted and missing are both `None` — our per-commit tombstones live one layer up, in `index/` values, so chain-walking keeps its stop signal). Only `src/MyLsmBinding.bend` names `MyLSM`; rest of the code uses `store_value/remove_value/load_value/store_batch` wrappers.
- Earlier risk (no MyLSM on public hub) RESOLVED by the pin above. `src/FakeSession.bend` (in-memory interpreter of the same action set) stays as a fast logic-check harness (no FS effects), not as a blocker. Optional naming (`mylsm@0.2.0` via `bend login` + `bend link`) is cosmetic — hash imports work without it; skip unless publishing convenience demands it. (Hub pins content immutably and `bend` checks a fetched package as it checks you, so the pin locks trust permanently.)
- Session handles are affine (`Type`, not `Data`): each function threads the handle through and hands it back; nothing copies a live handle.

## 2.1 External dependencies (decision record, 2026-09-25)

Trust rule: an external library is adopted only if its formal checking is verified by us (repo fetched, proof gate green at the pinned hash). A pinned hash freezes content, never quality. What the library proves, we do not re-prove; the glue between the library and our code is ours and stays tiny + differentially tested.

| Need | Candidate | Proof status (verified by us) | Decision |
|---|---|---|---|
| SHA-256 | `bend-sha256` v0.1.0, `0xda83506fb9f059ead7afcfa2f498df5f/sha256.bend` | VERIFIED: repo fetched, machine-checked proof vs independent FIPS 180-4 spec, `CORRECTNESS.bend` + `PROOF.bend` gates, 142 packed cases/backend + mutation rejection. Perf: ~0.9µs/64B, ~8.8µs/KiB (≈2x vs C, absolute cost negligible vs MyLSM I/O). Boundary: packed-input theorem only; String→word packing is our glue. | ADOPT. Import by hash in `src/ContentHash.bend`. Never hand-roll SHA-256. Re-run their `PROOF.bend` locally once (they checked on Bend 2.0.16, we run 2.0.27) before trusting. |
| Sorted map / tree map | `bend-collections` indexed red-black tree (`balanced_search_tree.bend`, hub `0x9ee2...`) | VERIFIED as proven code: repo fetched (Giulio2002, 205 commits), per-package `proof.bend` under root `proofs/PROOF.bend` + `END_TO_END.bend`, `prove.py`, differential tests vs C with matching checksums. Toolchain pinned 2.0.25 (we run 2.0.27 — re-run gate locally before trusting). | REJECT on performance + proof-ownership grounds (see below). NOT a trust problem. |
| Sorted-list merge / compare / union cores | hand-rolled pure recursion | n/a (these carry Laws 1–3) | REINVENT (~50 lines). Two decisive reasons. (1) Proof ownership: Laws 1–3 quantify over OUR merge/compare semantics — a generic container cannot discharge them; the proof work stays ours either way. (2) Performance fit: our entries live as serialized SORTED LISTS in MyLSM. Linear merge is O(n) with tiny constants; routing through a tree map pays build O(n log n) + flatten, and their own benchmarks show `to_list` 16–27x vs C and `range` up to 20x vs C, while point ops we never do (insert/lookup) are the only fast part. Wrong shape for our access pattern. |
| In-memory String→value map (if ever needed hot) | `bend-collections` `hash_table.bend` | VERIFIED (same gate as above). Perf: 5–25x faster than `Base.Map` on point ops (their maps/compare benchmark). | CONDITIONAL: adopt by single-module hash import ONLY if a >100-entry String-keyed map appears in a hot path (candidate: v0.4 `SchemaLaw` registry). Until then, plain association lists — simpler proofs, zero pinning. Never `Base.Map` for hot paths (crit-bit tree, 400–1800ns/op). |
| FIFO/stack/deque for ancestor walk | `bend-collections` queue/stack (0.5–1.4x vs C — excellent) | VERIFIED (same gate) | NOT NEEDED. Ancestor walk follows a single-parent chain — a visited list + recursion is O(depth) and optimal; a queue buys nothing. |
| LRU / bitset / bitlist / heaps / Keccak / BLAKE | `bend-collections` | VERIFIED (same gate) | NOT NEEDED. No cache layer (MyLSM owns block cache), no bitmap/heap/alt-hash use in scope. SHA-256 stays the sole addressing hash (FIPS + Git-philosophy + existing proofs). |
| Signed 64-bit integers | hub `0x5a02f49892413b8561a33a7642d823e2` ("SIGNED 64-bit integer in pure Bend, two's complement") | UNVERIFIED (hub page only; no repo/gate observed) | NOT NEEDED. All counters/timestamps are U64/Nat; zero signed arithmetic in scope. |
| Keccak-256 standalone package | hub `0x48cee57f42dae6ba4c727fbf982cdd4d?f=keccak.bend` (presumably bend-keccak) | PRESUMED (same author line; not individually verified) | NOT NEEDED. Single-hash discipline: SHA-256 only. |
| `bolt` rules, e.g. `bolt/rules/suspicious/unused.bend` (looks like a Bend linter) | hub `0x729eecea86ea5a2cdba3a2856a313bca` | UNVERIFIED (identity and purpose unconfirmed) | NOT A DEPENDENCY. Evaluate separately as a CI dev-tool at most; never imported into shipped code without a verified gate. |
| Deterministic serialization codecs (objects/trees/commits, hex) | none found on hub | n/a | REINVENT (tiny). Covered by roundtrip laws in OUR `LAWS.bend` — `parse(serialize(x)) == x` per type. Cheap, high-value, zero external trust required. |
| Test frameworks / assertion helpers | none needed | n/a | NOT NEEDED. `LAWS.bend` + `PROOF.bend` + `def main() -> IO(Unit)` checks are the native framework; a third-party harness adds trust surface for zero proof value. |
| Hex / Base64 / UTF-8 codec | `bend-codec-lib@0.2.0.0` (= `0x888714bde93f46c139372bb9fdc57a19`), 777genius | VERIFIED import-checks green on 2.0.27 (probe 2026-09-25); upstream: closed roundtrips proved, fixtures tested JS+native (upstream checked on 2.0.5 — re-run `./tools/e2e` locally before trusting) | ADOPT `utf8.bend` (String→bytes packing for the SHA-256 glue) + `hex.bend` for any hex needs. Replaces hand-rolled byte-packing core. |
| JSON parser/serializer | `bend-kit-json@0.3.0.0` = `0xaaa10a97bf5ac6990143da2c863f8a3f` (`bend-net-json@0.3.0.0` is byte-identical except header) | VERIFIED: import-checks green on 2.0.28; byte probe kit vs vendored rootagi PASSED 2026-09-26 on all 4 persisted doc shapes (content-object, commit, tree, stage-index) — canonical bytes identical, hash namespace unchanged | ADOPT (version import) behind `src/JsonAdapter.bend`, the only module calling kit operations. `vendor/json/` deleted 2026-09-26. Boundary: `encode` is `@unsafe` upstream (work-list walk); confined to the adapter, canonical-bytes property covered by probe + differential check vs Python `json`, not by proof. |
| Proof lemmas (Nat/List/Bool/String) | `caiodomingues/bend-lemmas` (repo verified: `bend all.bend` green claim, honest open laws flagged in `map.bend`) + `bend-mathlib` `0xafc61ca8b7738a6df7f28eddf80168f8/nat.bend` as supplement | PARTIAL: READMEs verified; bend-lemmas hub hash still missing (obtain from its releases/publish line, then probe-check) | ADOPT proof-only (zero runtime trust surface — lemmas are compiler-checked functions). Our `PROOF.bend` imports `append_assoc`, `length_append`, String `++` laws instead of re-proving them. Prefer bend-lemmas (list/string focus); mathlib as fallback. |
| Parser combinators (cursor/digits) | `777genius/bend-parse` | UNEVALUATED (README fetch failed) | DEFERRED. Unneeded while JSON is the format — its parser subsumes cursor/digit needs. Revisit only for a second format. |
| Lists, Strings, Arrays | Base (stdlib) | Trusted with the toolchain | USE freely. |

Consequence: `src/ContentHash.bend` is a two-part module — trusted core (`ProvenSha256.sha256`/`hex` by hash import) plus owned packing glue covered by a differential test vs `hashlib` (fixtures at 55/56/64-byte padding boundaries).

## 3. Data model (Bend 2.0.27 syntax)

Bend types need explicit kinds. Value types below are `Data` (copyable); handles stay `Type`.

```python
import Base

type LogicalKey is Data:
  Make{namespace_name: String, record_identifier: String}

type ContentObject is Data:
  Make{content_hash: String, payload: String, references: List<String>}

type StateTreeNode is Data:
  Make{tree_hash: String, entries: List<String & String>, children_hashes: List<String>}

type Commit is Data:
  Make{commit_identifier: String, parent_commit_identifiers: List<String>, tree_hash: String, timestamp: Nat, metadata: List<String & String>, certificate_hash: Maybe<String>}

type MergeResult is Data:
  MergeSuccess{resulting_commit: Commit, certificate: MergeCertificate}
  MergeConflict{conflicting_keys: List<LogicalKey>}
  MergeUnprovable{reason: String}

type MergeCertificate is Data:
  Make{first_parent_commit: String, second_parent_commit: String, base_commit: String, result_tree_hash: String, strategy_name: String, checked_laws: List<String & Bool>}

type CompareResult is Data:
  Make{added_keys: List<LogicalKey>, removed_keys: List<LogicalKey>, modified_entries: List<ModifiedEntry>, pruned_subtree_count: Nat, compared_entry_count: Nat}
```

Notes:
- `entries` are sorted by encoded key `namespace_name ++ "/" ++ record_identifier`. Sorting is a pure recursive function over lists (`Con{h, t}` / `Nil{}` patterns), never an in-place sort.
- `children_hashes` is empty in v0.1 (flat tree); partitioning by range arrives in v0.3.
- Strings concatenate with `++`, never with interpolation. Hashes are lowercase hex `String`.
- No `for` loops exist in Bend. All repetition is recursion with a structurally smaller argument first (termination is mandatory; `@unsafe` is forbidden in `ber-core`).

### 3.1 Physical layout in MyLSM (single source of truth)

All keys are ASCII strings with `/` separator to allow prefix scan. Key builders are pure functions:

```python
import Base

def build_object_storage_key(content_hash: String) -> String:
  "object/" ++ content_hash

def build_tree_storage_key(tree_hash_value: String) -> String:
  "tree/" ++ tree_hash_value

def build_commit_storage_key(commit_identifier: String) -> String:
  "commit/" ++ commit_identifier

def build_index_storage_key(namespace_name: String, record_identifier: String, commit_identifier: String) -> String:
  "index/" ++ namespace_name ++ "/" ++ record_identifier ++ "/" ++ commit_identifier

def build_stage_storage_key(session_identifier: String, namespace_name: String, record_identifier: String) -> String:
  "stage/" ++ session_identifier ++ "/" ++ namespace_name ++ "/" ++ record_identifier
```

- `object/{content_hash}` → serialized `ContentObject`
- `tree/{tree_hash}` → serialized `StateTreeNode`
- `commit/{commit_identifier}` → serialized `Commit`
- `index/{namespace}/{record}/{commit}` → `value_hash` or `TOMBSTONE`
- `stage/{session}/{namespace}/{record}` → `value_hash` or `TOMBSTONE` (uncommitted working set)

Tombstone: literal `TOMBSTONE`. `read_value_at` finding `TOMBSTONE` returns `None{}`.

Serialization format: canonical JSON via `bend-kit-json@0.3.0.0` behind `src/JsonAdapter.bend`. Objects/trees/commits persist with `encode_canonical` (keys emitted in char-code order by construction), so equal content ⇒ byte-identical text ⇒ stable content hashes. Payloads stay strings-only (no numbers, no raw nodes). Byte-compatibility with the pre-migration vendored encoder was probe-verified on every persisted shape before the cutover (2026-09-26). Perf caveat: very large inputs are slow — entries stay small line-shaped strings by construction; the v0.3 bench measures real tree sizes.

## 4. Public API (frozen at v1.0, minimal at v0.1) — no prefix, verbose English

```python
import Base

def put_record(session_handle: Session, session_identifier: String, namespace_name: String, record_identifier: String, value: String) -> IO<LogicalKey>:
  ...

def delete_record(session_handle: Session, session_identifier: String, namespace_name: String, record_identifier: String) -> IO<LogicalKey>:
  ...

def create_commit(session_handle: Session, session_identifier: String, parent_commit_identifiers: List<String>, metadata: List<String & String>) -> IO<Commit>:
  ...

def read_value_at(session_handle: Session, namespace_name: String, record_identifier: String, commit_identifier: String) -> IO<Maybe<String>>:
  ...

def read_tree_at(session_handle: Session, commit_identifier: String) -> IO<StateTreeNode>:
  ...

def compare_commits(session_handle: Session, first_commit_identifier: String, second_commit_identifier: String) -> IO<CompareResult>:
  ...

def merge_commits(session_handle: Session, first_commit_identifier: String, second_commit_identifier: String, strategy_name: String) -> IO<MergeResult>:
  ...

def verify_certificate(session_handle: Session, certificate: MergeCertificate, commit_to_verify: Commit) -> IO<Bool>:
  ...
```

Adjustment notes:
- Everything touching MyLSM returns `IO<...>` and sequences effects with `do` blocks; pure helpers (hashing, key building, list merging) stay pure. Fallible reads answer `Maybe`/`Result`, unwrapped with `<-` binds or `IO.try`.
- `put_record` writes to `stage/` only; only `create_commit` materializes `index/`, `tree/`, `commit/`, `object/`. Per-commit atomicity and deterministic reads.
- `create_commit` derives the tree from stage + parent tree. The caller cannot inject an inconsistent tree.
- `compare_commits` takes no `device` argument; internal `auto` (see §6).
- `timestamp: Nat` is supplied by the consumer inside `metadata` (Base has no U64; Nat is unbounded and JSON-safe); `ber-core` never reads a clock (testable determinism). On-disk commits omit timestamp/certificate (re-materialized on load: `0n`/`None`).
- `match` inspects only parameters or pattern-bound variables, never computed values: matching on a computed hash goes through a helper def taking it as a parameter.

## 5. Laws and certificates — law-driven workflow (LAWS.bend / PROOF.bend)

By convention (see `bend guide`, "Laws and Proofs") the project keeps two files at its root:

- `LAWS.bend` — imports the code and states each law as an open claim. Written by the human. The AI does not touch it.
- `PROOF.bend` — imports `LAWS.bend` and proves each law with a def of the same name. Written by the AI, together with the code.
- Gate: `bend PROOF.bend` fails while any law is open or false, prints `All terms check.` when everything holds. **No commit lands without a green `bend PROOF.bend`** (per `AGENTS.md`).

```python
import Base
import ./src/History.bend as History
import ./src/Comparison.bend as Comparison
import ./src/Merging.bend as Merging

# LAW 1 (v0.1): deterministic versioned read — same commit always reads the same value
law read_determinism:
  for namespace_name: String
  for record_identifier: String
  for commit_identifier: String
  for first_handle: Session
  for second_handle: Session
  {History.read_value_at(first_handle, namespace_name, record_identifier, commit_identifier) == History.read_value_at(second_handle, namespace_name, record_identifier, commit_identifier) : IO<Maybe<String>>}

# LAW 2 (v0.2): merge idempotence — merging the result with B again changes nothing
law merge_idempotence:
  for first_commit: String
  for second_commit: String
  {Merging.merge_tree(Merging.merge_tree(first_commit, second_commit), second_commit) == Merging.merge_tree(first_commit, second_commit) : String}

# LAW 3 (v0.2): conditional commutativity — disjoint change sets commute
law merge_commutativity_disjoint:
  for base_commit: String
  for first_commit: String
  for second_commit: String
  {Merging.merge_tree(first_commit, second_commit) == Merging.merge_tree(second_commit, first_commit) : String}
```

Laws quantify over **pure cores** (`merge_tree : String -> String -> String`, `compare_entries`, `compute_tree_hash`), not over live `IO` handles: IO values cannot be compared for equality in proofs. The IO wrappers (`merge_commits`, `read_value_at`) are thin shells that load, call the pure core, and store — the property lives in the core, where Bend can check it.

- v0.1 ships Law 1 as PROVEN BASE INSTANCES (`empty_chain_reads_none`, `resolve_none_stable`, `normalize_nil_stable` — green gate, real regression value). Merge/cert families ship as a COMPLETE CONCRETE TRUTH TABLE (every (base,first,second) presence/value cell + verify accept/tamper/empty-laws/unknown-strategy/wrong-entries rejects — all green by computation). Universal coverage: `string_eq_refl`, `word_cmp_refl` (open terms, via local `src/EqTheory.bend` refl tower: Word→U32→Char→String), `compare_counts_correct`, certificate/commit field roundtrips. Law 4 (`SchemaLaw` extension point, v0.4) is a consumer-registered predicate checked before `MergeSuccess`.
- GENERAL instances (shadow-invariance, merge idempotence/commutativity universals, verify-soundness universal): PROVEN UNPROVABLE with Bend 2.0.28 as it stands — a language-level boundary, not a missing lemma (verified 2026-09-26, see below). They stay OUT of `LAWS.bend` (an open law reds the gate for everyone) and are tracked here instead. The gate stays green-and-exact: everything claimed is proven, everything deferred is named.
- `verify_certificate`: reloads parents, base and result tree from MyLSM, recomputes both deltas via the pure `compare_entries` core, checks disjointness and that the recomputed tree hash equals `result_tree_hash`, and that every `checked_laws` entry is `True`. Trusts nothing from the producer. `False` if any object is missing.
- `MergeUnprovable` when: no common ancestor within `MAX_ANCESTOR_WALK` hops (default 10000), unknown strategy, or a `SchemaLaw` fails. Never guesses.

### 5.1 The inversion wall (verified boundary, 2026-09-26)

Every deferred general law has the same shape: case analysis on a COMPUTED
`String.eq` (or `Nat`/`Bool` derived from one) where one branch contradicts a
hypothesis. Discharging such a branch needs one of:
(a) matching on an equality proof (inversion — rejected: "expected: a
datatype", proofs aren't scrutineeable), or
(b) explosion from a constructor clash (`False==True` ⇒ anything — no
eliminator: rewrite only substitutes, never eliminates).
Probed directly (`def boom(h : {False==True})` — match rejected). Consequence:
NO property requiring inversion of a computed comparison is provable in Bend
2.0.28, however true. This covers `String.eq` soundness/substitution (hence
shadow-invariance, merge idempotence/commutativity universals, verify
universal soundness, `split∘encode` roundtrip).
What WOULD unblock it (upstream, in order): Base-shipped `U32`/`Char` order
lemmas + a discrimination eliminator (`{False==True} → Empty` or matchable
equality). Until then the honest ceiling is: reflexivity tower (shipped in
`src/EqTheory.bend`), complete concrete truth tables (every cell green),
universal computational laws (no computed-value case splits). mylsm's own
trust root agrees: Base primitives are the trusted kernel; ber-core extends
that kernel by exactly the inversion principle, documented here instead of
smuggled in.

## 6. Compare engine (Merkle pruning + parallel let, GPU via `!`)

I/O (loads of `tree/...`, `object/...`) is always sequential. Only pure hash-list comparison fans out, with Bend's parallel call notation — independent calls bound in one `let`, roughly equal in cost (balanced partitions, per the guide's scheduler note):

```python
import Base

def compare_subtree_pair(first_tree: StateTreeNode, second_tree: StateTreeNode) -> CompareResult:
  match String.eq(first_tree.tree_hash, second_tree.tree_hash):
    case True{}:
      CompareResult/Make{Nil{}, Nil{}, Nil{}, 1n, 0n}
    case False{}:
      compare_sorted_entries(first_tree.entries, second_tree.entries)
```

- Entry compare is MEMBERSHIP-based (as-built v0.1): added = second entries whose key is absent in first (linear `key_in_entries` scan, no ordering), symmetric removed, modified = shared keys with different value hashes. O(n*m) worst case, tiny constants. Deliberately zero `String.cmp` matching: every order-branch would need eq-transitivity downstream (lemma epic). The shape is embarrassingly parallel per entry — v0.3 fans membership tests out with parallel `let` / call-site `!`.
- Pruning: equal subtree hashes return immediately with `pruned_subtree_count` incremented, no descent.
- Threshold: partitions below `COMPARISON_PARALLEL_THRESHOLD` (default 1024 entries) compare sequentially; above it they use parallel `let`. GPU selection is a call-site `!` on uniform work; divergent key sets stay on CPU. A machine without GPU runs `!` on CPU in parallel — no separate code path, automatic fallback.
- Per `AGENTS.md`, parallelize wherever the two calls are independent and balanced.

## 7. Three-way merge (single strategy in v0.2: `union-disjoint`)

Pure core (`merge_tree`) plus IO shell (`merge_commits`):

1. `base_commit = find_lowest_common_ancestor(a, b)` via parent BFS over `commit/...` (fuel-bounded `Nat` countdown —外 loops need fuel since termination is mandatory). None → `MergeUnprovable("no-common-ancestor")`.
2. `first_delta = compare(base, a)`, `second_delta = compare(base, b)` via the pure `compare_sorted_entries` core.
3. Any key present in both deltas with different value hashes → `MergeConflict(keys)`.
4. Disjoint or same value → new tree = base + deltas, new commit with `parents = [a, b]`, persist `object/tree/commit/index`.
5. Registered `SchemaLaw`s (v0.4) run before `MergeSuccess`; any failure → `MergeUnprovable("schema-law:" ++ law_name)`.

## 8. Consumer obligations

1. Never assume an exclusive `namespace_name`; always prefix (e.g. `"finance.ledger"`).
2. Domain invariants only via `SchemaLaw`, never hand-rolled merge outside.
3. `MergeUnprovable` is terminal: surface to the user / rebase-retry, never force `MergeSuccess`.

## 9. BendHub publishing

Pinned by hash (`import 0x<HASH>/main.bend as BerCore`). Semantic tag → hash via `bend link`. The law certificate + `bend PROOF.bend` log attach to the package board. No `v1.0` tag without green proofs.

## 10. ber-core only roadmap

- v0.1 Content objects + index + linear commits + deterministic `read_value_at` (Law 1 in `LAWS.bend`, proven in `PROOF.bend`). No merge, no parallel compare.
- v0.2 `union-disjoint` merge + Laws 2–3 + `MergeCertificate` + `verify_certificate`.
- v0.3 Pruned compare + parallel threshold + `!` GPU call-site + public benchmarks.
- v0.4 `SchemaLaw` + 1 real parallel consumer (Parquet adapter or minimal ber-cli).
- v1.0 Frozen API + BendHub board with visible laws.
