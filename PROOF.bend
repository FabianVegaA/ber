import Base
import ./LAWS.bend as Laws

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

def Laws.verify_accepts_recomputed():
  {==}

def Laws.verify_rejects_tampered_tree():
  {==}

def Laws.verify_rejects_empty_laws():
  {==}
