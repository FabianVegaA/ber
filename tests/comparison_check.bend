import Base
import ../src/Staging.bend as Staging
import ../src/History.bend as History
import ../src/Comparison.bend as Comparison
import ../src/LogicalKey.bend as LogicalKey
import mylsm-lsm-store@0.3.1.0/mylsm.bend as MyLsmStore
import mylsm-lsm-store@0.3.1.0/src/Db.bend as DbTypes

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

def scenario_texts() -> MyLsmStore.Sess<&2, List<&2, String>>:
  do MyLsmStore.Sess<&2, List<&2, String>>:
    staged_base : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_base", "base_version")
    base_commit : History.Commit <- History.create_commit("session_first", Nil{}, Nil{})
    +base_identifier : String = History.commit_identifier_of(base_commit)
    staged_branch_first : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_alpha", "alpha_version")
    first_branch : History.Commit <- History.create_commit("session_first", Con{base_identifier, Nil{}}, Nil{})
    +first_identifier : String = History.commit_identifier_of(first_branch)
    staged_branch_second : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_beta", "beta_version")
    second_branch : History.Commit <- History.create_commit("session_first", Con{base_identifier, Nil{}}, Nil{})
    +second_identifier : String = History.commit_identifier_of(second_branch)
    +branch_diff : Comparison.CompareResult <- Comparison.compare_commits(first_identifier, second_identifier)
    +self_diff : Comparison.CompareResult <- Comparison.compare_commits(first_identifier, first_identifier)
    return Con{is_count("diff-added-one", count_added(branch_diff), 1n), Con{is_count("diff-removed-one", count_removed(branch_diff), 1n), Con{is_count("diff-modified-none", count_modified(branch_diff), 0n), Con{is_count("self-pruned-one", Comparison.pruned_count_of(self_diff), 1n), Con{is_count("self-added-none", count_added(self_diff), 0n), Nil{}}}}}}

def join_lines(text_lines: List<&2, String>) -> String:
  match text_lines:
    case Nil{}:
      ""
    case Con{head_text, remaining_texts}:
      head_text ++ "\n" ++ join_lines(remaining_texts)

def print_scenario_result(result_pair: DbTypes.Db & List<&2, String>) -> IO(Unit):
  match result_pair:
    case (unused_store, text_lines):
      IO.print(join_lines(text_lines))

def main() -> IO(Unit):
  opened_store = MyLsmStore.open("comparison-check")
  print_scenario_result(MyLsmStore.run_sess(&2, List<&2, String>, opened_store, scenario_texts()))
