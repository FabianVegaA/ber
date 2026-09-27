import Base
import ./Reading.bend as Reading
import ./LogicalKey.bend as LogicalKey
import ./StateTree.bend as StateTree
import ./History.bend as History
import ./Store.bend as Store

# Structural tree diff, membership-based (no ordering decisions): added =
# second-only keys, removed = first-only keys, modified = shared keys with
# different value hashes. Zero Cmp matching keeps every branch provable.
# The v0.3 fan-out splits entries alternately and compares halves in
# parallel; counts and sets agree with the sequential path, order does not
# (downstream merge sorts before hashing, so order never leaks into hashes).

# One changed key with its before/after hashes.
type ModifiedEntry is Data:
  Changed{changed_key: LogicalKey.LogicalKey, before_hash: String, after_hash: String}

# Added, removed and modified sets plus prune/compare counts.
type CompareResult is Data:
  Make{added_keys: List<&2, LogicalKey.LogicalKey>, removed_keys: List<&2, LogicalKey.LogicalKey>, modified_entries: List<&2, ModifiedEntry>, pruned_subtree_count: Nat, compared_entry_count: Nat}

# Projects the added keys out of a compare result.
def added_keys_of(compare_result: CompareResult) -> List<&2, LogicalKey.LogicalKey>:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      added_keys

# Projects the removed keys out of a compare result.
def removed_keys_of(compare_result: CompareResult) -> List<&2, LogicalKey.LogicalKey>:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      removed_keys

# Projects the modified entries out of a compare result.
def modified_entries_of(compare_result: CompareResult) -> List<&2, ModifiedEntry>:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      modified_entries

# Projects the pruned-subtree count out of a compare result.
def pruned_count_of(compare_result: CompareResult) -> Nat:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      pruned_subtree_count

# Projects the compared-entry count out of a compare result.
def compared_entry_count_of(compare_result: CompareResult) -> Nat:
  match compare_result:
    case Make{added_keys, removed_keys, modified_entries, pruned_subtree_count, compared_entry_count}:
      compared_entry_count

# Splits an entry key into namespace and record.
def entry_to_logical_key(head_entry: Reading.ChainEntry) -> LogicalKey.LogicalKey:
  LogicalKey.split_combined_key(Reading.entry_key_of(head_entry))

# True short-circuits the membership scan.
def decide_member_found(head_matches: Bool, recursive_result: Bool) -> Bool:
  match head_matches:
    case True{}:
      True{}
    case False{}:
      recursive_result

# Scans entries for the target key.
def key_in_entries(+target_key: String, entries: List<&2, Reading.ChainEntry>) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{head_entry, remaining_entries}:
      decide_member_found(String.eq(Reading.entry_key_of(head_entry), target_key), key_in_entries(target_key, remaining_entries))

# Keeps the entry only when absent from the other side.
def decide_member_keep(is_member: Bool, +head_entry: Reading.ChainEntry, tail_keys: List<&2, LogicalKey.LogicalKey>) -> List<&2, LogicalKey.LogicalKey>:
  match is_member:
    case True{}:
      tail_keys
    case False{}:
      Con{entry_to_logical_key(head_entry), tail_keys}

# Keys of second absent from first: the added set.
def second_only_entries(+first_entries: List<&2, Reading.ChainEntry>, second_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  match second_entries:
    case Nil{}:
      Nil{}
    case Con{+head_entry, remaining_entries}:
      decide_member_keep(key_in_entries(Reading.entry_key_of(head_entry), first_entries), head_entry, second_only_entries(first_entries, remaining_entries))

# Keys of first absent from second: the removed set.
def first_only_entries(+second_entries: List<&2, Reading.ChainEntry>, first_entries: List<&2, Reading.ChainEntry>) -> List<&2, LogicalKey.LogicalKey>:
  match first_entries:
    case Nil{}:
      Nil{}
    case Con{+head_entry, remaining_entries}:
      decide_member_keep(key_in_entries(Reading.entry_key_of(head_entry), second_entries), head_entry, first_only_entries(second_entries, remaining_entries))

# Some on match, otherwise the tail result.
def decide_value_found(head_matches: Bool, head_value: String, tail_result: Maybe<&2, String>) -> Maybe<&2, String>:
  match head_matches:
    case True{}:
      Some{head_value}
    case False{}:
      tail_result

# Finds the value stored under the key.
def value_of_key(+target_key: String, entries: List<&2, Reading.ChainEntry>) -> Maybe<&2, String>:
  match entries:
    case Nil{}:
      None{}
    case Con{+head_entry, remaining_entries}:
      decide_value_found(String.eq(Reading.entry_key_of(head_entry), target_key), Reading.entry_value_of(head_entry), value_of_key(target_key, remaining_entries))

# Records a change only when values differ.
def decide_modified_value(values_equal: Bool, +head_entry: Reading.ChainEntry, +second_value: String, tail_modified: List<&2, ModifiedEntry>) -> List<&2, ModifiedEntry>:
  match values_equal:
    case True{}:
      tail_modified
    case False{}:
      Con{Changed{entry_to_logical_key(head_entry), Reading.entry_value_of(head_entry), second_value}, tail_modified}

# Records a change when the key exists on both sides.
def decide_modified_member(second_value_maybe: Maybe<&2, String>, +head_entry: Reading.ChainEntry, tail_modified: List<&2, ModifiedEntry>) -> List<&2, ModifiedEntry>:
  match second_value_maybe:
    case None{}:
      tail_modified
    case Some{+second_value}:
      decide_modified_value(String.eq(Reading.entry_value_of(head_entry), second_value), head_entry, second_value, tail_modified)

# Shared keys with different values: the modified set.
def changed_pairs(+second_entries: List<&2, Reading.ChainEntry>, first_entries: List<&2, Reading.ChainEntry>) -> List<&2, ModifiedEntry>:
  match first_entries:
    case Nil{}:
      Nil{}
    case Con{+head_entry, remaining_entries}:
      decide_modified_member(value_of_key(Reading.entry_key_of(head_entry), second_entries), head_entry, changed_pairs(second_entries, remaining_entries))

# Membership diff core; counts cover both inputs.
def compare_sorted_entries(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  Make{second_only_entries(first_entries, second_entries), first_only_entries(second_entries, first_entries), changed_pairs(second_entries, first_entries), 0n, Nat.add(List.length(&2, Reading.ChainEntry, first_entries), List.length(&2, Reading.ChainEntry, second_entries))}

# Alternates entries into even/odd accumulators, then reverses.
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

# Splits into balanced halves for any key distribution.
def split_entries(+source_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry> & List<&2, Reading.ChainEntry>:
  split_step(source_entries, True{}, Nil{}, Nil{})

# Copies the spine so each lane scans a private list without atomics.
def decide_linear_value(values_equal: Bool, +first_head: Reading.ChainEntry, +second_head: Reading.ChainEntry, +tail_diff: CompareResult) -> CompareResult:
  match values_equal:
    case True{}:
      Make{added_keys_of(tail_diff), removed_keys_of(tail_diff), modified_entries_of(tail_diff), pruned_count_of(tail_diff), Nat.add(2n, compared_entry_count_of(tail_diff))}
    case False{}:
      Make{added_keys_of(tail_diff), removed_keys_of(tail_diff), Con{Changed{entry_to_logical_key(first_head), Reading.entry_value_of(first_head), Reading.entry_value_of(second_head)}, modified_entries_of(tail_diff)}, pruned_count_of(tail_diff), Nat.add(2n, compared_entry_count_of(tail_diff))}

# Merges one step by key order; both sides kept on ties (stable).
# @unsafe: calls merge_by_key below (branch-dependent recursion needs the
# forward reference); terminates in practice (one side always shrinks).
@unsafe
def merge_order(ordering: Cmp, first_head: Reading.ChainEntry, first_tail: List<&2, Reading.ChainEntry>, second_head: Reading.ChainEntry, second_tail: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match ordering:
    case LT{}:
      Con{first_head, merge_by_key(first_tail, Con{second_head, second_tail})}
    case GT{}:
      Con{second_head, merge_by_key(Con{first_head, first_tail}, second_tail)}
    case EQ{}:
      Con{first_head, Con{second_head, merge_by_key(first_tail, second_tail)}}

# Unpacks the key comparison into the ordering step.
def merge_dispatch(cmp_result: (String & String) & Cmp, first_head: Reading.ChainEntry, first_tail: List<&2, Reading.ChainEntry>, second_head: Reading.ChainEntry, second_tail: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match cmp_result:
    case ((returned_first, returned_second), ordering):
      merge_order(ordering, first_head, first_tail, second_head, second_tail)

# Linear merge of two sorted lists by entry key.
# @unsafe: the greater-side branch recurses on a reconstructed list, which
# the termination checker cannot see through; one side always shrinks.
@unsafe
def merge_by_key(first_sorted: List<&2, Reading.ChainEntry>, second_sorted: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match first_sorted:
    case Nil{}:
      second_sorted
    case Con{+first_head, first_tail}:
      match second_sorted:
        case Nil{}:
          Con{first_head, first_tail}
        case Con{+second_head, second_tail}:
          merge_dispatch(String.cmp(Reading.entry_key_of(first_head), Reading.entry_key_of(second_head)), first_head, first_tail, second_head, second_tail)

# Merges the sorted halves of one split pair.
# @unsafe: calls sort_fuel below (split halves are computed, not structural).
@unsafe
def sort_split_halves(split_pair: List<&2, Reading.ChainEntry> & List<&2, Reading.ChainEntry>, +remaining_fuel: Nat) -> List<&2, Reading.ChainEntry>:
  match split_pair:
    case (even_entries, odd_entries):
      merge_by_key(sort_fuel(remaining_fuel, even_entries), sort_fuel(remaining_fuel, odd_entries))

# Merge sort with Nat fuel; fuel bounds recursion depth, not size.
def sort_fuel(remaining_fuel: Nat, unsorted_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match remaining_fuel:
    case 0n:
      unsorted_entries
    case 1n+fuel_left:
      match unsorted_entries:
        case Nil{}:
          Nil{}
        case Con{single_entry, Nil{}}:
          Con{single_entry, Nil{}}
        case Con{first_entry, Con{second_entry, remaining_entries}}:
          sort_split_halves(split_entries(unsorted_entries), fuel_left)

# Sorts entries by key; fuel starts at the entry count.
def sort_entries_by_key(+unsorted_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  sort_fuel(List.length(&2, Reading.ChainEntry, unsorted_entries), unsorted_entries)

# Decides one linear-diff step by key order.
# @unsafe: calls merge_sorted_diff below (branch-dependent recursion needs
# the forward reference); one side always shrinks.
@unsafe
def decide_linear_order(ordering: Cmp, +first_head: Reading.ChainEntry, first_tail: List<&2, Reading.ChainEntry>, +second_head: Reading.ChainEntry, second_tail: List<&2, Reading.ChainEntry>) -> CompareResult:
  match ordering:
    case LT{}:
      prepend_linear_removed(first_head, merge_sorted_diff(first_tail, Con{second_head, second_tail}))
    case GT{}:
      prepend_linear_added(second_head, merge_sorted_diff(Con{first_head, first_tail}, second_tail))
    case EQ{}:
      decide_linear_value(String.eq(Reading.entry_value_of(first_head), Reading.entry_value_of(second_head)), first_head, second_head, merge_sorted_diff(first_tail, second_tail))

# Prepends a removed key to a computed tail diff; one entry consumed.
def prepend_linear_removed(+head_entry: Reading.ChainEntry, +tail_diff: CompareResult) -> CompareResult:
  Make{added_keys_of(tail_diff), Con{entry_to_logical_key(head_entry), removed_keys_of(tail_diff)}, modified_entries_of(tail_diff), pruned_count_of(tail_diff), Nat.add(1n, compared_entry_count_of(tail_diff))}

# Prepends an added key to a computed tail diff; one entry consumed.
def prepend_linear_added(+head_entry: Reading.ChainEntry, +tail_diff: CompareResult) -> CompareResult:
  Make{Con{entry_to_logical_key(head_entry), added_keys_of(tail_diff)}, removed_keys_of(tail_diff), modified_entries_of(tail_diff), pruned_count_of(tail_diff), Nat.add(1n, compared_entry_count_of(tail_diff))}

# Unpacks the key comparison into the linear-diff step.
def dispatch_linear_diff(cmp_result: (String & String) & Cmp, +first_head: Reading.ChainEntry, first_tail: List<&2, Reading.ChainEntry>, +second_head: Reading.ChainEntry, second_tail: List<&2, Reading.ChainEntry>) -> CompareResult:
  match cmp_result:
    case ((returned_first, returned_second), ordering):
      decide_linear_order(ordering, first_head, first_tail, second_head, second_tail)

# Decides one linear-diff step over sorted heads.
def linear_diff_heads(+first_head: Reading.ChainEntry, first_tail: List<&2, Reading.ChainEntry>, +second_head: Reading.ChainEntry, second_tail: List<&2, Reading.ChainEntry>) -> CompareResult:
  dispatch_linear_diff(String.cmp(Reading.entry_key_of(first_head), Reading.entry_key_of(second_head)), first_head, first_tail, second_head, second_tail)

# Linear diff over two sorted lists; counts cover both inputs.
def merge_sorted_diff(+first_sorted: List<&2, Reading.ChainEntry>, +second_sorted: List<&2, Reading.ChainEntry>) -> CompareResult:
  match first_sorted:
    case Nil{}:
      Make{second_only_entries(Nil{}, second_sorted), Nil{}, Nil{}, 0n, List.length(&2, Reading.ChainEntry, second_sorted)}
    case Con{first_head, first_tail}:
      match second_sorted:
        case Nil{}:
          Make{Nil{}, first_only_entries(Nil{}, Con{first_head, first_tail}), Nil{}, 0n, List.length(&2, Reading.ChainEntry, Con{first_head, first_tail})}
        case Con{second_head, second_tail}:
          linear_diff_heads(first_head, first_tail, second_head, second_tail)

# Sorted-path diff: sorts both lists, then linear-diffs.
def compare_entries_sorted(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  merge_sorted_diff(sort_entries_by_key(first_entries), sort_entries_by_key(second_entries))

# Routes every compare through the sorted path; fastest at all sizes.
def compare_entries_auto(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  compare_entries_sorted(first_entries, second_entries)

# Missing trees read as empty entry lists.
def entries_or_empty(tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> List<&2, Reading.ChainEntry>:
  match tree_maybe:
    case None{}:
      Nil{}
    case Some{found_tree}:
      StateTree.tree_entries(found_tree)

# Missing trees hash as the empty string.
def hash_or_empty(tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  match tree_maybe:
    case None{}:
      ""
    case Some{found_tree}:
      StateTree.tree_hash_of(found_tree)

# Equal hashes yield an empty delta with one prune counted.
def pruned_result(first_entries: List<&2, Reading.ChainEntry>, second_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  Make{Nil{}, Nil{}, Nil{}, 1n, Nat.add(List.length(&2, Reading.ChainEntry, first_entries), List.length(&2, Reading.ChainEntry, second_entries))}

# Missing second tree degrades to a one-sided diff.
def pruned_or_present(second_maybe: Maybe<&2, StateTree.StateTreeNode>, first_entries: List<&2, Reading.ChainEntry>) -> CompareResult:
  match second_maybe:
    case None{}:
      compare_entries_auto(first_entries, Nil{})
    case Some{second_tree}:
      pruned_result(first_entries, StateTree.tree_entries(second_tree))

# Missing first tree degrades to a one-sided diff.
def pruned_or_empty(first_maybe: Maybe<&2, StateTree.StateTreeNode>, second_maybe: Maybe<&2, StateTree.StateTreeNode>) -> CompareResult:
  match first_maybe:
    case None{}:
      compare_entries_auto(Nil{}, entries_or_empty(second_maybe))
    case Some{first_tree}:
      pruned_or_present(second_maybe, StateTree.tree_entries(first_tree))

# Equal hashes prune; different hashes diff.
def dispatch_tree_hashes(hashes_equal: Bool, +first_maybe: Maybe<&2, StateTree.StateTreeNode>, +second_maybe: Maybe<&2, StateTree.StateTreeNode>) -> CompareResult:
  match hashes_equal:
    case True{}:
      pruned_or_empty(first_maybe, second_maybe)
    case False{}:
      compare_entries_auto(entries_or_empty(first_maybe), entries_or_empty(second_maybe))

# Diffs two loaded trees with hash pruning.
def compare_loaded_trees(+first_maybe: Maybe<&2, StateTree.StateTreeNode>, +second_maybe: Maybe<&2, StateTree.StateTreeNode>) -> CompareResult:
  dispatch_tree_hashes(String.eq(hash_or_empty(first_maybe), hash_or_empty(second_maybe)), first_maybe, second_maybe)

# Shell: loads both trees and diffs them.
def compare_commits(+first_identifier: String, +second_identifier: String) -> Store.Op<&2, CompareResult>:
  do Store.Op<&2, CompareResult>:
    first_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(first_identifier)
    second_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(second_identifier)
    return compare_loaded_trees(first_tree_maybe, second_tree_maybe)
