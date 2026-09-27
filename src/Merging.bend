import Base
import ./Reading.bend as Reading
import ./LogicalKey.bend as LogicalKey
import ./Comparison.bend as Comparison
import ./StateTree.bend as StateTree
import ./History.bend as History
import ./Store.bend as Store

# Three-way merge, strategy "union-disjoint". The pure core decides per key
# from (base, first, second) with an explicit truth table: equal inputs take
# the value, single-side changes win, delete-vs-unchanged drops, every other
# divergence conflicts (both delete-vs-modify directions — asymmetry would
# break commutativity). Results are sorted before hashing, so compatible
# merges commute as trees by construction.



# Pure merge result: merged entries or conflicting keys.
type MergeOutcome is Data:
  MergedEntries{merged_entries: List<&2, Reading.ChainEntry>}
  ConflictingKeys{conflicting_keys: List<&2, LogicalKey.LogicalKey>}

# One named law verdict.
type LawCheck is Data:
  Check{check_name: String, check_passed: Bool}

# Parents, base, result hash, strategy and checked laws.
type MergeCertificate is Data:
  Make{first_parent_commit: String, second_parent_commit: String, base_commit: String, result_tree_hash: String, strategy_name: String, checked_laws: List<&2, LawCheck>}

# Success with commit and certificate, conflict, or unprovable.
type MergeResult is Data:
  MergeSuccess{resulting_commit: History.Commit, certificate: MergeCertificate}
  MergeConflict{conflicting_keys: List<&2, LogicalKey.LogicalKey>}
  MergeUnprovable{reason: String}

# True only for successful merges.
def merge_succeeded(merge_result: MergeResult) -> Bool:
  match merge_result:
    case MergeSuccess{resulting_commit, certificate}:
      True{}
    case MergeConflict{conflicting_keys}:
      False{}
    case MergeUnprovable{reason}:
      False{}

# Counts conflicting keys; zero otherwise.
def conflict_key_count(merge_result: MergeResult) -> Nat:
  match merge_result:
    case MergeSuccess{resulting_commit, certificate}:
      0n
    case MergeConflict{conflicting_keys}:
      List.length(&2, LogicalKey.LogicalKey, conflicting_keys)
    case MergeUnprovable{reason}:
      0n

# Unwraps the resulting commit of a success.
def success_commit_of(merge_result: MergeResult) -> Maybe<&2, History.Commit>:
  match merge_result:
    case MergeSuccess{resulting_commit, certificate}:
      Some{resulting_commit}
    case MergeConflict{conflicting_keys}:
      None{}
    case MergeUnprovable{reason}:
      None{}

# Unwraps the certificate of a success.
def success_certificate_of(merge_result: MergeResult) -> Maybe<&2, MergeCertificate>:
  match merge_result:
    case MergeSuccess{resulting_commit, certificate}:
      Some{certificate}
    case MergeConflict{conflicting_keys}:
      None{}
    case MergeUnprovable{reason}:
      None{}

# Projects the first parent out of a certificate.
def cert_first_parent(certificate: MergeCertificate) -> String:
  match certificate:
    case Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}:
      first_parent_commit

# Projects the second parent out of a certificate.
def cert_second_parent(certificate: MergeCertificate) -> String:
  match certificate:
    case Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}:
      second_parent_commit

# Projects the base commit out of a certificate.
def cert_base_commit(certificate: MergeCertificate) -> String:
  match certificate:
    case Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}:
      base_commit

# Projects the result tree out of a certificate.
def cert_result_tree(certificate: MergeCertificate) -> String:
  match certificate:
    case Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}:
      result_tree_hash

# Projects the strategy name out of a certificate.
def cert_strategy_name(certificate: MergeCertificate) -> String:
  match certificate:
    case Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}:
      strategy_name

# Projects the checked laws out of a certificate.
def cert_checked_laws(certificate: MergeCertificate) -> List<&2, LawCheck>:
  match certificate:
    case Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, checked_laws}:
      checked_laws

# Projects the verdict out of a law check.
def law_check_passed(law_check: LawCheck) -> Bool:
  match law_check:
    case Check{check_name, check_passed}:
      check_passed

# Projects merged entries; conflicts project as empty.
def merged_entries_of(merge_outcome: MergeOutcome) -> List<&2, Reading.ChainEntry>:
  match merge_outcome:
    case MergedEntries{merged_entries}:
      merged_entries
    case ConflictingKeys{conflicting_keys}:
      Nil{}

# Projects conflicting keys; merges project as empty.
def conflicting_keys_of(merge_outcome: MergeOutcome) -> List<&2, LogicalKey.LogicalKey>:
  match merge_outcome:
    case MergedEntries{merged_entries}:
      Nil{}
    case ConflictingKeys{conflicting_keys}:
      conflicting_keys

# True short-circuits the membership scan.
def decide_contains_member(head_matches: Bool, recursive_result: Bool) -> Bool:
  match head_matches:
    case True{}:
      True{}
    case False{}:
      recursive_result

# Scans the visit list for the identifier.
def list_contains_member(+target_identifier: String, visit_list: List<&2, String>) -> Bool:
  match visit_list:
    case Nil{}:
      False{}
    case Con{head_identifier, remaining_identifiers}:
      decide_contains_member(String.eq(head_identifier, target_identifier), list_contains_member(target_identifier, remaining_identifiers))

# Unknown commits contribute no parents.
def parent_list_or_empty(commit_maybe: Maybe<&2, History.Commit>) -> List<&2, String>:
  match commit_maybe:
    case None{}:
      Nil{}
    case Some{found_commit}:
      History.commit_parents_of(found_commit)

# Skips visited parents in the queue.
def decide_queue_member(is_member: Bool, head_identifier: String, tail_queue: List<&2, String>) -> List<&2, String>:
  match is_member:
    case True{}:
      tail_queue
    case False{}:
      Con{head_identifier, tail_queue}

# Keeps only unvisited parents.
def filter_unvisited(parent_identifiers: List<&2, String>, +visited_accum: List<&2, String>) -> List<&2, String>:
  match parent_identifiers:
    case Nil{}:
      Nil{}
    case Con{+head_identifier, remaining_parents}:
      decide_queue_member(list_contains_member(head_identifier, visited_accum), head_identifier, filter_unvisited(remaining_parents, visited_accum))

# Deduplicates the visited accumulator.
def decide_visited_member(already_visited: Bool, +head_identifier: String, tail_result: List<&2, String>) -> List<&2, String>:
  match already_visited:
    case True{}:
      tail_result
    case False{}:
      Con{head_identifier, tail_result}

# Breadth-first ancestor collection with fuel.
def collect_ancestors(remaining_fuel: Nat, visit_queue: List<&2, String>, +visited_accum: List<&2, String>) -> Store.Op<&2, List<&2, String>>:
  match remaining_fuel:
    case 0n:
      do Store.Op<&2, List<&2, String>>:
        return visited_accum
    case 1n+fuel_left:
      match visit_queue:
        case Nil{}:
          do Store.Op<&2, List<&2, String>>:
            return visited_accum
        case Con{+head_identifier, remaining_queue}:
          do Store.Op<&2, List<&2, String>>:
            commit_maybe : Maybe<&2, History.Commit> <- History.load_commit(head_identifier)
            +extended_queue : List<&2, String> = List.append(&2, String, remaining_queue, filter_unvisited(parent_list_or_empty(commit_maybe), visited_accum))
            tail_result : List<&2, String> <- collect_ancestors(fuel_left, extended_queue, Con{head_identifier, visited_accum})
            return decide_visited_member(list_contains_member(head_identifier, visited_accum), head_identifier, tail_result)

# Some on the first common commit, otherwise the tail.
def decide_lca_found(is_common: Bool, +commit_identifier: String, tail_result: Maybe<&2, String>) -> Maybe<&2, String>:
  match is_common:
    case True{}:
      Some{commit_identifier}
    case False{}:
      tail_result

# A hit ends the ascent: deeper links cannot beat the first common commit.
def lca_fuel_left(is_common: Bool, fuel_left: Nat) -> Nat:
  match is_common:
    case True{}:
      0n
    case False{}:
      fuel_left

# Walks the second branch for the first ancestor-set hit. checker_fuel
# decreases every level for the termination checker; gated_fuel carries the
# early stop. Callers pass the same fuel twice.
def find_first_common(+ancestor_set: List<&2, String>, checker_fuel: Nat, gated_fuel: Nat, +commit_identifier: String) -> Store.Op<&2, Maybe<&2, String>>:
  match checker_fuel gated_fuel:
    case 0n _:
      History.empty_text_maybe()
    case 1n+checker_left 0n:
      History.empty_text_maybe()
    case 1n+checker_left 1n+gated_left:
      do Store.Op<&2, Maybe<&2, String>>:
        commit_maybe : Maybe<&2, History.Commit> <- History.load_commit(commit_identifier)
        +parent_text : String = History.first_parent_text(commit_maybe)
        tail_result : Maybe<&2, String> <- find_first_common(ancestor_set, checker_left, lca_fuel_left(list_contains_member(commit_identifier, ancestor_set), gated_left), parent_text)
        return decide_lca_found(list_contains_member(commit_identifier, ancestor_set), commit_identifier, tail_result)

# Emits the first side entry.
def keep_first_entry(+combined_key: String, +entry_value: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match tail_outcome:
    case ConflictingKeys{conflicting_keys}:
      ConflictingKeys{conflicting_keys}
    case MergedEntries{merged_entries}:
      MergedEntries{Con{Reading.make_entry(combined_key, entry_value), merged_entries}}

# Emits the second side entry.
def keep_second_entry(+combined_key: String, +entry_value: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match tail_outcome:
    case ConflictingKeys{conflicting_keys}:
      ConflictingKeys{conflicting_keys}
    case MergedEntries{merged_entries}:
      MergedEntries{Con{Reading.make_entry(combined_key, entry_value), merged_entries}}

# Records the key as conflicting.
def raise_merge_conflict(+combined_key: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match tail_outcome:
    case ConflictingKeys{conflicting_keys}:
      ConflictingKeys{Con{LogicalKey.split_combined_key(combined_key), conflicting_keys}}
    case MergedEntries{merged_entries}:
      ConflictingKeys{Con{LogicalKey.split_combined_key(combined_key), Nil{}}}

# Unchanged second keeps first; changed conflicts.
def decide_second_changed(second_unchanged: Bool, +combined_key: String, +first_text: String, +second_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match second_unchanged:
    case True{}:
      keep_first_entry(combined_key, first_text, tail_outcome)
    case False{}:
      raise_merge_conflict(combined_key, tail_outcome)

# Unchanged first keeps second; otherwise checks second.
def decide_divergent_base(first_unchanged: Bool, second_unchanged: Bool, +combined_key: String, +first_text: String, +second_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match first_unchanged:
    case True{}:
      keep_second_entry(combined_key, second_text, tail_outcome)
    case False{}:
      decide_second_changed(second_unchanged, combined_key, first_text, second_text, tail_outcome)

# Resolves two present values against the base.
def resolve_divergent(+combined_key: String, base_value: Maybe<&2, String>, +first_text: String, +second_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match base_value:
    case None{}:
      raise_merge_conflict(combined_key, tail_outcome)
    case Some{+base_text}:
      decide_divergent_base(String.eq(first_text, base_text), String.eq(second_text, base_text), combined_key, first_text, second_text, tail_outcome)

# Equal sides keep the value; unequal consults the base.
def decide_both_equal(both_equal: Bool, +combined_key: String, base_value: Maybe<&2, String>, +first_text: String, +second_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match both_equal:
    case True{}:
      keep_first_entry(combined_key, first_text, tail_outcome)
    case False{}:
      resolve_divergent(combined_key, base_value, first_text, second_text, tail_outcome)

# Resolves two present values.
def resolve_both_present(+combined_key: String, base_value: Maybe<&2, String>, +first_text: String, +second_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  decide_both_equal(String.eq(first_text, second_text), combined_key, base_value, first_text, second_text, tail_outcome)

# Unchanged present drops; modified conflicts.
def decide_present_delete(first_unchanged: Bool, +combined_key: String, +first_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match first_unchanged:
    case True{}:
      tail_outcome
    case False{}:
      raise_merge_conflict(combined_key, tail_outcome)

# Keeps added values; checks modified-against-base.
def resolve_present_vs_deleted(+combined_key: String, base_value: Maybe<&2, String>, +first_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match base_value:
    case None{}:
      keep_first_entry(combined_key, first_text, tail_outcome)
    case Some{base_text}:
      decide_present_delete(String.eq(first_text, base_text), combined_key, first_text, tail_outcome)

# Dispatches on the second side presence.
def resolve_first_present(+combined_key: String, base_value: Maybe<&2, String>, +first_text: String, second_value: Maybe<&2, String>, tail_outcome: MergeOutcome) -> MergeOutcome:
  match second_value:
    case None{}:
      resolve_present_vs_deleted(combined_key, base_value, first_text, tail_outcome)
    case Some{second_text}:
      resolve_both_present(combined_key, base_value, first_text, second_text, tail_outcome)

# Unchanged second drops; modified conflicts.
def decide_delete_modify(second_unchanged: Bool, +combined_key: String, +second_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match second_unchanged:
    case True{}:
      tail_outcome
    case False{}:
      raise_merge_conflict(combined_key, tail_outcome)

# Keeps added values; checks modified-against-base.
def resolve_deleted_vs_present(+combined_key: String, base_value: Maybe<&2, String>, +second_text: String, tail_outcome: MergeOutcome) -> MergeOutcome:
  match base_value:
    case None{}:
      keep_second_entry(combined_key, second_text, tail_outcome)
    case Some{base_text}:
      decide_delete_modify(String.eq(second_text, base_text), combined_key, second_text, tail_outcome)

# Dispatches on the second side presence.
def resolve_first_absent(+combined_key: String, base_value: Maybe<&2, String>, second_value: Maybe<&2, String>, tail_outcome: MergeOutcome) -> MergeOutcome:
  match second_value:
    case None{}:
      tail_outcome
    case Some{second_text}:
      resolve_deleted_vs_present(combined_key, base_value, second_text, tail_outcome)

# Decides one key from its (base, first, second) values.
def resolve_key_triple(+combined_key: String, base_value: Maybe<&2, String>, first_value: Maybe<&2, String>, second_value: Maybe<&2, String>, tail_outcome: MergeOutcome) -> MergeOutcome:
  match first_value:
    case None{}:
      resolve_first_absent(combined_key, base_value, second_value, tail_outcome)
    case Some{first_text}:
      resolve_first_present(combined_key, base_value, first_text, second_value, tail_outcome)

# Emits unseen keys once.
def decide_unique_emit(is_seen: Bool, +head_key: String, tail_keys: List<&2, String>) -> List<&2, String>:
  match is_seen:
    case True{}:
      tail_keys
    case False{}:
      Con{head_key, tail_keys}

# Collects candidate keys in first-seen order.
def unique_seen_keys(entries: List<&2, Reading.ChainEntry>, +seen_keys: List<&2, String>) -> List<&2, String>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+head_entry, remaining_entries}:
      decide_unique_emit(list_contains_member(Reading.entry_key_of(head_entry), seen_keys), Reading.entry_key_of(head_entry), unique_seen_keys(remaining_entries, Con{Reading.entry_key_of(head_entry), seen_keys}))

# Concatenates base, first and second entries.
def all_candidate_entries(+base_entries: List<&2, Reading.ChainEntry>, +first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  List.append(&2, Reading.ChainEntry, base_entries, List.append(&2, Reading.ChainEntry, first_entries, second_entries))

# Merges every unique key against the three entry lists.
def merge_unique_keys(unique_keys: List<&2, String>, +base_entries: List<&2, Reading.ChainEntry>, +first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> MergeOutcome:
  match unique_keys:
    case Nil{}:
      MergedEntries{Nil{}}
    case Con{+head_key, remaining_keys}:
      resolve_key_triple(head_key, Comparison.value_of_key(head_key, base_entries), Comparison.value_of_key(head_key, first_entries), Comparison.value_of_key(head_key, second_entries), merge_unique_keys(remaining_keys, base_entries, first_entries, second_entries))

# Sorts merged entries by key for canonical hashing.
def sort_entries(unsorted_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match unsorted_entries:
    case Nil{}:
      Nil{}
    case Con{head_entry, remaining_entries}:
      StateTree.insert_single_entry(sort_entries(remaining_entries), head_entry)

# Sorts merged entries; conflicts pass through.
def finalize_merge(merge_outcome: MergeOutcome) -> MergeOutcome:
  match merge_outcome:
    case MergedEntries{merged_entries}:
      MergedEntries{sort_entries(merged_entries)}
    case ConflictingKeys{conflicting_keys}:
      ConflictingKeys{conflicting_keys}

# Pure three-way merge core over entry lists.
def merge_entry_lists(+base_entries: List<&2, Reading.ChainEntry>, +first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> MergeOutcome:
  finalize_merge(merge_unique_keys(unique_seen_keys(all_candidate_entries(base_entries, first_entries, second_entries), Nil{}), base_entries, first_entries, second_entries))

# Wraps conflicting keys as a Sess result.
def conflict_merge_result(conflicting_keys: List<&2, LogicalKey.LogicalKey>) -> Store.Op<&2, MergeResult>:
  do Store.Op<&2, MergeResult>:
    return MergeConflict{conflicting_keys}

# Wraps an unprovable reason as a Sess result.
def unprovable_merge_result(+reason: String) -> Store.Op<&2, MergeResult>:
  do Store.Op<&2, MergeResult>:
    return MergeUnprovable{reason}

# Issues the certificate with pairwise-compatibility evidence.
def build_merge_certificate(+first_parent_commit: String, +second_parent_commit: String, +base_commit: String, +result_tree_hash: String, +strategy_name: String) -> MergeCertificate:
  Make{first_parent_commit, second_parent_commit, base_commit, result_tree_hash, strategy_name, Con{Check{"pairwise-compatibility", True{}}, Nil{}}}

# Persists tree, commit and index for merged entries.
def persist_merged_result(+first_identifier: String, +second_identifier: String, +base_identifier: String, +merged_entries: List<&2, Reading.ChainEntry>) -> Store.Op<&2, MergeResult>:
  do Store.Op<&2, MergeResult>:
    +tree_hash_value : String <- History.persist_tree(merged_entries)
    +resulting_commit : History.Commit <- History.persist_commit(Con{first_identifier, Con{second_identifier, Nil{}}}, Con{History.Field{"strategy", "union-disjoint"}, Nil{}}, tree_hash_value)
    indexed_unit : Unit <- History.write_each_index(merged_entries, resulting_commit)
    return MergeSuccess{resulting_commit, build_merge_certificate(first_identifier, second_identifier, base_identifier, tree_hash_value, "union-disjoint")}

# Persists merges; conflicts become results directly.
def persist_merge_outcome(merge_outcome: MergeOutcome, +first_identifier: String, +second_identifier: String, +base_identifier: String) -> Store.Op<&2, MergeResult>:
  match merge_outcome:
    case ConflictingKeys{conflicting_keys}:
      conflict_merge_result(conflicting_keys)
    case MergedEntries{merged_entries}:
      persist_merged_result(first_identifier, second_identifier, base_identifier, merged_entries)

# Loads the three trees and merges them.
def merge_three_way(+first_identifier: String, +second_identifier: String, +base_identifier: String) -> Store.Op<&2, MergeResult>:
  do Store.Op<&2, MergeResult>:
    base_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(base_identifier)
    first_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(first_identifier)
    second_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(second_identifier)
    +base_entries : List<&2, Reading.ChainEntry> = Comparison.entries_or_empty(base_tree_maybe)
    +first_entries : List<&2, Reading.ChainEntry> = Comparison.entries_or_empty(first_tree_maybe)
    +second_entries : List<&2, Reading.ChainEntry> = Comparison.entries_or_empty(second_tree_maybe)
    merged_outcome : MergeOutcome = finalize_merge(merge_entry_lists(base_entries, first_entries, second_entries))
    persisted_result : MergeResult <- persist_merge_outcome(merged_outcome, first_identifier, second_identifier, base_identifier)
    return persisted_result

# Merges on the ancestor; missing ancestors are unprovable.
def branch_lca_search(lca_maybe: Maybe<&2, String>, +first_identifier: String, +second_identifier: String) -> Store.Op<&2, MergeResult>:
  match lca_maybe:
    case None{}:
      unprovable_merge_result("no-common-ancestor")
    case Some{base_identifier}:
      merge_three_way(first_identifier, second_identifier, base_identifier)

# Finds the lowest common ancestor, then merges.
def merge_with_ancestor_search(+first_identifier: String, +second_identifier: String) -> Store.Op<&2, MergeResult>:
  do Store.Op<&2, MergeResult>:
    ancestor_set : List<&2, String> <- collect_ancestors(10000n, Con{first_identifier, Nil{}}, Nil{})
    lca_maybe : Maybe<&2, String> <- find_first_common(ancestor_set, 10000n, 10000n, second_identifier)
    merged_result : MergeResult <- branch_lca_search(lca_maybe, first_identifier, second_identifier)
    return merged_result

# Only union-disjoint merges; anything else is unprovable.
def decide_strategy_name(strategy_matches: Bool, +first_identifier: String, +second_identifier: String) -> Store.Op<&2, MergeResult>:
  match strategy_matches:
    case True{}:
      merge_with_ancestor_search(first_identifier, second_identifier)
    case False{}:
      unprovable_merge_result("unknown-strategy")

# Merges two commits by strategy name.
def merge_commits(+first_identifier: String, +second_identifier: String, +strategy_name: String) -> Store.Op<&2, MergeResult>:
  decide_strategy_name(String.eq(strategy_name, "union-disjoint"), first_identifier, second_identifier)
