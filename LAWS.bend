import Base
import ./src/Reading.bend as Reading
import ./src/LogicalKey.bend as LogicalKey
import ./src/Comparison.bend as Comparison
import ./src/Merging.bend as Merging
import ./src/StateTree.bend as StateTree
import ./src/Certificate.bend as Certificate

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

# LAW 4 FAMILY, v0.1 instances (Task 7): certificate verification pins on
# CONCRETE entries. The pure core re-derives hash + merge + law-evidence, so
# all hold by computation. Universal verify-soundness needs the eq epic.
law verify_accepts_recomputed:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "union-disjoint", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == True{} : Bool}

law verify_rejects_tampered_tree:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", "0000tampered", "union-disjoint", Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}) == False{} : Bool}

law verify_rejects_empty_laws:
  {Certificate.verify_merge_certificate_pure(Nil{}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Nil{}}, Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}, Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}, Merging.Make{"commit_first", "commit_second", "commit_base", StateTree.compute_tree_hash(Con{Reading.make_entry("ledger/record_alpha", "alpha_version"), Con{Reading.make_entry("ledger/record_beta", "beta_version"), Nil{}}}), "union-disjoint", Nil{}}) == False{} : Bool}
