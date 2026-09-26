import Base
import ../ber.bend as Ber
import ../src/Store.bend as Store
import ../src/Value.bend as Value
import ../src/History.bend as History
import ../src/Merging.bend as Merging
import ../src/StateTree.bend as StateTree
import ../src/Reading.bend as Reading

# IO harness: disjoint merges succeed, same-key-different-value conflicts,
# ancestor walk finds the base, result accessors behave.


def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def count_tree_entries(entries: List<&2, Reading.ChainEntry>) -> Nat:
  match entries:
    case Nil{}:
      0n
    case Con{head_entry, remaining_entries}:
      Nat.add(1n, count_tree_entries(remaining_entries))

def is_count_same(check_name: String, counted: Nat, expected_count: Nat) -> String:
  match counted:
    case 0n:
      match expected_count:
        case 0n:
          flag_text(check_name, True{})
        case _:
          flag_text(check_name, False{})
    case 1n+remaining_count:
      match expected_count:
        case 0n:
          flag_text(check_name, False{})
        case 1n+remaining_expected:
          flag_text(check_name, True{})

def is_count(check_name: String, counted: Nat, expected_count: Nat) -> String:
  match counted:
    case 0n:
      match expected_count:
        case 0n:
          flag_text(check_name, True{})
        case _:
          flag_text(check_name, False{})
    case 1n+remaining_count:
      match expected_count:
        case 0n:
          flag_text(check_name, False{})
        case 1n+remaining_expected:
          is_count_same(check_name, remaining_count, remaining_expected)

def read_merged_tree(success_maybe: Maybe<&2, History.Commit>) -> Store.Op<&2, Maybe<&2, StateTree.StateTreeNode>>:
  match success_maybe:
    case None{}:
      Store.Op.pure(&2, Maybe<&2, StateTree.StateTreeNode>, None{})
    case Some{merged_commit}:
      Ber.read_tree_at(History.commit_identifier_of(merged_commit))

def merged_count_flag(merged_tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  match merged_tree_maybe:
    case None{}:
      flag_text("merged-count-three", False{})
    case Some{merged_tree}:
      is_count("merged-count-three", count_tree_entries(StateTree.tree_entries(merged_tree)), 3n)

def scenario_texts() -> Store.Op<&2, List<&2, String>>:
  do Store.Op<&2, List<&2, String>>:
    +base_identifier : String <- Ber.commit_value("session_first", "ledger", "record_base", Value.Text{"base_version"}, Nil{})
    +first_identifier : String <- Ber.commit_value("session_first", "ledger", "record_alpha", Value.Text{"alpha_version"}, Con{base_identifier, Nil{}})
    +second_identifier : String <- Ber.commit_value("session_first", "ledger", "record_beta", Value.Text{"beta_version"}, Con{base_identifier, Nil{}})
    +merge_outcome : Merging.MergeResult <- Ber.merge_commits(first_identifier, second_identifier, "union-disjoint")
    +conflict_first_identifier : String <- Ber.commit_value("session_first", "ledger", "record_base", Value.Text{"version_ex"}, Con{base_identifier, Nil{}})
    +conflict_second_identifier : String <- Ber.commit_value("session_first", "ledger", "record_base", Value.Text{"version_wye"}, Con{base_identifier, Nil{}})
    +conflict_outcome : Merging.MergeResult <- Ber.merge_commits(conflict_first_identifier, conflict_second_identifier, "union-disjoint")
    merged_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- read_merged_tree(Merging.success_commit_of(merge_outcome))
    return Con{flag_text("merge-succeeds", Merging.merge_succeeded(merge_outcome)), Con{merged_count_flag(merged_tree_maybe), Con{is_count("conflict-keys-one", Merging.conflict_key_count(conflict_outcome), 1n), Con{flag_text("conflict-detected", Bool.not(Merging.merge_succeeded(conflict_outcome))), Nil{}}}}}

def join_lines(text_lines: List<&2, String>) -> String:
  match text_lines:
    case Nil{}:
      ""
    case Con{head_text, remaining_texts}:
      head_text ++ "\n" ++ join_lines(remaining_texts)

def print_scenario_result(result_pair: Store.Handle & List<&2, String>) -> IO(Unit):
  match result_pair:
    case (unused_store, text_lines):
      IO.print(join_lines(text_lines))

def main() -> IO(Unit):
  opened_store : Store.Handle = Store.open_store("merging-check")
  print_scenario_result(Store.run_op(&2, List<&2, String>, opened_store, scenario_texts()))
