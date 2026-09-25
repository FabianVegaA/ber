import Base
import ./Reading.bend as Reading
import ./StateTree.bend as StateTree
import ./History.bend as History
import ./Merging.bend as Merging
import 0x8bf6d41adbe0e67e438f6cdc25a6cb6e/mylsm.bend as MyLsmStore

# Independent merge verification. The PURE core re-derives everything from
# entry lists: strategy known, result hash matches recomputed hash, merge
# recomputation yields the same entry SET (order-insensitive, both-directions
# presence — lists are unique-keyed by construction so set equality is exact),
# every recorded law passed AND at least one law recorded (empty evidence
# rejects — a certificate asserting nothing proves nothing).
# The shell loads the four trees NAMED BY THE CERTIFICATE and runs the core —
# a tampered cert names trees whose content contradicts its claims.

def decide_entry_present(key_matches: Bool, +head_value: String, +target_value: String, tail_result: Bool) -> Bool:
  match key_matches:
    case True{}:
      String.eq(head_value, target_value)
    case False{}:
      tail_result

def entry_present_in(+target_key: String, +target_value: String, entries: List<&2, Reading.ChainEntry>) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{+head_entry, remaining_entries}:
      decide_entry_present(String.eq(Reading.entry_key_of(head_entry), target_key), Reading.entry_value_of(head_entry), target_value, entry_present_in(target_key, target_value, remaining_entries))

def decide_all_present(head_present: Bool, tail_result: Bool) -> Bool:
  match head_present:
    case True{}:
      tail_result
    case False{}:
      False{}

def all_present_in(source_entries: List<&2, Reading.ChainEntry>, +target_entries: List<&2, Reading.ChainEntry>) -> Bool:
  match source_entries:
    case Nil{}:
      True{}
    case Con{+head_entry, remaining_entries}:
      decide_all_present(entry_present_in(Reading.entry_key_of(head_entry), Reading.entry_value_of(head_entry), target_entries), all_present_in(remaining_entries, target_entries))

def entries_equal(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> Bool:
  all_present_in(first_entries, second_entries) && all_present_in(second_entries, first_entries)

def decide_law_step(head_passed: Bool, tail_result: Bool) -> Bool:
  match head_passed:
    case True{}:
      tail_result
    case False{}:
      False{}

def all_remaining_pass(remaining_checks: List<&2, Merging.LawCheck>) -> Bool:
  match remaining_checks:
    case Nil{}:
      True{}
    case Con{head_check, tail_checks}:
      decide_law_step(Merging.law_check_passed(head_check), all_remaining_pass(tail_checks))

def verify_laws_step(checked_laws: List<&2, Merging.LawCheck>) -> Bool:
  match checked_laws:
    case Nil{}:
      False{}
    case Con{head_check, remaining_checks}:
      decide_law_step(Merging.law_check_passed(head_check), all_remaining_pass(remaining_checks))

def verify_entries_step(entries_match: Bool, +certificate: Merging.MergeCertificate) -> Bool:
  match entries_match:
    case False{}:
      False{}
    case True{}:
      verify_laws_step(Merging.cert_checked_laws(certificate))

def verify_recompute_step(recomputed_outcome: Merging.MergeOutcome, +merged_entries: List<&2, Reading.ChainEntry>, +certificate: Merging.MergeCertificate) -> Bool:
  match recomputed_outcome:
    case Merging.ConflictingKeys{conflicting_keys}:
      False{}
    case Merging.MergedEntries{recomputed_entries}:
      verify_entries_step(entries_equal(recomputed_entries, merged_entries), certificate)

def verify_hash_step(hash_matches: Bool, +base_entries: List<&2, Reading.ChainEntry>, +first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>, +merged_entries: List<&2, Reading.ChainEntry>, +certificate: Merging.MergeCertificate) -> Bool:
  match hash_matches:
    case False{}:
      False{}
    case True{}:
      verify_recompute_step(Merging.merge_entry_lists(base_entries, first_entries, second_entries), merged_entries, certificate)

def decide_strategy_known(strategy_known: Bool, +base_entries: List<&2, Reading.ChainEntry>, +first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>, +merged_entries: List<&2, Reading.ChainEntry>, +certificate: Merging.MergeCertificate) -> Bool:
  match strategy_known:
    case False{}:
      False{}
    case True{}:
      verify_hash_step(String.eq(Merging.cert_result_tree(certificate), StateTree.compute_tree_hash(merged_entries)), base_entries, first_entries, second_entries, merged_entries, certificate)

def verify_merge_certificate_pure(+base_entries: List<&2, Reading.ChainEntry>, +first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>, +merged_entries: List<&2, Reading.ChainEntry>, +certificate: Merging.MergeCertificate) -> Bool:
  decide_strategy_known(String.eq(Merging.cert_strategy_name(certificate), "union-disjoint"), base_entries, first_entries, second_entries, merged_entries, certificate)

def decide_verify_result(+certificate: Merging.MergeCertificate, base_tree: StateTree.StateTreeNode, first_tree: StateTree.StateTreeNode, second_tree: StateTree.StateTreeNode, result_maybe: Maybe<&2, StateTree.StateTreeNode>) -> Bool:
  match result_maybe:
    case None{}:
      False{}
    case Some{result_tree}:
      verify_merge_certificate_pure(StateTree.tree_entries(base_tree), StateTree.tree_entries(first_tree), StateTree.tree_entries(second_tree), StateTree.tree_entries(result_tree), certificate)

def decide_verify_second(+certificate: Merging.MergeCertificate, base_tree: StateTree.StateTreeNode, first_tree: StateTree.StateTreeNode, second_maybe: Maybe<&2, StateTree.StateTreeNode>, result_maybe: Maybe<&2, StateTree.StateTreeNode>) -> Bool:
  match second_maybe:
    case None{}:
      False{}
    case Some{second_tree}:
      decide_verify_result(certificate, base_tree, first_tree, second_tree, result_maybe)

def decide_verify_first(+certificate: Merging.MergeCertificate, base_tree: StateTree.StateTreeNode, first_maybe: Maybe<&2, StateTree.StateTreeNode>, second_maybe: Maybe<&2, StateTree.StateTreeNode>, result_maybe: Maybe<&2, StateTree.StateTreeNode>) -> Bool:
  match first_maybe:
    case None{}:
      False{}
    case Some{first_tree}:
      decide_verify_second(certificate, base_tree, first_tree, second_maybe, result_maybe)

def decide_verify_trees(+certificate: Merging.MergeCertificate, base_maybe: Maybe<&2, StateTree.StateTreeNode>, first_maybe: Maybe<&2, StateTree.StateTreeNode>, second_maybe: Maybe<&2, StateTree.StateTreeNode>, result_maybe: Maybe<&2, StateTree.StateTreeNode>) -> Bool:
  match base_maybe:
    case None{}:
      False{}
    case Some{base_tree}:
      decide_verify_first(certificate, base_tree, first_maybe, second_maybe, result_maybe)

def verify_certificate(+certificate: Merging.MergeCertificate) -> MyLsmStore.Sess<&2, Bool>:
  do MyLsmStore.Sess<&2, Bool>:
    base_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(Merging.cert_base_commit(certificate))
    first_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(Merging.cert_first_parent(certificate))
    second_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.read_tree_at(Merging.cert_second_parent(certificate))
    result_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- History.load_tree_text(Merging.cert_result_tree(certificate))
    return decide_verify_trees(certificate, base_tree_maybe, first_tree_maybe, second_tree_maybe, result_tree_maybe)
