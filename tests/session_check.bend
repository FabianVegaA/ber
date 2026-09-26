import Base
import ../src/Store.bend as Store

# Session check: the Op newtype writes, reads, misses and deletes through a
# real store. Verdict lines below must all print PASS.

def some_matches(read_result: Maybe<&2, String>, +expected_text: String) -> Bool:
  match read_result:
    case None{}:
      False{}
    case Some{+found_text}:
      String.eq(found_text, expected_text)

def none_matches(read_result: Maybe<&2, String>) -> Bool:
  match read_result:
    case None{}:
      True{}
    case Some{+unexpected_text}:
      False{}

def flag_line(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def report_all(read_back: Maybe<&2, String>, missing_back: Maybe<&2, String>, deleted_back: Maybe<&2, String>) -> String:
  flag_line("write-read", some_matches(read_back, "session-check-val")) ++ "\n" ++ flag_line("missing-none", none_matches(missing_back)) ++ "\n" ++ flag_line("deleted-none", none_matches(deleted_back))

def scenario() -> Store.Op<&2, String>:
  do Store.Op<&2, String>:
    stored_unit : Unit <- Store.oput("session-check/key", "session-check-val")
    read_back : Maybe<&2, String> <- Store.oget("session-check/key")
    missing_back : Maybe<&2, String> <- Store.oget("session-check/absent")
    staged_unit : Unit <- Store.oput("session-check/gone", "x")
    removed_unit : Unit <- Store.odel("session-check/gone")
    deleted_back : Maybe<&2, String> <- Store.oget("session-check/gone")
    return report_all(read_back, missing_back, deleted_back)

def print_report(run_pair: Store.Handle & String) -> IO(Unit):
  match run_pair:
    case (unused_store, report_text):
      IO.print(report_text)

def main() -> IO(Unit):
  opened_store : Store.Handle = Store.open_store("session-check")
  print_report(Store.run_op(&2, String, opened_store, scenario()))
