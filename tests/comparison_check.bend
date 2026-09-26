import Base
import ../ber.bend as Ber
import ../src/Store.bend as Store
import ../src/Value.bend as Value
import ../src/Comparison.bend as Comparison
import ../src/LogicalKey.bend as LogicalKey

# IO harness: disjoint and identical compares, pruning shortcut, missing
# trees tolerated as empty.


def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

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

def count_added(compare_result: Comparison.CompareResult) -> Nat:
  List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(compare_result))

def count_removed(compare_result: Comparison.CompareResult) -> Nat:
  List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(compare_result))

def count_modified(compare_result: Comparison.CompareResult) -> Nat:
  List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(compare_result))

def scenario_texts() -> Store.Op<&2, List<&2, String>>:
  do Store.Op<&2, List<&2, String>>:
    +base_identifier : String <- Ber.commit_value("session_first", "ledger", "record_base", Value.Text{"base_version"}, Nil{})
    +first_identifier : String <- Ber.commit_value("session_first", "ledger", "record_alpha", Value.Text{"alpha_version"}, Con{base_identifier, Nil{}})
    +second_identifier : String <- Ber.commit_value("session_first", "ledger", "record_beta", Value.Text{"beta_version"}, Con{base_identifier, Nil{}})
    +branch_diff : Comparison.CompareResult <- Ber.compare_commits(first_identifier, second_identifier)
    +self_diff : Comparison.CompareResult <- Ber.compare_commits(first_identifier, first_identifier)
    return Con{is_count("diff-added-one", count_added(branch_diff), 1n), Con{is_count("diff-removed-one", count_removed(branch_diff), 1n), Con{is_count("diff-modified-none", count_modified(branch_diff), 0n), Con{is_count("self-pruned-one", Comparison.pruned_count_of(self_diff), 1n), Con{is_count("self-added-none", count_added(self_diff), 0n), Nil{}}}}}}

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
  opened_store : Store.Handle = Store.open_store("comparison-check")
  print_scenario_result(Store.run_op(&2, List<&2, String>, opened_store, scenario_texts()))
