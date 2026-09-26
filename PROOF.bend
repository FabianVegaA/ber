import Base
import ./LAWS.bend as Laws
import ./src/EqTheory.bend as EqTheory

# Proofs for LAWS.bend. Each law gets a def of the same name.
def Laws.empty_chain_reads_none(namespace_name, record_identifier):
  {==}

def Laws.resolve_none_stable():
  {==}

def Laws.normalize_nil_stable():
  {==}

def Laws.compare_empty_empty():
  {==}

def Laws.compare_empty_singleton_added_single(entry_key, entry_value):
  {==}

def Laws.compare_empty_singleton_removed_none(entry_key, entry_value):
  {==}

def Laws.compare_singleton_empty_removed_single(entry_key, entry_value):
  {==}

def Laws.compare_singleton_empty_added_none(entry_key, entry_value):
  {==}

def Laws.merge_no_changes_keep():
  {==}

def Laws.merge_disjoint_union():
  {==}

def Laws.merge_same_key_conflict():
  {==}

def Laws.merge_delete_unchanged_drops():
  {==}

def Laws.merge_delete_modify_conflicts():
  {==}

def Laws.merge_modify_delete_conflicts():
  {==}

def Laws.merge_absent_absent_absent():
  {==}

def Laws.merge_same_value_both_sides():
  {==}

def Laws.merge_first_unchanged_keep_second():
  {==}

def Laws.merge_second_unchanged_keep_first():
  {==}

def Laws.merge_all_different_conflict():
  {==}

def Laws.merge_absent_absent_present():
  {==}

def Laws.merge_present_absent_absent():
  {==}

def Laws.verify_rejects_unknown_strategy():
  {==}

def Laws.verify_rejects_wrong_entries():
  {==}

def Laws.compare_counts_correct(first_entries, second_entries):
  {==}

def Laws.cert_first_parent_roundtrip(first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws):
  {==}

def Laws.cert_result_tree_roundtrip(first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws):
  {==}

def Laws.verify_accepts_recomputed():
  {==}

def Laws.verify_rejects_tampered_tree():
  {==}

def Laws.verify_rejects_empty_laws():
  {==}

def Laws.string_eq_refl(text):
  EqTheory.string_eq_refl(text)

def Laws.word_cmp_refl(width, word):
  EqTheory.word_cmp_refl(width, word)
