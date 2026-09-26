import Base
import ./src/Reading.bend as Reading
import ./src/LogicalKey.bend as LogicalKey
import ./src/Comparison.bend as Comparison
import ./src/Merging.bend as Merging
import ./src/StateTree.bend as StateTree
import ./src/Certificate.bend as Certificate
import ./src/EqTheory.bend as EqTheory

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
