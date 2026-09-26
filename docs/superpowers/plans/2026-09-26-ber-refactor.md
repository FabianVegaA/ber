# ber refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate ber-core's JSON from vendored rootagi to `bend-kit-json@0.3.0.0` behind a thin adapter, remove dead code, rewrite all comments, add bolt config and README — with `bend PROOF.bend` green after every task.

**Architecture:** One new module `src/JsonAdapter.bend` owns every JSON operation; the 4 serde consumers (`ContentObject`, `StateTree`, `History`, `Staging`) import the kit package for the `Val` TYPE only (same convention as `MyLsmStore.Sess`) and the adapter for all functions. Canonical bytes are probed kit-vs-rootagi BEFORE any consumer changes; a mismatch stops the migration.

**Tech Stack:** Bend 2.0.28, `bend-kit-json@0.3.0.0` (`0xaaa10a97bf5ac6990143da2c863f8a3f`), mylsm `0x0ae7ac793853e753f5f74c16e06ee078` (0.3.1.0, already pinned), bolt linter (`/Users/fvega/dev/bolt/bin/bolt.bin`).

**Spec:** `docs/superpowers/specs/2026-09-26-ber-refactor-design.md`

**Bend rules that bind every task (from `bend guide` + `AGENTS.md`):**
- `match` only on parameters or pattern-bound variables; computed values go through a helper def.
- No forward references: a def may only call defs declared ABOVE it. Adapter/probe def order matters.
- Termination: recursive calls pass a structurally smaller argument FIRST; accumulator folds put the shrinking list in argument position 1.
- `import bend-kit-json@0.3.0.0/json.bend as Json` is probe-verified green on 2.0.28.
- `Map.new(&2, KitType.Val)` / `Map.set(&2, KitType.Val, m, k, v)` are the exact Base call shapes (kit uses them at its own lines 257/338).
- Gate: `bend PROOF.bend` prints `All terms check.` before every commit. Bolt: `/Users/fvega/dev/bolt/bin/bolt.bin` prints no `error` lines before merge.

---

### Task 0: bolt config + baseline

**Files:**
- Create: `bolt.bend`

- [ ] **Step 1: Write bolt.bend**

```python
# bolt linter config. correctness findings gate the build (error); style,
# suspicious and laws findings stay advisory (warn) — LAWS.bend long lines
# (S002) and IO-shell law coverage (L001) are accepted by design, see spec §7.
def correctness() -> String:
  "error"
def suspicious() -> String:
  "warn"
def style() -> String:
  "warn"
def laws() -> String:
  "warn"
```

- [ ] **Step 2: Run bolt, record baseline**

Run: `/Users/fvega/dev/bolt/bin/bolt.bin 2>&1 | tail -3`
Expected: `5 errors, 1583 warnings` (all 5 errors are `C003` inside `vendor/json/json.bend`).

- [ ] **Step 3: Commit**

```bash
git add bolt.bend
git commit -m "chore(ber-core): bolt config - correctness gates, rest advisory"
```

---

### Task 1: LOAD-BEARING byte probe — kit vs vendored rootagi

**Files:**
- Create: `json_bytes_probe.bend` (repo root; deleted in Task 7)

The probe builds each of our 4 document shapes with BOTH libraries and asserts byte equality. If any shape differs, STOP: do not migrate; report the differing bytes (spec §2 fallback).

- [ ] **Step 1: Write the probe**

```python
import Base
import ./vendor/json/json.bend as Rootagi
import bend-kit-json@0.3.0.0/json.bend as Kit

# One-shot migration gate: prove kit emits byte-identical canonical text to
# vendored rootagi for every document shape ber-core persists. Deleted with
# vendor/ after the migration lands.

def probe_fold(fields: List<&2, Sigma<&2, &2, String, _ => Kit.Val>>, field_map: Map<&2, Kit.Val>) -> Map<&2, Kit.Val>:
  match fields:
    case Nil{}:
      field_map
    case (field_key, field_value) <> tail_fields:
      probe_fold(tail_fields, Map.set(&2, Kit.Val, field_map, field_key, field_value))

def probe_obj(fields: List<&2, Sigma<&2, &2, String, _ => Kit.Val>>) -> Kit.Val:
  Kit.Obj{probe_fold(fields, Map.new(&2, Kit.Val))}

def rootagi_content_object() -> String:
  Rootagi.stringify(Rootagi.sort_keys(Rootagi.obj(Con{Rootagi.kv("payload", Rootagi.str("hello")), Con{Rootagi.kv("references", Rootagi.arr(Con{Rootagi.str("ref_a"), Nil{}})), Nil{}})))

def kit_content_object() -> String:
  Kit.encode(probe_obj(Con{("payload", Kit.Str{"hello"}), Con{("references", Kit.Arr{Con{Kit.Str{"ref_a"}, Nil{}}}), Nil{}}))

def rootagi_commit() -> String:
  Rootagi.stringify(Rootagi.sort_keys(Rootagi.obj(Con{Rootagi.kv("parents", Rootagi.arr(Con{Rootagi.str("parent_one"), Nil{}})), Con{Rootagi.kv("tree", Rootagi.str("abc123")), Con{Rootagi.kv("meta", Rootagi.arr(Con{Rootagi.arr(Con{Rootagi.str("strategy"), Con{Rootagi.str("union-disjoint"), Nil{}}}), Nil{}})), Nil{}}))))

def kit_commit() -> String:
  Kit.encode(probe_obj(Con{("parents", Kit.Arr{Con{Kit.Str{"parent_one"}, Nil{}}}), Con{("tree", Kit.Str{"abc123"}), Con{("meta", Kit.Arr{Con{Kit.Arr{Con{Kit.Str{"strategy"}, Con{Kit.Str{"union-disjoint"}, Nil{}}}}, Nil{}}}), Nil{}}}))

def rootagi_tree() -> String:
  Rootagi.stringify(Rootagi.sort_keys(Rootagi.obj(Con{Rootagi.kv("hash", Rootagi.str("tree_hash_value")), Con{Rootagi.kv("entries", Rootagi.arr(Con{Rootagi.arr(Con{Rootagi.str("ledger/record_a"), Con{Rootagi.str("hash_a"), Nil{}}}), Con{Rootagi.arr(Con{Rootagi.str("ledger/record_b"), Con{Rootagi.str("hash_b"), Nil{}}}), Nil{}})), Con{Rootagi.kv("children", Rootagi.arr(Nil{})), Nil{}}))))

def kit_tree() -> String:
  Kit.encode(probe_obj(Con{("hash", Kit.Str{"tree_hash_value"}), Con{("entries", Kit.Arr{Con{Kit.Arr{Con{Kit.Str{"ledger/record_a"}, Con{Kit.Str{"hash_a"}, Nil{}}}}, Con{Kit.Arr{Con{Kit.Str{"ledger/record_b"}, Con{Kit.Str{"hash_b"}, Nil{}}}}, Nil{}}}), Con{("children", Kit.Arr{Nil{}}), Nil{}}}))

def rootagi_stage_index() -> String:
  Rootagi.stringify(Rootagi.arr(Con{Rootagi.str("stage/s/ledger/r1"), Con{Rootagi.str("stage/s/ledger/r2"), Nil{}}}))

def kit_stage_index() -> String:
  Kit.encode(Kit.Arr{Con{Kit.Str{"stage/s/ledger/r1"}, Con{Kit.Str{"stage/s/ledger/r2"}, Nil{}}})

def flag_line(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def val_text_or_empty(json_value: Kit.Val) -> String:
  match json_value:
    case Kit.Str{text}:
      text
    case _:
      ""

def payload_field_text(payload_maybe: Maybe<&2, Kit.Val>) -> String:
  match payload_maybe:
    case None{}:
      ""
    case Some{payload_val}:
      val_text_or_empty(payload_val)

def parsed_payload_text(parse_result: Maybe<&2, Kit.Val>) -> String:
  match parse_result:
    case None{}:
      ""
    case Some{parsed_doc}:
      payload_field_text(Kit.get(parsed_doc, "payload"))

def payload_roundtrip_ok() -> Bool:
  String.eq(parsed_payload_text(Kit.parse(kit_content_object())), "hello")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(flag_line("content-object-bytes", String.eq(rootagi_content_object(), kit_content_object())))
    IO.print(flag_line("commit-bytes", String.eq(rootagi_commit(), kit_commit())))
    IO.print(flag_line("tree-bytes", String.eq(rootagi_tree(), kit_tree())))
    IO.print(flag_line("stage-index-bytes", String.eq(rootagi_stage_index(), kit_stage_index())))
    IO.print(flag_line("kit-parse-roundtrip", payload_roundtrip_ok()))
```

- [ ] **Step 2: Run the probe**

Run: `bend json_bytes_probe.bend`
Expected: five lines, all `PASS`. If any `FAIL`: STOP the migration, print both byte strings for the failing shape, report to the user (spec §2: differing key order invalidates pre-migration stores and changes the hash namespace — needs an explicit decision).

- [ ] **Step 3: Commit**

```bash
git add json_bytes_probe.bend
git commit -m "test(ber-core): byte probe kit vs vendored rootagi - all shapes identical"
```

---

### Task 2: `src/JsonAdapter.bend` + adapter check

**Files:**
- Create: `src/JsonAdapter.bend`
- Create: `tests/json_adapter_check.bend`

- [ ] **Step 1: Write the failing check**

NOTE — every `match` below sits on a def PARAMETER (Bend rejects `match` on
computed values); results are threaded through helper chains, exactly as in
`src/ContentObject.bend`.

```python
import Base
import ../src/JsonAdapter.bend as JsonAdapter
import bend-kit-json@0.3.0.0/json.bend as Json

def sample_text() -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(Con{JsonAdapter.make_kv("payload", JsonAdapter.make_str("hello")), Con{JsonAdapter.make_kv("references", JsonAdapter.make_arr(Con{JsonAdapter.make_str("ref_a"), Nil{}})), Nil{}}))

def check_canonical_bytes() -> Bool:
  String.eq(sample_text(), "{\"payload\":\"hello\",\"references\":[\"ref_a\"]}")

def str_maybe_matches(found_maybe: Maybe<&2, String>, +expected_text: String) -> Bool:
  match found_maybe:
    case None{}:
      False{}
    case Some{+found_text}:
      String.eq(found_text, expected_text)

def payload_val_ok(payload_val: Json.Val) -> Bool:
  str_maybe_matches(JsonAdapter.as_str(payload_val), "hello")

def payload_field_ok(payload_maybe: Maybe<&2, Json.Val>) -> Bool:
  match payload_maybe:
    case None{}:
      False{}
    case Some{payload_val}:
      payload_val_ok(payload_val)

def parsed_doc_has_payload(parse_result: Maybe<&2, Json.Val>) -> Bool:
  match parse_result:
    case None{}:
      False{}
    case Some{parsed_doc}:
      payload_field_ok(JsonAdapter.get_field(parsed_doc, "payload"))

def check_roundtrip_payload() -> Bool:
  parsed_doc_has_payload(JsonAdapter.parse_text(sample_text()))

def absent_field_is_none(absent_maybe: Maybe<&2, Json.Val>) -> Bool:
  match absent_maybe:
    case None{}:
      True{}
    case Some{unexpected_val}:
      False{}

def parsed_doc_lacks_absent(parse_result: Maybe<&2, Json.Val>) -> Bool:
  match parse_result:
    case None{}:
      False{}
    case Some{parsed_doc}:
      absent_field_is_none(JsonAdapter.get_field(parsed_doc, "absent"))

def check_missing_field() -> Bool:
  parsed_doc_lacks_absent(JsonAdapter.parse_text(sample_text()))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Bool.show(check_canonical_bytes()))
    IO.print(Bool.show(check_roundtrip_payload()))
    IO.print(Bool.show(check_missing_field()))
```

- [ ] **Step 2: Run to verify it fails**

Run: `bend tests/json_adapter_check.bend`
Expected: check error (`no such file: ../src/JsonAdapter.bend`).

- [ ] **Step 3: Write the adapter**

```python
import Base
import bend-kit-json@0.3.0.0/json.bend as Json

# Sole owner of JSON operations. Consumers import THIS module for all
# encode/parse/get work; they import the kit package ONLY for the Val type in
# annotations (Bend cannot alias types across modules — same convention as
# MyLsmStore.Sess).
# TRUST BOUNDARY: Json.parse is structural recursion. Json.encode is @unsafe
# upstream (work-list walk, documented in kit source); canonical-bytes
# (equal content => identical text) is covered by json_bytes_probe and the
# differential check vs Python json, not by proof. If kit ships a safe
# encoder, only this file changes.

def make_str(+text: String) -> Json.Val:
  Json.Str{text}

def make_arr(items: List<&2, Json.Val>) -> Json.Val:
  Json.Arr{items}

def make_kv(+field_key: String, field_value: Json.Val) -> Sigma<&2, &2, String, _ => Json.Val>:
  (field_key, field_value)

def fold_pair(field_map: Map<&2, Json.Val>, field_pair: Sigma<&2, &2, String, _ => Json.Val>) -> Map<&2, Json.Val>:
  match field_pair:
    case (field_key, field_value):
      Map.set(&2, Json.Val, field_map, field_key, field_value)

def fold_fields(remaining_fields: List<&2, Sigma<&2, &2, String, _ => Json.Val>>, field_map: Map<&2, Json.Val>) -> Map<&2, Json.Val>:
  match remaining_fields:
    case Nil{}:
      field_map
    case Con{field_pair, tail_fields}:
      fold_fields(tail_fields, fold_pair(field_map, field_pair))

def make_obj(fields: List<&2, Sigma<&2, &2, String, _ => Json.Val>>) -> Json.Val:
  Json.Obj{fold_fields(fields, Map.new(&2, Json.Val))}

def parse_text(+stored_text: String) -> Maybe<&2, Json.Val>:
  Json.parse(stored_text)

def get_field(+document: Json.Val, +field_name: String) -> Maybe<&2, Json.Val>:
  Json.get(document, field_name)

def as_str(json_value: Json.Val) -> Maybe<&2, String>:
  match json_value:
    case Json.Str{text}:
      Some{text}
    case _:
      None{}

def as_arr(json_value: Json.Val) -> Maybe<&2, List<&2, Json.Val>>:
  match json_value:
    case Json.Arr{items}:
      Some{items}
    case _:
      None{}

def encode_canonical(+document: Json.Val) -> String:
  Json.encode(document)
```

- [ ] **Step 4: Run to verify it passes**

Run: `bend tests/json_adapter_check.bend`
Expected: three lines, all `True`.

- [ ] **Step 5: Gate + commit**

Run: `bend PROOF.bend` → `All terms check.`

```bash
git add src/JsonAdapter.bend tests/json_adapter_check.bend
git commit -m "feat(ber-core): json adapter over bend-kit-json with canonical encode"
```

---

### Task 3: Migrate `src/ContentObject.bend` (+ rewrite its comments)

**Files:**
- Modify: `src/ContentObject.bend`

- [ ] **Step 1: Replace the import block (lines 1-14)**

Old:
```python
import Base
import ./ContentHash.bend as ContentHash
import ./LogicalKey.bend as LogicalKey
import ./MyLsmBinding.bend as Binding
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore
import ../vendor/json/json.bend as JsonLib
```

New:
```python
import Base
import ./ContentHash.bend as ContentHash
import ./LogicalKey.bend as LogicalKey
import ./MyLsmBinding.bend as Binding
import ./JsonAdapter.bend as JsonAdapter
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore
import bend-kit-json@0.3.0.0/json.bend as Json

# Content-addressed objects persisted as canonical JSON: equal content gives
# byte-identical text, so the SHA-256 of the text is a stable address.
# Payloads and references stay strings-only, inside the probed doc shapes.
# Kit is named for the Val TYPE only; all operations go through JsonAdapter.
# Effects use only Binding wrappers; MyLsmStore is named for Sess types only.
```

- [ ] **Step 2: Apply the rename table + structural edits**

Rename table (exact strings, whole file):
| Old | New |
|---|---|
| `JsonLib.Json` | `Json.Val` |
| `JsonLib.str(` | `JsonAdapter.make_str(` |
| `JsonLib.arr(` | `JsonAdapter.make_arr(` |
| `JsonLib.kv(` | `JsonAdapter.make_kv(` |
| `JsonLib.as_str(` | `JsonAdapter.as_str(` |
| `JsonLib.as_arr(` | `JsonAdapter.as_arr(` |
| `JsonLib.get(` | `JsonAdapter.get_field(` |

Structural edits (full new bodies):

`encode_reference_list` — kv-list now feeds `make_obj`:
```python
def encode_reference_list(payload: String, references: List<&2, String>) -> List<&2, Sigma<&2, &2, String, _ => Json.Val>>:
  Con{JsonAdapter.make_kv("payload", JsonAdapter.make_str(payload)), Con{JsonAdapter.make_kv("references", JsonAdapter.make_arr(encode_each_reference(references))), Nil{}}}
```

`canonical_content` — sorted-by-construction encode replaces `stringify(sort_keys(·))`:
```python
def canonical_content(payload: String, references: List<&2, String>) -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(encode_reference_list(payload, references)))
```

`object_from_parse_result` — `Result` becomes `Maybe`:
```python
def object_from_parse_result(content_hash: String, parse_result: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match parse_result:
    case None{}:
      None{}
    case Some{+document}:
      extract_with_payload(content_hash, document, JsonAdapter.get_field(document, "payload"))
```

`parse_canonical_object`:
```python
def parse_canonical_object(content_hash: String, stored_text: String) -> Maybe<&2, ContentObject>:
  object_from_parse_result(content_hash, JsonAdapter.parse_text(stored_text))
```

- [ ] **Step 3: Rewrite the file's comments per spec §3**

Delete every remaining `#` line in the file. New rule: one line per PUBLIC def stating its contract (private helpers only when non-obvious). Apply exactly as in these examples:

```python
# SHA-256 of the canonical text; the address consumers store and load by.
def store_content_object(payload: String, references: List<&2, String>) -> MyLsmStore.Sess<&2, String>:
```

```python
# None on missing or malformed stored text; never returns a corrupt object.
def load_content_object(+content_hash: String) -> MyLsmStore.Sess<&2, Maybe<&2, ContentObject>>:
```

- [ ] **Step 4: Run checks**

Run: `bend tests/content_object_check.bend` → all printed lines `True`.
Run: `bend tests/json_adapter_check.bend` → three `True`.
Run: `bend PROOF.bend` → `All terms check.`

- [ ] **Step 5: Commit**

```bash
git add src/ContentObject.bend
git commit -m "refactor(ber-core): content objects on json adapter, comments rewritten"
```

---

### Task 4: Migrate `src/StateTree.bend` (+ comments)

**Files:**
- Modify: `src/StateTree.bend`

- [ ] **Step 1: Replace imports (lines 1-11)**

New:
```python
import Base
import ./Reading.bend as Reading
import ./ContentHash.bend as ContentHash
import ./JsonAdapter.bend as JsonAdapter
import bend-kit-json@0.3.0.0/json.bend as Json

# Flat sorted state tree (v0.1: no children partitioning). Entries sorted by
# combined key ("namespace/record"); staged entries win ties. The tree hash
# covers the flattened entries only, never the JSON text. This module owns
# both tree directions (serialize + parse); History only calls them.
# Kit is named for the Val TYPE only; operations go through JsonAdapter.
```

- [ ] **Step 2: Rename table + structural edits**

Rename table (exact strings, whole file — identical in every consumer):
| Old | New |
|---|---|
| `JsonLib.Json` | `Json.Val` |
| `JsonLib.str(` | `JsonAdapter.make_str(` |
| `JsonLib.arr(` | `JsonAdapter.make_arr(` |
| `JsonLib.kv(` | `JsonAdapter.make_kv(` |
| `JsonLib.as_str(` | `JsonAdapter.as_str(` |
| `JsonLib.as_arr(` | `JsonAdapter.as_arr(` |
| `JsonLib.get(` | `JsonAdapter.get_field(` |

StateTree structural edits (full new bodies):

`finalize_tree_document`:
```python
def finalize_tree_document(hash_field: Sigma<&2, &2, String, _ => Json.Val>, entries_field: Sigma<&2, &2, String, _ => Json.Val>, children_field: Sigma<&2, &2, String, _ => Json.Val>) -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(Con{hash_field, Con{entries_field, Con{children_field, Nil{}}}}))
```

`serialize_tree`:
```python
def serialize_tree(+merged_entries: List<&2, Reading.ChainEntry>, +tree_hash_value: String) -> String:
  finalize_tree_document(JsonAdapter.make_kv("hash", JsonAdapter.make_str(tree_hash_value)), JsonAdapter.make_kv("entries", JsonAdapter.make_arr(entry_list_to_json(merged_entries))), JsonAdapter.make_kv("children", JsonAdapter.make_arr(Nil{})))
```

`tree_from_parse` — `Result` → `Maybe`:
```python
def tree_from_parse(parse_result: Maybe<&2, Json.Val>) -> Maybe<&2, StateTreeNode>:
  match parse_result:
    case None{}:
      None{}
    case Some{+document}:
      extract_tree_fields(document)
```

`parse_tree_document`:
```python
def parse_tree_document(stored_text: String) -> Maybe<&2, StateTreeNode>:
  tree_from_parse(JsonAdapter.parse_text(stored_text))
```

- [ ] **Step 3: Rewrite comments** — rule: delete every `#` line; one header line per file is already in place from Step 1 (verify it); add one English contract line per public def (why-not-what); private helpers get a line only if the contract is not obvious from the name

- [ ] **Step 4: Run checks**

Run: `bend tests/commit_read_check.bend` → all lines PASS.
Run: `bend PROOF.bend` → `All terms check.`

- [ ] **Step 5: Commit**

```bash
git add src/StateTree.bend
git commit -m "refactor(ber-core): state tree serde on json adapter, comments rewritten"
```

---

### Task 5: Migrate `src/History.bend` (+ comments)

**Files:**
- Modify: `src/History.bend`

- [ ] **Step 1: Replace imports (lines 1-22)**

New:
```python
import Base
import ./Reading.bend as Reading
import ./LogicalKey.bend as LogicalKey
import ./ContentHash.bend as ContentHash
import ./StateTree.bend as StateTree
import ./Staging.bend as Staging
import ./ContentObject.bend as ContentObject
import ./MyLsmBinding.bend as Binding
import ./JsonAdapter.bend as JsonAdapter
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore
import bend-kit-json@0.3.0.0/json.bend as Json

# Linear history: staging -> merged tree -> commit -> per-key version index.
# Commits serialize as canonical JSON without timestamp/certificate (both
# re-materialize on load: 0 / None). Loads re-serialize the parsed fields and
# compare against the stored text: a mismatch yields None, never corruption.
# Kit is named for the Val TYPE only; operations go through JsonAdapter.
# Effects use only Binding wrappers; MyLsmStore is named for Sess types only.
```

- [ ] **Step 2: Rename table + structural edits**

Rename table (exact strings, whole file — identical in every consumer):
| Old | New |
|---|---|
| `JsonLib.Json` | `Json.Val` |
| `JsonLib.str(` | `JsonAdapter.make_str(` |
| `JsonLib.arr(` | `JsonAdapter.make_arr(` |
| `JsonLib.kv(` | `JsonAdapter.make_kv(` |
| `JsonLib.as_str(` | `JsonAdapter.as_str(` |
| `JsonLib.as_arr(` | `JsonAdapter.as_arr(` |
| `JsonLib.get(` | `JsonAdapter.get_field(` |

History structural edits (full new bodies):

`finalize_commit_document`:
```python
def finalize_commit_document(parents_field: Sigma<&2, &2, String, _ => Json.Val>, tree_field: Sigma<&2, &2, String, _ => Json.Val>, meta_field: Sigma<&2, &2, String, _ => Json.Val>) -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(Con{parents_field, Con{tree_field, Con{meta_field, Nil{}}}}))
```

`serialize_commit`:
```python
def serialize_commit(parent_commit_identifiers: List<&2, String>, metadata: List<&2, CommitMeta>, tree_hash_value: String) -> String:
  finalize_commit_document(JsonAdapter.make_kv("parents", JsonAdapter.make_arr(encode_parent_list(parent_commit_identifiers))), JsonAdapter.make_kv("tree", JsonAdapter.make_str(tree_hash_value)), JsonAdapter.make_kv("meta", JsonAdapter.make_arr(meta_list_to_json(metadata))))
```

`commit_from_parse` — `Result` → `Maybe`:
```python
def commit_from_parse(requested_identifier: String, stored_text: String, parse_result: Maybe<&2, Json.Val>) -> Maybe<&2, Commit>:
  match parse_result:
    case None{}:
      None{}
    case Some{+document}:
      extract_commit_parents(requested_identifier, stored_text, document)
```

`parse_commit_text`:
```python
def parse_commit_text(requested_identifier: String, +stored_text: String) -> Maybe<&2, Commit>:
  commit_from_parse(requested_identifier, stored_text, JsonAdapter.parse_text(stored_text))
```

- [ ] **Step 3: Rewrite comments** — rule: delete every `#` line; one header line per file is already in place from Step 1 (verify it); add one English contract line per public def (why-not-what); private helpers get a line only if the contract is not obvious from the name

- [ ] **Step 4: Run checks**

Run: `bend tests/commit_read_check.bend` → all PASS.
Run: `bend tests/reading_check.bend` → all PASS.
Run: `bend PROOF.bend` → `All terms check.`

- [ ] **Step 5: Commit**

```bash
git add src/History.bend
git commit -m "refactor(ber-core): history serde on json adapter, comments rewritten"
```

---

### Task 6: Migrate `src/Staging.bend` (+ comments)

**Files:**
- Modify: `src/Staging.bend`

- [ ] **Step 1: Replace imports (lines 1-11)**

New:
```python
import Base
import ./LogicalKey.bend as LogicalKey
import ./ContentObject.bend as ContentObject
import ./MyLsmBinding.bend as Binding
import ./JsonAdapter.bend as JsonAdapter
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore
import bend-kit-json@0.3.0.0/json.bend as Json

# Uncommitted working set. Staged values live at stage/{session}/{ns}/{id};
# the per-session key manifest lives at stage-index/{session} as a canonical
# JSON string list. Point operations only — no prefix scan anywhere.
# Kit is named for the Val TYPE only; operations go through JsonAdapter.
```

- [ ] **Step 2: Rename table + structural edits**

Rename table (exact strings, whole file — identical in every consumer):
| Old | New |
|---|---|
| `JsonLib.Json` | `Json.Val` |
| `JsonLib.str(` | `JsonAdapter.make_str(` |
| `JsonLib.arr(` | `JsonAdapter.make_arr(` |
| `JsonLib.kv(` | `JsonAdapter.make_kv(` |
| `JsonLib.as_str(` | `JsonAdapter.as_str(` |
| `JsonLib.as_arr(` | `JsonAdapter.as_arr(` |
| `JsonLib.get(` | `JsonAdapter.get_field(` |

Staging structural edits (full new bodies):

`serialize_key_list`:
```python
def serialize_key_list(staged_keys: List<&2, String>) -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_arr(ContentObject.encode_each_reference(staged_keys)))
```

`index_from_text` — `Result` → `Maybe`:
```python
def index_from_text(parse_result: Maybe<&2, Json.Val>) -> List<&2, String>:
  match parse_result:
    case None{}:
      Nil{}
    case Some{document}:
      index_from_document(JsonAdapter.as_arr(document))
```

`parse_stage_index`:
```python
def parse_stage_index(stored_maybe: Maybe<&2, String>) -> List<&2, String>:
  match stored_maybe:
    case None{}:
      Nil{}
    case Some{stored_text}:
      index_from_text(JsonAdapter.parse_text(stored_text))
```

- [ ] **Step 3: Rewrite comments** — rule: delete every `#` line; one header line per file is already in place from Step 1 (verify it); add one English contract line per public def (why-not-what); private helpers get a line only if the contract is not obvious from the name

- [ ] **Step 4: Run checks**

Run: `bend tests/commit_read_check.bend` → all PASS.
Run: `bend tests/reading_check.bend` → all PASS.
Run: `bend PROOF.bend` → `All terms check.`

- [ ] **Step 5: Commit**

```bash
git add src/Staging.bend
git commit -m "refactor(ber-core): staging serde on json adapter, comments rewritten"
```

---

### Task 7: Delete vendor + probe, full check sweep

**Files:**
- Delete: `vendor/json/json.bend` (and `vendor/` tree)
- Delete: `json_bytes_probe.bend`

- [ ] **Step 1: Verify no reference to vendor remains**

Run: `rg -n "vendor/json|JsonLib" src tests benches LAWS.bend PROOF.bend`
Expected: no output (zero matches).

- [ ] **Step 2: Delete**

```bash
git rm -r vendor json_bytes_probe.bend
```

- [ ] **Step 3: Full sweep**

Run each, expect all PASS/True lines:
`bend tests/logical_key_check.bend`
`bend tests/content_object_check.bend`
`bend tests/json_adapter_check.bend`
`bend tests/commit_read_check.bend`
`bend tests/reading_check.bend`
`bend tests/comparison_check.bend`
`bend tests/merging_check.bend`
`bend tests/certificate_check.bend`
`bend tests/fanout_agreement_check.bend`
Run: `bend PROOF.bend` → `All terms check.`
Run: `/Users/fvega/dev/bolt/bin/bolt.bin 2>&1 | tail -3` → `0 errors` (the 5 `C003` died with vendor).

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(ber-core): drop vendored rootagi json and byte probe"
```

---

### Task 8: Dead code removal

**Files:**
- Modify: `src/Merging.bend` (delete `find_common_ancestor`, lines 190-194)
- Modify: `src/MyLsmBinding.bend` (delete `store_batch` + the `WalTypes` import it alone uses)

Confirmed zero-usage by `rg` on 2026-09-26 (spec §6).

- [ ] **Step 1: Delete `find_common_ancestor` from `src/Merging.bend`**

Remove exactly:
```python
def find_common_ancestor(+first_identifier: String, +second_identifier: String) -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  do MyLsmStore.Sess<&2, Maybe<&2, String>>:
    ancestor_set : List<&2, String> <- collect_ancestors(10000n, Con{first_identifier, Nil{}}, Nil{})
    lca_result : Maybe<&2, String> <- find_first_common(ancestor_set, 10000n, second_identifier)
    return lca_result
```

- [ ] **Step 2: Write the new `src/MyLsmBinding.bend`**

```python
import Base
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore

# PINNED: mylsm v0.3.1.0 = 0x0ae7ac793853e753f5f74c16e06ee078 (hash is the
# trust anchor; the tag is convenience). Only this file names MyLsmStore
# effects. MyLSM is a state monad (Sess), not handles: ber-core composes
# Sess actions in do-blocks and the monad threads Db internally.
def store_value(+storage_key: String, +stored_value: String) -> MyLsmStore.Sess<&2, Unit>:
  MyLsmStore.sput(storage_key, stored_value)

def remove_value(+storage_key: String) -> MyLsmStore.Sess<&2, Unit>:
  MyLsmStore.sdel(storage_key)

def load_value(+storage_key: String) -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  MyLsmStore.sget(storage_key)
```

(This also lands the stale `v0.2.0` → `v0.3.1.0` comment fix from spec §5 and drops the `WalTypes` import only `store_batch` used.)

- [ ] **Step 3: Verify zero usage, gate, commit**

Run: `rg -n "find_common_ancestor|store_batch|WalTypes" src tests benches LAWS.bend PROOF.bend` → no output.
Run: `bend PROOF.bend` → `All terms check.`
Run: `bend tests/merging_check.bend` → all PASS.

```bash
git add src/Merging.bend src/MyLsmBinding.bend
git commit -m "chore(ber-core): drop dead find_common_ancestor and store_batch"
```

---

### Task 9: Comments rewrite — remaining files

**Files:**
- Modify: `src/Reading.bend`, `src/LogicalKey.bend`, `src/EqTheory.bend`, `src/Comparison.bend`, `src/Merging.bend`, `src/Certificate.bend`, `LAWS.bend`, `PROOF.bend`, `tests/*.bend`, `benches/compare_bench.bend`

Rule (spec §3): delete every `#` line; write one header line per file (purpose + trust boundary if any) and one line per public def (contract, why-not-what, English, short). Law claims in `LAWS.bend` are NEVER edited — only `#` lines change (each law needs a comment above it for bolt `S001`). Insert the new comment line directly above each existing law in its CURRENT position; do not reorder laws; law bodies are shown as `...` below meaning "keep the existing line byte-identical".

- [ ] **Step 1: `src/Reading.bend`**

New header:
```python
# Pure chain-reading cores; LAWS.bend quantifies over these, never over IO.
# Entries are named ChainEntry Data, not String & String pairs: a & pair
# defaults to kind Type, which List<&2, _> rejects.
```
Plus one line per public def, e.g.:
```python
# Most-recent-wins lookup: the head of the chain is the newest commit.
def lookup_in_chain(...
# Drops older duplicates, keeping the first (newest) occurrence of each key.
def normalize_chain(...
```

- [ ] **Step 2: `src/LogicalKey.bend`**

```python
# Logical keys and the physical MyLSM key layout. All keys are ASCII with "/"
# separators so prefix scan stays possible at the storage layer.
```
`split_combined_key` gets: `# Inverse of encode_logical_key: splits at the FIRST "/".`

- [ ] **Step 3: `src/EqTheory.bend`**

```python
# Equality theory for key comparison: the reflexivity tower Word -> U32 ->
# Char -> String, discharged by induction. Base of the soundness tower —
# every general merge/read law rewrites with string_eq_refl.
```

- [ ] **Step 4: `src/Comparison.bend`**

```python
# Structural tree diff, membership-based (no ordering decisions): added =
# second-only keys, removed = first-only keys, modified = shared keys with
# different value hashes. Zero Cmp matching keeps every branch provable.
# The v0.3 fan-out splits entries alternately and compares halves in
# parallel; counts and sets agree with the sequential path, order does not
# (downstream merge sorts before hashing, so order never leaks into hashes).
```

- [ ] **Step 5: `src/Merging.bend`**

```python
# Three-way merge, strategy "union-disjoint". The pure core decides per key
# from (base, first, second) with an explicit truth table: equal inputs take
# the value, single-side changes win, delete-vs-unchanged drops, every other
# divergence conflicts (both delete-vs-modify directions — asymmetry would
# break commutativity). Results are sorted before hashing, so compatible
# merges commute as trees by construction.
```

- [ ] **Step 6: `src/Certificate.bend`**

```python
# Independent merge verification. The pure core re-derives everything from
# entry lists: strategy known, result hash matches recomputed hash, merge
# recomputation yields the same entry set, every recorded law passed and at
# least one law was recorded (empty evidence rejects). The shell loads the
# trees named by the certificate — a tampered cert names trees whose content
# contradicts its claims.
```

- [ ] **Step 7: `LAWS.bend`**

Keep one short family header per family and add one line per law. Replace the existing long comment blocks with:

```python
# LAW 1 family: empty-history base instances; general shadow-invariance is
# deferred (needs String.eq inversion — see spec §5.1 wall).
# Empty chain reads no value.
law empty_chain_reads_none: ...
# Tombstone resolution is stable on None.
law resolve_none_stable: ...
# Normalizing an empty chain is the identity.
law normalize_nil_stable: ...

# LAW 2 family: diff boundary instances on empty/singleton inputs.
# Empty vs empty yields no delta and zero counts.
law compare_empty_empty: ...
# Empty vs singleton: exactly one added key.
law compare_empty_singleton_added_single: ...
# Empty vs singleton: nothing removed.
law compare_empty_singleton_removed_none: ...
# Singleton vs empty: exactly one removed key.
law compare_singleton_empty_removed_single: ...
# Singleton vs empty: nothing added.
law compare_singleton_empty_added_none: ...

# LAW 3 family: full merge truth table on concrete keys — every (base, first,
# second) presence/value cell, machine-checked by computation.
# Identical single entries merge to one kept entry.
law merge_no_changes_keep: ...
# Disjoint keys union into both entries.
law merge_disjoint_union: ...
# Same key, two different values, no base: conflict.
law merge_same_key_conflict: ...
# Delete vs unchanged drops the entry.
law merge_delete_unchanged_drops: ...
# Delete vs modify conflicts.
law merge_delete_modify_conflicts: ...
# Modify vs delete conflicts (mirror direction).
law merge_modify_delete_conflicts: ...
# All three absent: empty merge.
law merge_absent_absent_absent: ...
# Same value on both sides, no base: kept once.
law merge_same_value_both_sides: ...
# First unchanged, second changed: keep second.
law merge_first_unchanged_keep_second: ...
# Second unchanged, first changed: keep first.
law merge_second_unchanged_keep_first: ...
# Three different values: conflict.
law merge_all_different_conflict: ...
# Only second present: kept.
law merge_absent_absent_present: ...
# Only base present: dropped.
law merge_present_absent_absent: ...

# LAW 4 family: certificate verification on concrete entries.
# Unknown strategy rejects.
law verify_rejects_unknown_strategy: ...
# Entries that do not match the recomputed merge reject.
law verify_rejects_wrong_entries: ...
# A faithfully recomputed certificate verifies.
law verify_accepts_recomputed: ...
# A tampered result tree hash rejects.
law verify_rejects_tampered_tree: ...
# Empty law evidence rejects — asserting nothing proves nothing.
law verify_rejects_empty_laws: ...

# Universal computational laws: count accounting and field layout for ALL
# inputs, no case analysis on computed values.
# Compared count is the sum of both input lengths.
law compare_counts_correct: ...
# Certificate first-parent field roundtrips.
law cert_first_parent_roundtrip: ...
# Certificate result-tree field roundtrips.
law cert_result_tree_roundtrip: ...

# Equality theory, universal: comparison is reflexive (EqTheory tower).
# String equality is reflexive.
law string_eq_refl: ...
# Word comparison is reflexive.
law word_cmp_refl: ...
```

- [ ] **Step 8: `PROOF.bend`**

```python
# Proofs for LAWS.bend: one def per law, same name. {==} closes every
# computational law; the two reflexivity laws delegate to EqTheory.
```

- [ ] **Step 9: tests + benches**

One header line per file (delete the old ones first):

```python
# IO harness: versioned reads across put/commit/delete cycles on a real
# MyLSM store; laws cover the pure cores, this covers the wiring.
```
(`tests/reading_check.bend`)
```python
# IO harness: linear commit materializes stage into tree/commit/index and
# the tree reads back with the expected entries.
```
(`tests/commit_read_check.bend`)
```python
# IO harness: disjoint and identical compares, pruning shortcut, missing
# trees tolerated as empty.
```
(`tests/comparison_check.bend`)
```python
# IO harness: content objects roundtrip by hash; identical payloads dedupe.
```
(`tests/content_object_check.bend`)
```python
# IO harness: pure key encoding and every storage-key builder.
```
(`tests/logical_key_check.bend`)
```python
# IO harness: disjoint merges succeed, same-key-different-value conflicts,
# ancestor walk finds the base, result accessors behave.
```
(`tests/merging_check.bend`)
```python
# IO harness: faithful certificates verify, tampered/empty/unknown ones fail.
```
(`tests/certificate_check.bend`)
```python
# IO harness: fanned and sequential compare agree on counts on small inputs.
```
(`tests/fanout_agreement_check.bend`)
```python
# IO harness: adapter encode/parse/get roundtrips and canonical bytes.
```
(`tests/json_adapter_check.bend`)
```python
# Bench: generated entry lists, sequential vs fanned compare, wall-timed
# natively. Checker-normalized runs are NOT timed.
```
(`benches/compare_bench.bend`)

- [ ] **Step 10: Gate + bolt + commit**

Run: `bend PROOF.bend` → `All terms check.`
Run: `/Users/fvega/dev/bolt/bin/bolt.bin 2>&1 | tail -3` → `0 errors`; our `S001` warnings gone (remaining warnings: `S002` long LAWS lines + `L001` on IO shells — accepted per spec §7).

```bash
git add src/Reading.bend src/LogicalKey.bend src/EqTheory.bend src/Comparison.bend src/Merging.bend src/Certificate.bend LAWS.bend PROOF.bend tests benches
git commit -m "docs(ber-core): rewrite all comments - headers, contracts, law one-liners"
```

---

### Task 10: Spec §2.1/§3.1 update + README

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-ber-core-design.md` (JSON row + serialization paragraph)
- Create: `README.md`

- [ ] **Step 1: Replace the JSON row in spec §2.1**

Replace the entire `| JSON parser/serializer | ... |` row with:

```
| JSON parser/serializer | `bend-kit-json@0.3.0.0` = `0xaaa10a97bf5ac6990143da2c863f8a3f` (paymog/bend-kit; `bend-net-json@0.3.0.0` is byte-identical except header) | VERIFIED: import-checks green on 2.0.28 (probe 2026-09-26); byte probe kit vs vendored rootagi PASSED on all 4 persisted doc shapes (content-object, commit, tree, stage-index) — canonical bytes identical, hash namespace unchanged | ADOPT (hash import) behind `src/JsonAdapter.bend`, the only module calling kit operations. `vendor/json/` deleted. Boundary: `encode` is `@unsafe` upstream (work-list walk); confined to the adapter, canonical-bytes property covered by probe + differential check vs Python `json`, not by proof. Replaces vendored rootagi (60 stated laws but broken upstream on 2.0.28; our probe subsumes the byte-compat concern). |
```

- [ ] **Step 2: Replace the serialization paragraph in spec §3.1**

Replace the `Serialization format: JSON via bend-json...` paragraph with:

```
Serialization format: canonical JSON via `bend-kit-json@0.3.0.0` behind `src/JsonAdapter.bend`. Objects/trees/commits persist with `encode_canonical` (keys emitted in char-code order by construction), so equal content ⇒ byte-identical text ⇒ stable content hashes. Payloads stay strings-only (no numbers, no `JRaw`-style raw nodes). Byte-compatibility with the pre-migration vendored encoder was probe-verified on every persisted shape before the cutover (2026-09-26). Perf caveat: very large inputs are slow — entries stay small line-shaped strings by construction; the v0.3 bench measures real tree sizes.
```

- [ ] **Step 3: Write `README.md`**

```markdown
# ber-core

Version-controlled state with machine-checked merge proofs, written in [Bend](https://github.com/bendlang/bend).

ber-core is a convergence + proof primitive on top of [MyLSM](https://github.com): content-addressed objects, flat Merkle state trees, linear and three-way (`union-disjoint`) commits, and merge certificates that re-verify independently. It never lies: `merge_commits` returns `MergeSuccess | MergeConflict | MergeUnprovable`, and a certificate asserts nothing it cannot recompute.

## The spec is executable

`LAWS.bend` states the properties, `PROOF.bend` proves them. The full merge truth table — every (base, first, second) presence/value cell — plus certificate accept/reject cases and a reflexivity tower (`Word → U32 → Char → String`) are machine-checked on every commit:

```bash
bend PROOF.bend   # All terms check.
```

No commit lands without a green gate (see `AGENTS.md`). `bolt` lints the tree with `correctness` findings as errors.

## Quickstart

```python
import Base
import ./src/Staging.bend as Staging
import ./src/History.bend as History
import ./src/LogicalKey.bend as LogicalKey
import ./src/Merging.bend as Merging
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore

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
| mylsm | `0.3.1.0` = `0x0ae7ac793853e753f5f74c16e06ee078` |
| bend-kit-json | `0.3.0.0` = `0xaaa10a97bf5ac6990143da2c863f8a3f` (behind `src/JsonAdapter.bend`) |
| bend-codec-lib | `0.2.0.0` (UTF-8 for the SHA glue) |
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
| `src/MyLsmBinding.bend` | the only file naming MyLSM effects |

## Benchmarks

```bash
bend benches/compare_bench.bend -o /tmp/compare_bench_bin
/tmp/compare_bench_bin 10000 fan
```

Sequential vs fanned compare; see the v0.3 notes in `docs/superpowers/plans/2026-09-25-ber-core.md`.

## Roadmap

v0.4 `SchemaLaw` extension point, v1.0 frozen API + BendHub board. Design and verification walls documented in `docs/superpowers/specs/`.
```

- [ ] **Step 4: Gate + commit**

Run: `bend PROOF.bend` → `All terms check.`

```bash
git add docs/superpowers/specs/2026-09-25-ber-core-design.md README.md
git commit -m "docs(ber-core): adopt kit-json in spec, add README"
```

---

### Task 11: Final gate

- [ ] **Step 1: Full sweep in one pass**

```bash
bend PROOF.bend
for f in tests/*_check.bend; do bend "$f"; done
/Users/fvega/dev/bolt/bin/bolt.bin 2>&1 | tail -3
```

Expected: `All terms check.`; every check prints only PASS/True lines; bolt `0 errors`.

- [ ] **Step 2: Diff review**

Run: `git log --oneline main..HEAD` and `git diff main --stat`
Expected: 11 commits (Tasks 0-10, one each); `vendor/` gone.
Law-claim integrity: `git diff main -- LAWS.bend PROOF.bend | grep -E "^[-+]" | grep -vE "^[-+]{2}" | grep -v "#"` must print NOTHING — every changed line is a `#` comment; no law or proof body changed.

- [ ] **Step 3: Report**

Summarize: migration evidence (probe PASS), dead code removed, bolt state, remaining accepted warnings.

---

## Self-review

- **Spec coverage:** §1 laws-vs-tests → no test deletion (tests are IO wiring; verified no pure-duplicate asserts worth removing — Task 7 sweep keeps all 9 checks). §2 adapter+kit → Tasks 1-7 (probe load-bearing first, per spec). §3 comments → Tasks 3-6 Step 3 + Task 9. §4 bend-cli → absent by design. §5 mylsm comment fix → Task 8 Step 2. §6 dead code → Task 8 (exactly the two confirmed defs + WalTypes import). §7 bolt → Task 0 + gates in 7/9/11. §8 README → Task 10. §9 testing → gates every task + Task 11.
- **Placeholders:** none — every code-changing step shows full code or exact-string tables; probe/adapter/README/spec rows are complete.
- **Type consistency:** `Json.Val` / `JsonAdapter.{make_str,make_arr,make_kv,make_obj,parse_text,get_field,as_str,as_arr,encode_canonical}` identical across Tasks 2-6; `Sigma<&2, &2, String, _ => Json.Val>` matches kit's `items.obj` shape; `Maybe<&2, Json.Val>` replaces `Result<&2, &2, String, JsonLib.Json>` everywhere it appeared (`object_from_parse_result`, `tree_from_parse`, `commit_from_parse`, `index_from_text`).
- **Bend legality:** adapter `fold_fields` shrinks in argument position 1; probe `probe_fold` same; constructor patterns `case Json.Str{text}:` / `case Merging.MergedEntries{...}:` are established in-repo (Certificate.bend); no `match` on computed values introduced; no forward references (adapter order: make_str/make_arr/make_kv/fold_pair/fold_fields/make_obj/parse_text/get_field/as_str/as_arr/encode_canonical).
