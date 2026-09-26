import Base
import ../src/Staging.bend as Staging
import ../src/History.bend as History
import ../src/LogicalKey.bend as LogicalKey
import mylsm-lsm-store@0.3.1.0/mylsm.bend as MyLsmStore
import mylsm-lsm-store@0.3.1.0/src/Db.bend as DbTypes

def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def flag_some_equals(check_name: String, read_maybe: Maybe<&2, String>, expected_text: String) -> String:
  match read_maybe:
    case None{}:
      flag_text(check_name, False{})
    case Some{actual_text}:
      flag_text(check_name, String.eq(actual_text, expected_text))

def flag_is_none(check_name: String, read_maybe: Maybe<&2, String>) -> String:
  match read_maybe:
    case None{}:
      flag_text(check_name, True{})
    case Some{actual_text}:
      flag_text(check_name, False{})

def scenario_texts() -> MyLsmStore.Sess<&2, List<&2, String>>:
  do MyLsmStore.Sess<&2, List<&2, String>>:
    staged_first : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_first", "version_one")
    first_commit : History.Commit <- History.create_commit("session_first", Nil{}, Nil{})
    +first_identifier : String = History.commit_identifier_of(first_commit)
    staged_second : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_first", "version_two")
    second_commit : History.Commit <- History.create_commit("session_first", Con{first_identifier, Nil{}}, Nil{})
    +second_identifier : String = History.commit_identifier_of(second_commit)
    read_first : Maybe<&2, String> <- History.read_value_at("ledger", "record_first", first_identifier)
    read_second : Maybe<&2, String> <- History.read_value_at("ledger", "record_first", second_identifier)
    staged_delete : LogicalKey.LogicalKey <- Staging.delete_record("session_first", "ledger", "record_first")
    third_commit : History.Commit <- History.create_commit("session_first", Con{second_identifier, Nil{}}, Nil{})
    read_third : Maybe<&2, String> <- History.read_value_at("ledger", "record_first", History.commit_identifier_of(third_commit))
    read_first_again : Maybe<&2, String> <- History.read_value_at("ledger", "record_first", first_identifier)
    return Con{flag_some_equals("read-first-version", read_first, "version_one"), Con{flag_some_equals("read-second-version", read_second, "version_two"), Con{flag_is_none("read-after-delete", read_third), Con{flag_some_equals("read-first-stable", read_first_again, "version_one"), Nil{}}}}}

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
  opened_store = MyLsmStore.open("reading-check")
  print_scenario_result(MyLsmStore.run_sess(&2, List<&2, String>, opened_store, scenario_texts()))
