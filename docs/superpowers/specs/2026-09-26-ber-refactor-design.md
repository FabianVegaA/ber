# ber refactor — design (core-only cleanup)

Date: 2026-09-26. Branch: `refactor/ber-core-cleanup`. Status: approved design, pending plan.
Scope: `ber-core` only. Out of scope (deferred by user): `~/dev/bend-cli` — no CLI scaffold in this branch.

Decisions taken in brainstorming: vendor JSON migrates (rejection in spec §2.1 removed); approach **A. adapter + `bend-kit-json@0.3.0.0`**; `bend-cli` deferred; all comments rewritten.

Target: Bend 2.0.28 (`bend guide` authoritative). Gate stays green: `bend PROOF.bend` → `All terms check` before every commit. `bolt` (linter) clean on our code before merge.

## 1. Laws vs tests

Pure-core fixtures already live as laws (merge truth table, compare boundaries, cert verify, `string_eq_refl` tower) — those duplicates in `tests/` are documentation, not coverage. IO shells (`Staging.put_record/delete_record`, `History.create_commit/read_value_at/read_tree_at`, `Merging.merge_commits`, `Certificate.verify_certificate` shells, `Comparison.compare_commits` shell, fan-out agreement) cannot move to laws: laws quantify over pure cores, never `Sess`/`IO`.

Design: keep all 8 `tests/*_check.bend` as the IO harness; delete only pure-core duplicate asserts that restate an existing law byte-for-byte (if any remain after migration — expected: none worth deleting, tests assert IO wiring, laws assert pure semantics). `benches/compare_bench.bend` stays.

## 2. Vendor JSON → adapter + kit (approach A)

Both candidates check green on 2.0.28 and are byte-identical except header; pick `bend-kit-json@0.3.0.0` (cites source `paymog/bend-kit`).
Delete `vendor/json/` entirely.

New `src/JsonAdapter.bend` (only file naming `Json`): wraps `Val{Null/Flag/Num/Str/Arr/Obj{m: Map}}` (kit uses Base's `Map`) with 8 defs matching current call sites — `make_str/make_arr/make_obj/parse_text/encode_canonical/get_field/as_str/as_arr`. Internals: objects built by `Map.new` + `Map.set` fold (no `sort_keys` needed — `encode` emits keys via `Map.to_list`, an in-order Patricia-trie traversal = char-code lexicographic order, same as rootagi's `sort_keys` for our ASCII keys); `parse: String -> Maybe<Val>` replaces `Result Fail/Done` with `None/Some` at the adapter boundary so the 4 consumers change minimally. Kit's `Num` keeps exact text; our docs carry no numbers.

`@unsafe` boundary (honest): kit's `encode` is `@unsafe` (work-list walk), which violates spec §3's `@unsafe`-free rule. Confinement: only the adapter calls `encode`; its doc header states the trust boundary (parser safe, encoder `@unsafe` upstream, canonical-bytes property covered by roundtrip checks + differential test vs Python `json`, not by proof). Spec §2.1 row rewritten: ADOPT kit, rejection deleted, boundary recorded. If upstream ships a safe encoder, drop-in inside adapter only.

Consumers (`ContentObject, History, StateTree, Staging`): change import to adapter, constructor renames (`str→Str`, `arr→Arr`, `obj(kv-list)→Obj(Map)`, `stringify(sort_keys(·))→encode_canonical`), parse branches `Fail/Done→None/Some`.

Canonical-byte compatibility (load-bearing probe, FIRST migration step): equal content must yield byte-identical text, because `compute_sha256_hex` hashes canonical text and `History.verify_commit_text` re-serializes parsed fields and string-compares against the stored bytes. Build each of our 4 doc shapes (content-object, commit, tree, stage-index) with BOTH libraries in one probe file and assert byte equality per shape. Expected equal (both emit char-code-sorted keys, no escapes in our payloads). If the probe fails on any shape, stop: pre-migration stores become unreadable (integrity check rejects re-serialized mismatches) and the hash namespace changes — that outcome is acceptable ONLY because v0.x has no durable data (fresh MyLSM store per test run), and must be recorded in the commit message.

Data flow unchanged: canonical JSON → `compute_sha256_hex` → content/tree/commit hashes. Error handling unchanged: parse failure → `None`/`Nil` (never corrupt values); adapter adds no new failure modes.

## 3. Comments rewrite

Delete every `#` comment in `src/*.bend`, `LAWS.bend`, `PROOF.bend`, `tests/*.bend`, `benches/*.bend` (vendor deleted anyway; `docs/` untouched). Write new ones in English, short, why-not-what: one header line per file (purpose + trust boundary if any), one line per public `def` (contract). Private helpers get a line only if the contract isn't obvious from the name. This also satisfies `bolt` doc rule `S001`, so lint and readability land together. No changelog/history in code — that lives in git log and this spec.

## 4. bend-cli — deferred

Nothing in this branch. No `IO.args` CLI enters `ber/`. When reactivated, `bend-cli` imports `ber-core` by hash and owns all arg parsing and `open/run_sess` wiring.

## 5. MyLSM 0.3.1.0 only

Code already pins `0x0ae7ac793853e753f5f74c16e06ee078` everywhere (mylsm + `src/hub_sha/sha256.bend` subpath + `Wal`). Only change: fix stale `v0.2.0` comment in `src/MyLsmBinding.bend:5` to `v0.3.1.0` (done as part of comment rewrite) and record the pin line in README. No code change.

## 6. Dead code

`src/` only, verified by `rg` zero-usage before each deletion, `bend PROOF.bend` green after. Confirmed dead (usage search 2026-09-26): `Merging.find_common_ancestor` (defined, never called — `merge_with_ancestor_search` inlines the same ancestor-set + first-common walk), `MyLsmBinding.store_batch` (binding wrapper with zero callers). Everything else checked is live: `merge_succeeded/conflict_key_count/success_commit_of/success_certificate_of/pruned_count_of` and all `cert_*` accessors are used by tests or `Certificate.bend`; `History.empty_*` are used internally; `law_check_passed` used by `Certificate`. Tests/benches keep their mains. Laws keep every law (coverage owns them, even single-case `L002`s).

## 7. Bolt

Create `bolt.bend` at root: `correctness → error`, rest warn (oxlint-style groups per bolt README). Fix all our `S001` (via new comments). `S002` (>120 cols) stays as accepted warnings where the line is a single law expression that Bend cannot wrap safely (most LAWS lines); gate is errors, not warnings. The 5 `C003 Bool.pick` errors live in vendor and disappear with it; kit lives in `~/.bend/lib`, outside bolt's cwd scan, and its `Bool.pick` uses are the safe peek pattern documented in its source. `L001` (no law reaches def) shrinks automatically with the vendor surface gone; remaining `L001`s on IO shells are accepted (laws cover pure cores by design — record as config comment, not code churn). Gate: `bolt` prints no `error` lines on our tree (exit 0 when warnings only).

## 8. README

New root `README.md`: what ber-core is (convergence + proof primitive over MyLSM), laws-as-spec (`LAWS.bend`/`PROOF.bend` + gate command), quickstart (stage → commit → read → compare → merge → verify), physical layout table (`object/tree/commit/index/stage` keys), pins (mylsm 0.3.1.0 hash, kit json, codec), project map (`src/` one line each), benchmarks pointer, roadmap pointer to spec. English, concise, no duplication of this design doc.

## 9. Testing

`bend PROOF.bend` green after every step. Byte-probe (kit vs rootagi on our 4 doc shapes) runs FIRST and passes before any consumer changes. Each `tests/*_check.bend` run green after migration (canonical bytes + Maybe-branches). Differential JSON check vs Python `json` re-run (roundtrip + key order vs `json.dumps(..., sort_keys=True)`). `bolt` no-error. Final: full `bend PROOF.bend` + `bolt` + all checks in one pass before merge.
