import Base
import ../src/Staging.bend as Staging
import ../src/History.bend as History
import ../src/Merging.bend as Merging
import ../src/StateTree.bend as StateTree
import ../src/Reading.bend as Reading
import ../src/LogicalKey.bend as LogicalKey
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore
import 0x0ae7ac793853e753f5f74c16e06ee078/src/Db.bend as DbTypes

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

def read_merged_tree(success_maybe: Maybe<&2, History.Commit>) -> MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
  match success_maybe:
    case None{}:
      do MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
        return None{}
    case Some{merged_commit}:
      History.read_tree_at(History.commit_identifier_of(merged_commit))

def merged_count_flag(merged_tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  match merged_tree_maybe:
    case None{}:
      flag_text("merged-count-three", False{})
    case Some{merged_tree}:
      is_count("merged-count-three", count_tree_entries(StateTree.tree_entries(merged_tree)), 3n)

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
    +merge_outcome : Merging.MergeResult <- Merging.merge_commits(first_identifier, second_identifier, "union-disjoint")
    staged_conflict_first : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_base", "version_ex")
    conflict_first : History.Commit <- History.create_commit("session_first", Con{base_identifier, Nil{}}, Nil{})
    +conflict_first_identifier : String = History.commit_identifier_of(conflict_first)
    staged_conflict_second : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_base", "version_wye")
    conflict_second : History.Commit <- History.create_commit("session_first", Con{base_identifier, Nil{}}, Nil{})
    +conflict_second_identifier : String = History.commit_identifier_of(conflict_second)
    +conflict_outcome : Merging.MergeResult <- Merging.merge_commits(conflict_first_identifier, conflict_second_identifier, "union-disjoint")
    merged_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- read_merged_tree(Merging.success_commit_of(merge_outcome))
    return Con{flag_text("merge-succeeds", Merging.merge_succeeded(merge_outcome)), Con{merged_count_flag(merged_tree_maybe), Con{is_count("conflict-keys-one", Merging.conflict_key_count(conflict_outcome), 1n), Con{flag_text("conflict-detected", Bool.not(Merging.merge_succeeded(conflict_outcome))), Nil{}}}}}

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
  opened_store = MyLsmStore.open("merging-check")
  print_scenario_result(MyLsmStore.run_sess(&2, List<&2, String>, opened_store, scenario_texts()))
