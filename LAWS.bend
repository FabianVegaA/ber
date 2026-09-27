import Base
import ./src/Reading.bend as Reading
import ./src/LogicalKey.bend as LogicalKey
import ./src/ContentHash.bend as ContentHash
import ./src/Comparison.bend as Comparison
import ./src/Merging.bend as Merging
import ./src/StateTree.bend as StateTree
import ./src/Certificate.bend as Certificate
import ./src/EqTheory.bend as EqTheory
import ./src/JsonAdapter.bend as JsonAdapter
import ./src/Value.bend as Value
import bend-kit-json@0.3.0.0/json.bend as Json

# LAW 1 family: empty-history base instances; general shadow-invariance is
# deferred (needs String.eq inversion — see spec section 5.1 wall).
# Empty chain reads no value.
law empty_chain_reads_none:
  for namespace_name: String
  for record_identifier: String
  {Reading.lookup_in_chain(namespace_name, record_identifier, Nil{}) == None{} : Maybe<&2, String>}

# Tombstone resolution is stable on None.
law resolve_none_stable:
  {Reading.resolve_tombstone(None{}) == None{} : Maybe<&2, String>}

# Normalizing an empty chain is the identity.
law normalize_nil_stable:
  {Reading.normalize_chain(Nil{}) == Nil{} : List<&2, Reading.ChainEntry>}

# LAW 2 family: diff boundary instances on empty/singleton inputs.
# Empty vs empty yields no delta and zero counts.
law compare_empty_empty:
  {Comparison.compare_sorted_entries(Nil{}, Nil{}) == Comparison.Make{Nil{}, Nil{}, Nil{}, 0n, 0n} : Comparison.CompareResult}

# Empty vs singleton: exactly one added key.
law compare_empty_singleton_added_single:
  for entry_key: String
  for entry_value: String
  {List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(Comparison.compare_sorted_entries(Nil{}, Con{Reading.make_entry(entry_key, entry_value), Nil{}}))) == 1n : Nat}

# Empty vs singleton: nothing removed.
law compare_empty_singleton_removed_none:
  for entry_key: String
  for entry_value: String
  {Comparison.removed_keys_of(Comparison.compare_sorted_entries(Nil{}, Con{Reading.make_entry(entry_key, entry_value), Nil{}})) == Nil{} : List<&2, LogicalKey.LogicalKey>}

# Singleton vs empty: exactly one removed key.
law compare_singleton_empty_removed_single:
  for entry_key: String
  for entry_value: String
  {List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry(entry_key, entry_value), Nil{}}, Nil{}))) == 1n : Nat}

# Singleton vs empty: nothing added.
law compare_singleton_empty_added_none:
  for entry_key: String
  for entry_value: String
  {Comparison.added_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry(entry_key, entry_value), Nil{}}, Nil{})) == Nil{} : List<&2, LogicalKey.LogicalKey>}

# LAW 3 family: full merge truth table on concrete keys — every (base, first,
# second) presence/value cell, machine-checked by computation.
# Identical single entries merge to one kept entry.
law merge_no_changes_keep:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}} : Merging.MergeOutcome}

# Disjoint keys union into both entries.
law merge_disjoint_union:
  {Merging.merge_entry_lists(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}} : Merging.MergeOutcome}

# Same key, two different values, no base: conflict.
law merge_same_key_conflict:
  {Merging.merge_entry_lists(Nil{}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}) == Merging.ConflictingKeys{Con{LogicalKey.split_combined_key("ledger/record_first"), Nil{}}} : Merging.MergeOutcome}

# Delete vs unchanged drops the entry.
law merge_delete_unchanged_drops:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Nil{}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}) == Merging.MergedEntries{Nil{}} : Merging.MergeOutcome}

# Delete vs modify conflicts.
law merge_delete_modify_conflicts:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Nil{}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}) == Merging.ConflictingKeys{Con{LogicalKey.split_combined_key("ledger/record_first"), Nil{}}} : Merging.MergeOutcome}

# Modify vs delete conflicts (mirror direction).
law merge_modify_delete_conflicts:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}, Nil{}) == Merging.ConflictingKeys{Con{LogicalKey.split_combined_key("ledger/record_first"), Nil{}}} : Merging.MergeOutcome}

# All three absent: empty merge.
law merge_absent_absent_absent:
  {Merging.merge_entry_lists(Nil{}, Nil{}, Nil{}) == Merging.MergedEntries{Nil{}} : Merging.MergeOutcome}

# Same value on both sides, no base: kept once.
law merge_same_value_both_sides:
  {Merging.merge_entry_lists(Nil{}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}} : Merging.MergeOutcome}

# First unchanged, second changed: keep second.
law merge_first_unchanged_keep_second:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}} : Merging.MergeOutcome}

# Second unchanged, first changed: keep first.
law merge_second_unchanged_keep_first:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}} : Merging.MergeOutcome}

# Three different values: conflict.
law merge_all_different_conflict:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_three"), Nil{}}) == Merging.ConflictingKeys{Con{LogicalKey.split_combined_key("ledger/record_first"), Nil{}}} : Merging.MergeOutcome}

# Only second present: kept.
law merge_absent_absent_present:
  {Merging.merge_entry_lists(Nil{}, Nil{}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}} : Merging.MergeOutcome}

# Only base present: dropped.
law merge_present_absent_absent:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Nil{}, Nil{}) == Merging.MergedEntries{Nil{}} : Merging.MergeOutcome}

# LAW 4 family: certificate verification on concrete entries.
# Unknown strategy rejects.
law verify_rejects_unknown_strategy:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "sideways-merge", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == False{} : Bool}

# Entries that do not match the recomputed merge reject.
law verify_rejects_wrong_entries:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "union-disjoint", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == False{} : Bool}

# Universal computational laws: count accounting and field layout for ALL
# inputs, no case analysis on computed values.
# Compared count is the sum of both input lengths.
law compare_counts_correct:
  for first_entries: List<&2, Reading.ChainEntry>
  for second_entries: List<&2, Reading.ChainEntry>
  {Comparison.compared_entry_count_of(Comparison.compare_sorted_entries(first_entries, second_entries)) == Nat.add(List.length(&2, Reading.ChainEntry, first_entries), List.length(&2, Reading.ChainEntry, second_entries)) : Nat}

# Certificate first-parent field roundtrips.
law cert_first_parent_roundtrip:
  for first_parent_commit: String
  for second_parent_commit: String
  for base_commit: String
  for result_tree_hash: String
  for strategy_name: String
  for checked_laws: List<&2, Merging.LawCheck>
  {Merging.cert_first_parent(Merging.Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}) == first_parent_commit : String}

# Certificate result-tree field roundtrips.
law cert_result_tree_roundtrip:
  for first_parent_commit: String
  for second_parent_commit: String
  for base_commit: String
  for result_tree_hash: String
  for strategy_name: String
  for checked_laws: List<&2, Merging.LawCheck>
  {Merging.cert_result_tree(Merging.Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}) == result_tree_hash : String}

# A faithfully recomputed certificate verifies.
law verify_accepts_recomputed:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "union-disjoint", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == True{} : Bool}

# A tampered result tree hash rejects.
law verify_rejects_tampered_tree:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", "0000tampered", "union-disjoint", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == False{} : Bool}

# Empty law evidence rejects — asserting nothing proves nothing.
law verify_rejects_empty_laws:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "union-disjoint", Nil{}}) == False{} : Bool}

# Equality theory, universal: comparison is reflexive (EqTheory tower).
# String equality is reflexive.
law string_eq_refl:
  for text: String
  {String.eq(text, text) == True{} : Bool}

# Word comparison is reflexive.
law word_cmp_refl:
  for width: Nat
  for word: Word(width)
  {Word.cmp(width, word, word) == EQ{} : Cmp}

# ADAPTER family: canonical bytes, roundtrip and missing fields on concrete
# documents. The encoder is @unsafe upstream; these laws pin its observable
# behavior on our shapes by computation.
# Canonical bytes of the content-object shape.
law adapter_canonical_bytes:
  {JsonAdapter.encode_canonical(JsonAdapter.make_obj(Con{JsonAdapter.make_kv("payload", JsonAdapter.make_str("hello")), Con{JsonAdapter.make_kv("references", JsonAdapter.make_arr(Con{JsonAdapter.make_str("ref_a"), Nil{}})), Nil{}}})) == "{\"payload\":\"hello\",\"references\":[\"ref_a\"]}" : String}

# Absent fields read as None.
law adapter_missing_none:
  {JsonAdapter.get_field(JsonAdapter.make_obj(Con{JsonAdapter.make_kv("payload", JsonAdapter.make_str("hello")), Nil{}}), "absent") == None{} : Maybe<&2, Json.Val>}

# Parse inverts encode on the content-object shape.
law adapter_parse_roundtrip:
  {JsonAdapter.parse_text(JsonAdapter.encode_canonical(JsonAdapter.make_obj(Con{JsonAdapter.make_kv("payload", JsonAdapter.make_str("hello")), Con{JsonAdapter.make_kv("references", JsonAdapter.make_arr(Con{JsonAdapter.make_str("ref_a"), Nil{}})), Nil{}}}))) == Some{JsonAdapter.make_obj(Con{JsonAdapter.make_kv("payload", JsonAdapter.make_str("hello")), Con{JsonAdapter.make_kv("references", JsonAdapter.make_arr(Con{JsonAdapter.make_str("ref_a"), Nil{}})), Nil{}}})} : Maybe<&2, Json.Val>}

# VALUE family: roundtrips per constructor plus pairwise injectivity of the
# tagged canonical forms (different constructors never share bytes).
# Text roundtrips through its tagged form.
law value_text_roundtrip:
  {Value.value_from_json(Value.value_to_json(Value.Text{"hello"})) == Some{Value.Text{"hello"}} : Maybe<&2, Value.Value>}

# Document roundtrips through its tagged form.
law value_object_roundtrip:
  {Value.value_from_json(Value.value_to_json(Value.Object{JsonAdapter.make_obj(Con{JsonAdapter.make_kv("k", JsonAdapter.make_str("v")), Nil{}})})) == Some{Value.Object{JsonAdapter.make_obj(Con{JsonAdapter.make_kv("k", JsonAdapter.make_str("v")), Nil{}})}} : Maybe<&2, Value.Value>}

# Blob roundtrips through its hex tagged form.
law value_blob_roundtrip:
  {Value.value_from_json(Value.value_to_json(Value.Blob{Con{0, Con{1, Con{2, Con{250, Nil{}}}}}})) == Some{Value.Blob{Con{0, Con{1, Con{2, Con{250, Nil{}}}}}}} : Maybe<&2, Value.Value>}

# Text and document never share canonical bytes.
law value_injective_text_object:
  {String.eq(Value.value_to_canonical(Value.Text{"x"}), Value.value_to_canonical(Value.Object{JsonAdapter.make_str("x")})) == False{} : Bool}

# Text and blob never share canonical bytes.
law value_injective_text_blob:
  {String.eq(Value.value_to_canonical(Value.Text{"x"}), Value.value_to_canonical(Value.Blob{Con{0, Con{1, Con{2, Con{250, Nil{}}}}}})) == False{} : Bool}

# Document and blob never share canonical bytes.
law value_injective_object_blob:
  {String.eq(Value.value_to_canonical(Value.Object{JsonAdapter.make_str("x")}), Value.value_to_canonical(Value.Blob{Con{0, Con{1, Con{2, Con{250, Nil{}}}}}})) == False{} : Bool}

# KEY family: logical encoding, storage layouts, and SHA-256 known answers.
# Renders namespace and record with a slash separator.
law key_encode_logical:
  {LogicalKey.encode_logical_key(LogicalKey.Make{"ledger", "abc"}) == "ledger/abc" : String}

# Object storage layout.
law key_object_storage:
  {LogicalKey.build_object_storage_key("deadbeef") == "object/deadbeef" : String}

# Version index layout.
law key_index_storage:
  {LogicalKey.build_index_storage_key("ledger", "abc", "commit_first") == "index/ledger/abc/commit_first" : String}

# Stage layout.
law key_stage_storage:
  {LogicalKey.build_stage_storage_key("session_first", "ledger", "abc") == "stage/session_first/ledger/abc" : String}

# SHA-256 known answer (FIPS vector for "abc").
law hash_known_answer_abc:
  {ContentHash.compute_sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" : String}

# Distinct inputs hash distinctly.
law hash_distinct_hello_world:
  {String.eq(ContentHash.compute_sha256_hex("hello"), ContentHash.compute_sha256_hex("world")) == False{} : Bool}

# MEMBERSHIP family: the reference diff pins counts on a small concrete
# fixture (added/removed/modified all exercised once). Kept as the safe
# differential oracle for the sorted path.
# Sequential added count on the fixture.
law membership_added_one:
  {List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("bench/key-1", "version-1"), Con{Reading.make_entry("bench/key-2", "version-2"), Con{Reading.make_entry("bench/key-3", "version-3"), Nil{}}}}, Con{Reading.make_entry("bench/key-1", "version-1"), Con{Reading.make_entry("bench/key-2", "version-2-changed"), Con{Reading.make_entry("bench/key-4", "version-4"), Nil{}}}}))) == 1n : Nat}

# Sequential removed count on the fixture.
law membership_removed_one:
  {List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("bench/key-1", "version-1"), Con{Reading.make_entry("bench/key-2", "version-2"), Con{Reading.make_entry("bench/key-3", "version-3"), Nil{}}}}, Con{Reading.make_entry("bench/key-1", "version-1"), Con{Reading.make_entry("bench/key-2", "version-2-changed"), Con{Reading.make_entry("bench/key-4", "version-4"), Nil{}}}}))) == 1n : Nat}

# Sequential modified count on the fixture.
law membership_modified_one:
  {List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("bench/key-1", "version-1"), Con{Reading.make_entry("bench/key-2", "version-2"), Con{Reading.make_entry("bench/key-3", "version-3"), Nil{}}}}, Con{Reading.make_entry("bench/key-1", "version-1"), Con{Reading.make_entry("bench/key-2", "version-2-changed"), Con{Reading.make_entry("bench/key-4", "version-4"), Nil{}}}}))) == 1n : Nat}

# Branch diff adds exactly one key.
law compare_branch_added_one:
  {List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}, Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}))) == 1n : Nat}

# Branch diff removes exactly one key.
law compare_branch_removed_one:
  {List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}, Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}))) == 1n : Nat}

# Branch diff modifies nothing.
law compare_branch_modified_none:
  {List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}, Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}))) == 0n : Nat}

# Identical trees prune with one prune counted and zero compared.
law compare_pruned_self:
  {Comparison.compare_loaded_trees(Some{StateTree.Make{"h", Nil{}, Nil{}}}, Some{StateTree.Make{"h", Nil{}, Nil{}}}) == Comparison.Make{Nil{}, Nil{}, Nil{}, 1n, 0n} : Comparison.CompareResult}

# MERGE-COUNT family: multi-key outcomes of the merging_check fixtures.
# Disjoint branch merge yields three entries.
law merge_branch_count_three:
  {List.length(&2, Reading.ChainEntry, Merging.merged_entries_of(Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_base", "base_version"), Nil{}}, Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}, Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}))) == 3n : Nat}

# Same-key-different-value merge conflicts on exactly one key.
law merge_conflict_count_one:
  {List.length(&2, LogicalKey.LogicalKey, Merging.conflicting_keys_of(Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_base", "base_version"), Nil{}}, Con{Reading.make_entry("ledger/record_base", "version_ex"), Nil{}}, Con{Reading.make_entry("ledger/record_base", "version_wye"), Nil{}}))) == 1n : Nat}

# Merge sort orders the fixture by key.
law sort_fixture_sorted:
  {Comparison.sort_entries_by_key(Con{Reading.make_entry("ledger/c", "3"), Con{Reading.make_entry("ledger/a", "1"), Con{Reading.make_entry("ledger/b", "2"), Nil{}}}}) == Con{Reading.make_entry("ledger/a", "1"), Con{Reading.make_entry("ledger/b", "2"), Con{Reading.make_entry("ledger/c", "3"), Nil{}}}} : List<&2, Reading.ChainEntry>}

# Sorting preserves entry count.
law sort_preserves_count:
  {List.length(&2, Reading.ChainEntry, Comparison.sort_entries_by_key(Con{Reading.make_entry("ledger/c", "3"), Con{Reading.make_entry("ledger/a", "1"), Con{Reading.make_entry("ledger/b", "2"), Nil{}}}})) == 3n : Nat}

# Linear diff agrees with membership diff on added.
law sort_merge_agree_added:
  {List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(Comparison.merge_sorted_diff(Comparison.sort_entries_by_key(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}), Comparison.sort_entries_by_key(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}})))) == List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}, Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}))) : Nat}

# Linear diff agrees with membership diff on removed.
law sort_merge_agree_removed:
  {List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(Comparison.merge_sorted_diff(Comparison.sort_entries_by_key(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}), Comparison.sort_entries_by_key(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}})))) == List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}, Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}))) : Nat}

# Linear diff agrees with membership diff on modified.
law sort_merge_agree_modified:
  {List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(Comparison.merge_sorted_diff(Comparison.sort_entries_by_key(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}), Comparison.sort_entries_by_key(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}})))) == List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(Comparison.compare_sorted_entries(Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}}, Con{Reading.make_entry("ledger/record_base", "base_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}))) : Nat}
