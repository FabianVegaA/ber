import Base
import ./Reading.bend as Reading
import ./LogicalKey.bend as LogicalKey
import ./StateTree.bend as StateTree
import ./History.bend as History
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore

# Structural tree diff. MEMBERSHIP-based (no ordering decisions) —
# added = entries of second whose key is absent in first, symmetric removed,
# modified = shared keys with different value hashes. O(n*m) worst case, tiny
# constants, zero Cmp matching (String.cmp hands back nested pairs and every
# order-branch would need eq-transitivity downstream — deferred to the lemma
# epic). The shape is embarrassingly parallel per entry (v0.3 GPU fan-out):
# each membership test is independent.
#
# EFFECT RULE: Sess composition here reads trees via History only.
# MyLsmStore named for Sess types only.

type ModifiedEntry is Data:
  Changed{changed_key: LogicalKey.LogicalKey, before_hash: String, after_hash: String}

type CompareResult is Data:
  Make{added_keys: List<&2, LogicalKey.LogicalKey>, removed_keys: List<&2, LogicalKey.LogicalKey>, modified_entries: List<&2, ModifiedEntry>, pruned_subtree_count: Nat, compared_entry_count: Nat}

def added_keys_of(compare_result: CompareResult) -> List<&2, LogicalKey.LogicalKey>:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      added_keys

def removed_keys_of(compare_result: CompareResult) -> List<&2, LogicalKey.LogicalKey>:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      removed_keys

def modified_entries_of(compare_result: CompareResult) -> List<&2, ModifiedEntry>:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      modified_entries

def pruned_count_of(compare_result: CompareResult) -> Nat:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      pruned_subtree_count

def compared_entry_count_of(compare_result: CompareResult) -> Nat:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      compared_entry_count

def entry_to_logical_key(head_entry: Reading.ChainEntry) -> LogicalKey.LogicalKey:
  LogicalKey.split_combined_key(Reading.entry_key_of(head_entry))

def decide_member_found(head_matches: Bool, recursive_result: Bool) -> Bool:
  match head_matches:
    case True{}:
      True{}
    case False{}:
      recursive_result

def key_in_entries(+target_key: String, entries: List<&2, Reading.ChainEntry>) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{head_entry, remaining_entries}:
      decide_member_found(String.eq(Reading.entry_key_of(head_entry), target_key), key_in_entries(target_key, remaining_entries))

def decide_member_keep(is_member: Bool, +head_entry: Reading.ChainEntry, tail_keys: List<&2, LogicalKey.LogicalKey>) -> List<&2, LogicalKey.LogicalKey>:
  match is_member:
    case True{}:
      tail_keys
    case False{}:
      Con{entry_to_logical_key(head_entry), tail_keys}

def second_only_entries(+first_entries: List<&2, Reading.ChainEntry>, second_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  match second_entries:
    case Nil{}:
      Nil{}
    case Con{+head_entry, remaining_entries}:
      decide_member_keep(key_in_entries(Reading.entry_key_of(head_entry), first_entries), head_entry, second_only_entries(first_entries, remaining_entries))

def first_only_entries(+second_entries: List<&2, Reading.ChainEntry>, first_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  match first_entries:
    case Nil{}:
      Nil{}
    case Con{+head_entry, remaining_entries}:
      decide_member_keep(key_in_entries(Reading.entry_key_of(head_entry), second_entries), head_entry, first_only_entries(second_entries, remaining_entries))

def decide_value_found(head_matches: Bool, head_value: String, tail_result: Maybe<&2, String>) -> Maybe<&2, String>:
  match head_matches:
    case True{}:
      Some{head_value}
    case False{}:
      tail_result

def value_of_key(+target_key: String, entries: List<&2, Reading.ChainEntry>) -> Maybe<&2, String>:
  match entries:
    case Nil{}:
      None{}
    case Con{+head_entry, remaining_entries}:
      decide_value_found(String.eq(Reading.entry_key_of(head_entry), target_key), Reading.entry_value_of(head_entry), value_of_key(target_key, remaining_entries))

def decide_modified_value(values_equal: Bool, +head_entry: Reading.ChainEntry, +second_value: String, tail_modified: List<&2, ModifiedEntry>) -> List<&2, ModifiedEntry>:
  match values_equal:
    case True{}:
      tail_modified
    case False{}:
      Con{Changed{entry_to_logical_key(head_entry), Reading.entry_value_of(head_entry), second_value}, tail_modified}

def decide_modified_member(second_value_maybe: Maybe<&2, String>, +head_entry: Reading.ChainEntry, tail_modified: List<&2, ModifiedEntry>) -> List<&2, ModifiedEntry>:
  match second_value_maybe:
    case None{}:
      tail_modified
    case Some{+second_value}:
      decide_modified_value(String.eq(Reading.entry_value_of(head_entry), second_value), head_entry, second_value, tail_modified)

def changed_pairs(+second_entries: List<&2, Reading.ChainEntry>, first_entries: List<&2, Reading.ChainEntry>) -> List<&2, ModifiedEntry>:
  match first_entries:
    case Nil{}:
      Nil{}
    case Con{+head_entry, remaining_entries}:
      decide_modified_member(value_of_key(Reading.entry_key_of(head_entry), second_entries), head_entry, changed_pairs(second_entries, remaining_entries))

def compare_sorted_entries(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  Make{second_only_entries(first_entries, second_entries), first_only_entries(second_entries, first_entries), changed_pairs(second_entries, first_entries), 0n, Nat.add(List.length(&2, Reading.ChainEntry, first_entries), List.length(&2, Reading.ChainEntry, second_entries))}

# --- v0.3 parallel fan-out ---
# Alternating split (balanced for ANY key distribution — halves differ by at
# most one element), two independent membership-compares via parallel `let`,
# union by append. Order of added/removed/modified lists is NOT canonical
# across paths (evens-then-odds vs scan order) — COUNTS and SETS agree, order
# doesn't. Downstream merge sorts before hashing, so order never leaks into
# tree hashes. Equivalence fanned==sequential is behavioral (counts), NOT
# proven — general set-equality needs the eq-lemma epic.

def split_step(entries: List<&2, Reading.ChainEntry>, take_head: Bool, evens_accum: List<&2, Reading.ChainEntry>, odds_accum: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry> & List<&2, Reading.ChainEntry>:
  match entries:
    case Nil{}:
      (List.reverse(&2, Reading.ChainEntry, evens_accum), List.reverse(&2, Reading.ChainEntry, odds_accum))
    case Con{head_entry, remaining_entries}:
      match take_head:
        case True{}:
          split_step(remaining_entries, False{}, Con{head_entry, evens_accum}, odds_accum)
        case False{}:
          split_step(remaining_entries, True{}, evens_accum, Con{head_entry, odds_accum})

def split_entries(+source_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry> & List<&2, Reading.ChainEntry>:
  split_step(source_entries, True{}, Nil{}, Nil{})

# (union_compare_results removed: per-half full-compares are semantically
# wrong for membership diffs — see fan_*_entries above.)

def fan_added_halves(even_entries: List<&2, Reading.ChainEntry>, odd_entries: List<&2, Reading.ChainEntry>, +reference_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  even_added odd_added = second_only_entries(reference_entries, even_entries) second_only_entries(reference_entries, odd_entries)
  List.append(&2, LogicalKey.LogicalKey, even_added, odd_added)

def fan_out_pair(split_pair: List<&2, Reading.ChainEntry> & List<&2, Reading.ChainEntry>, +reference_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  match split_pair:
    case (even_entries, odd_entries):
      fan_added_halves(even_entries, odd_entries, reference_entries)

def fan_added_entries(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  fan_out_pair(split_entries(second_entries), first_entries)

def fan_removed_halves(even_entries: List<&2, Reading.ChainEntry>, odd_entries: List<&2, Reading.ChainEntry>, +reference_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  even_removed odd_removed = first_only_entries(reference_entries, even_entries) first_only_entries(reference_entries, odd_entries)
  List.append(&2, LogicalKey.LogicalKey, even_removed, odd_removed)

def fan_out_removed(split_pair: List<&2, Reading.ChainEntry> & List<&2, Reading.ChainEntry>, +reference_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  match split_pair:
    case (even_entries, odd_entries):
      fan_removed_halves(even_entries, odd_entries, reference_entries)

def fan_removed_entries(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  fan_out_removed(split_entries(first_entries), second_entries)

def fan_modified_halves(even_entries: List<&2, Reading.ChainEntry>, odd_entries: List<&2, Reading.ChainEntry>, +reference_entries: List<&2, Reading.ChainEntry>) -> List<&2, ModifiedEntry>:
  even_modified odd_modified = changed_pairs(reference_entries, even_entries) changed_pairs(reference_entries, odd_entries)
  List.append(&2, ModifiedEntry, even_modified, odd_modified)

def fan_out_modified(split_pair: List<&2, Reading.ChainEntry> & List<&2, Reading.ChainEntry>, +reference_entries: List<&2, Reading.ChainEntry>) -> List<&2, ModifiedEntry>:
  match split_pair:
    case (even_entries, odd_entries):
      fan_modified_halves(even_entries, odd_entries, reference_entries)

def fan_modified_entries(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> List<&2, ModifiedEntry>:
  fan_out_modified(split_entries(first_entries), second_entries)

def compare_entries_fanned(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  Make{fan_added_entries(first_entries, second_entries), fan_removed_entries(first_entries, second_entries), fan_modified_entries(first_entries, second_entries), 0n, Nat.add(List.length(&2, Reading.ChainEntry, first_entries), List.length(&2, Reading.ChainEntry, second_entries))}

def comparison_parallel_threshold() -> Nat:
  1024n

def decide_fan_out(is_large: Bool, +first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  match is_large:
    case True{}:
      compare_entries_fanned(first_entries, second_entries)
    case False{}:
      compare_sorted_entries(first_entries, second_entries)

def compare_entries_auto(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  decide_fan_out(Nat.is_ge(List.length(&2, Reading.ChainEntry, first_entries), comparison_parallel_threshold()), first_entries, second_entries)

def entries_or_empty(tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> List<&2, Reading.ChainEntry>:
  match tree_maybe:
    case None{}:
      Nil{}
    case Some{found_tree}:
      StateTree.tree_entries(found_tree)

def hash_or_empty(tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  match tree_maybe:
    case None{}:
      ""
    case Some{found_tree}:
      StateTree.tree_hash_of(found_tree)

def pruned_result(first_entries: List<&2, Reading.ChainEntry>, second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  Make{Nil{}, Nil{}, Nil{}, 1n, Nat.add(List.length(&2, Reading.ChainEntry, first_entries), List.length(&2, Reading.ChainEntry, second_entries))}

def pruned_or_present(second_maybe: Maybe<&2, StateTree.StateTreeNode>, first_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  match second_maybe:
    case None{}:
      compare_entries_auto(first_entries, Nil{})
    case Some{second_tree}:
      pruned_result(first_entries, StateTree.tree_entries(second_tree))

def pruned_or_empty(first_maybe: Maybe<&2, StateTree.StateTreeNode>, second_maybe: Maybe<&2, StateTree.StateTreeNode>) -> CompareResult:
  match first_maybe:
    case None{}:
      compare_entries_auto(Nil{}, entries_or_empty(second_maybe))
    case Some{first_tree}:
      pruned_or_present(second_maybe, StateTree.tree_entries(first_tree))

def dispatch_tree_hashes(hashes_equal: Bool, +first_maybe: Maybe<&2, StateTree.StateTreeNode>, +second_maybe: Maybe<&2, StateTree.StateTreeNode>) -> CompareResult:
  match hashes_equal:
    case True{}:
      pruned_or_empty(first_maybe, second_maybe)
    case False{}:
      compare_entries_auto(entries_or_empty(first_maybe), entries_or_empty(second_maybe))

def compare_loaded_trees(+first_maybe: Maybe<&2, StateTree.StateTreeNode>, +second_maybe: Maybe<&2, StateTree.StateTreeNode>) -> CompareResult:
  dispatch_tree_hashes(String.eq(hash_or_empty(first_maybe), hash_or_empty(second_maybe)), first_maybe, second_maybe)

def compare_commits(+first_identifier: String, +second_identifier: String) -> MyLsmStore.Sess<&2, CompareResult>:
  do MyLsmStore.Sess<&2, CompareResult>:
    first_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(first_identifier)
    second_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(second_identifier)
    return compare_loaded_trees(first_tree_maybe, second_tree_maybe)
