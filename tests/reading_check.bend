import Base
import ../ber.bend as Ber
import ../src/Store.bend as Store
import ../src/Value.bend as Value

# IO harness: versioned reads across put/commit/delete cycles on a real
# MyLSM store; laws cover the pure cores, this covers the wiring.

def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def text_is_expected(found_maybe: Maybe<&2, Value.Value>, expected_text: String) -> Bool:
  match found_maybe:
    case None{}:
      False{}
    case Some{Value.Text{content}}:
      String.eq(content, expected_text)
    case _:
      False{}

def flag_some_equals(check_name: String, read_maybe: Maybe<&2, Value.Value>, expected_text: String) -> String:
  flag_text(check_name, text_is_expected(read_maybe, expected_text))

def flag_is_none(check_name: String, read_maybe: Maybe<&2, Value.Value>) -> String:
  match read_maybe:
    case None{}:
      flag_text(check_name, True{})
    case Some{unexpected_value}:
      flag_text(check_name, False{})

def scenario_texts() -> Store.Op<&2, List<&2, String>>:
  do Store.Op<&2, List<&2, String>>:
    +first_identifier : String <- Ber.commit_value("session_first", "ledger", "record_first", Value.Text{"version_one"}, Nil{})
    +second_identifier : String <- Ber.commit_value("session_first", "ledger", "record_first", Value.Text{"version_two"}, Con{first_identifier, Nil{}})
    read_first : Maybe<&2, Value.Value> <- Ber.read_value_at("ledger", "record_first", first_identifier)
    read_second : Maybe<&2, Value.Value> <- Ber.read_value_at("ledger", "record_first", second_identifier)
    +third_identifier : String <- Ber.remove_record("session_first", "ledger", "record_first", Con{second_identifier, Nil{}})
    read_third : Maybe<&2, Value.Value> <- Ber.read_value_at("ledger", "record_first", third_identifier)
    read_first_again : Maybe<&2, Value.Value> <- Ber.read_value_at("ledger", "record_first", first_identifier)
    return Con{flag_some_equals("read-first-version", read_first, "version_one"), Con{flag_some_equals("read-second-version", read_second, "version_two"), Con{flag_is_none("read-after-delete", read_third), Con{flag_some_equals("read-first-stable", read_first_again, "version_one"), Nil{}}}}}

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
  opened_store : Store.Handle = Store.open_store("reading-check")
  print_scenario_result(Store.run_op(&2, List<&2, String>, opened_store, scenario_texts()))
