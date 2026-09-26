import Base
import ./src/Reading.bend as Reading
import ./src/LogicalKey.bend as LogicalKey
import ./src/Comparison.bend as Comparison
import ./src/Merging.bend as Merging
import ./src/StateTree.bend as StateTree
import ./src/Certificate.bend as Certificate
import ./src/EqTheory.bend as EqTheory

# LAW 1, v0.1 instances: empty-history behavior, proven below (green gate).
# Each pins a base case against regressions; none branches on key comparison,
# so all hold by computation ({==}).
#
# The GENERAL shadow-invariance law
#   lookup(ns, id, normalize(chain)) == lookup(ns, id, chain)
# is PROOF-DEFERRED (see spec): its False-branch needs String.eq
# transitivity/symmetry, a characterization library neither Base nor
# bend-lemmas ships. It becomes the first law of the v0.2 lemma-library epic.
law empty_chain_reads_none:
  for namespace_name: String
  for record_identifier: String
  {Reading.lookup_in_chain(namespace_name, record_identifier, Nil{}) == None{} : Maybe<&2, String>}

law resolve_none_stable:
  {Reading.resolve_tombstone(None{}) == None{} : Maybe<&2, String>}

law normalize_nil_stable:
  {Reading.normalize_chain(Nil{}) == Nil{} : List<&2, Reading.ChainEntry>}

# LAW 2 FAMILY, v0.1 instances (Task 5): diff boundary behavior, no key
# comparison evaluated on these shapes, so all hold by computation.
# General reflexivity/symmetry need the eq-lemma epic (deferred, like Law 1).
law compare_empty_empty:
  {Comparison.compare_sorted_entries(Nil{}, Nil{}) == Comparison.Make{Nil{}, Nil{}, Nil{}, 0n, 0n} : Comparison.CompareResult}

law compare_empty_singleton_added_single:
  for entry_key: String
  for entry_value: String
  {List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(Comparison.compare_sorted_entries(Nil{}, Con{Reading.make_entry(entry_key, entry_value), Nil{}}))) == 1n : Nat}

law compare_empty_singleton_removed_none:
  for entry_key: String
  for entry_value: String
  {Comparison.removed_keys_of(Comparison.compare_sorted_entries(Nil{}, Con{Reading.make_entry(entry_key, entry_value), Nil{}})) == Nil{} : List<&2, LogicalKey.LogicalKey>}

law compare_singleton_empty_removed_single:
  for entry_key: String
  for entry_value: String
  {List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry(entry_key, entry_value), Nil{}}, Nil{}))) == 1n : Nat}

law compare_singleton_empty_added_none:
  for entry_key: String
  for entry_value: String
  {Comparison.added_keys_of(Comparison.compare_sorted_entries(Con{Reading.make_entry(entry_key, entry_value), Nil{}}, Nil{})) == Nil{} : List<&2, LogicalKey.LogicalKey>}

# LAW 3 FAMILY, v0.1 instances (Task 6): merge truth-table pins on CONCRETE
# keys/values. Every String.eq fully reduces on literals, so all hold by
# computation ({==}) — the bend-json "concrete regression example" pattern.
# Universal idempotence/commutativity need the eq-lemma epic (deferred).
law merge_no_changes_keep:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}} : Merging.MergeOutcome}

law merge_disjoint_union:
  {Merging.merge_entry_lists(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}} : Merging.MergeOutcome}

law merge_same_key_conflict:
  {Merging.merge_entry_lists(Nil{}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}) == Merging.ConflictingKeys{Con{LogicalKey.split_combined_key("ledger/record_first"), Nil{}}} : Merging.MergeOutcome}

law merge_delete_unchanged_drops:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Nil{}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}) == Merging.MergedEntries{Nil{}} : Merging.MergeOutcome}

law merge_delete_modify_conflicts:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Nil{}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}) == Merging.ConflictingKeys{Con{LogicalKey.split_combined_key("ledger/record_first"), Nil{}}} : Merging.MergeOutcome}

law merge_modify_delete_conflicts:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}, Nil{}) == Merging.ConflictingKeys{Con{LogicalKey.split_combined_key("ledger/record_first"), Nil{}}} : Merging.MergeOutcome}

# FULL TRUTH TABLE, remaining cells (Task: formalization finale). Every
# (base, first, second) presence/value combination is pinned on concrete keys.
# All hold by computation ({==}) — the table IS the specification, and these
# laws are its machine-checked regression net. Universal versions need
# hypothesis inversion (see spec §5 wall) and stay deferred.
law merge_absent_absent_absent:
  {Merging.merge_entry_lists(Nil{}, Nil{}, Nil{}) == Merging.MergedEntries{Nil{}} : Merging.MergeOutcome}

law merge_same_value_both_sides:
  {Merging.merge_entry_lists(Nil{}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}} : Merging.MergeOutcome}

law merge_first_unchanged_keep_second:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}} : Merging.MergeOutcome}

law merge_second_unchanged_keep_first:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}} : Merging.MergeOutcome}

law merge_all_different_conflict:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_two"), Nil{}}, Con{Reading.make_entry("ledger/record_first", "version_three"), Nil{}}) == Merging.ConflictingKeys{Con{LogicalKey.split_combined_key("ledger/record_first"), Nil{}}} : Merging.MergeOutcome}

law merge_absent_absent_present:
  {Merging.merge_entry_lists(Nil{}, Nil{}, Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}) == Merging.MergedEntries{Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}} : Merging.MergeOutcome}

law merge_present_absent_absent:
  {Merging.merge_entry_lists(Con{Reading.make_entry("ledger/record_first", "version_one"), Nil{}}, Nil{}, Nil{}) == Merging.MergedEntries{Nil{}} : Merging.MergeOutcome}

law verify_rejects_unknown_strategy:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "sideways-merge", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == False{} : Bool}

law verify_rejects_wrong_entries:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "union-disjoint", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == False{} : Bool}

# UNIVERSAL COMPUTATIONAL laws (finale): properties over open terms whose
# proofs need NO case analysis on computed values — the goal reduces
# definitionally, closed by {==}. They pin count accounting and field layout
# for ALL inputs, not just fixtures.
law compare_counts_correct:
  for first_entries: List<&2, Reading.ChainEntry>
  for second_entries: List<&2, Reading.ChainEntry>
  {Comparison.compared_entry_count_of(Comparison.compare_sorted_entries(first_entries, second_entries)) == Nat.add(List.length(&2, Reading.ChainEntry, first_entries), List.length(&2, Reading.ChainEntry, second_entries)) : Nat}

law cert_first_parent_roundtrip:
  for first_parent_commit: String
  for second_parent_commit: String
  for base_commit: String
  for result_tree_hash: String
  for strategy_name: String
  for checked_laws: List<&2, Merging.LawCheck>
  {Merging.cert_first_parent(Merging.Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}) == first_parent_commit : String}

law cert_result_tree_roundtrip:
  for first_parent_commit: String
  for second_parent_commit: String
  for base_commit: String
  for result_tree_hash: String
  for strategy_name: String
  for checked_laws: List<&2, Merging.LawCheck>
  {Merging.cert_result_tree(Merging.Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}) == result_tree_hash : String}

# LAW 4 FAMILY, v0.1 instances (Task 7): certificate verification pins on
# CONCRETE entries. The pure core re-derives hash + merge + law-evidence, so
# all hold by computation. Universal verify-soundness needs the eq epic.
law verify_accepts_recomputed:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "union-disjoint", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == True{} : Bool}

law verify_rejects_tampered_tree:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", "0000tampered", "union-disjoint", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == False{} : Bool}

law verify_rejects_empty_laws:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "union-disjoint", Nil{}}) == False{} : Bool}

# EQUALITY THEORY, universal (EqTheory): key comparison is reflexive.
# These are the first universal laws over open terms in ber-core — every
# general merge/read law rewrites with string_eq_refl; it is the base of the
# soundness tower (bool-true ⟹ propositional equality).
law string_eq_refl:
  for text: String
  {String.eq(text, text) == True{} : Bool}

law word_cmp_refl:
  for width: Nat
  for word: Word(width)
  {Word.cmp(width, word, word) == EQ{} : Cmp}
