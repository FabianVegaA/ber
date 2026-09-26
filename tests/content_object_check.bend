import Base
import ../src/ContentObject.bend as ContentObject
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore
import 0x0ae7ac793853e753f5f74c16e06ee078/src/Db.bend as DbTypes

def check_payload_text(loaded_object: ContentObject.ContentObject, expected_payload: String) -> Bool:
  match loaded_object:
    case ContentObject.Make{found_hash, found_payload, found_references}:
      String.eq(found_payload, expected_payload)

def check_loaded_payload(loaded_maybe: Maybe<&2, ContentObject.ContentObject>, expected_payload: String) -> Bool:
  match loaded_maybe:
    case None{}:
      False{}
    case Some{loaded_object}:
      check_payload_text(loaded_object, expected_payload)

def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

# One Sess program: all store/load steps sequenced in the monad, db stays inside.
def scenario_texts() -> MyLsmStore.Sess<&2, List<&2, String>>:
  do MyLsmStore.Sess<&2, List<&2, String>>:
    +first_hash : String <- ContentObject.store_content_object("hello", Nil{})
    second_hash : String <- ContentObject.store_content_object("hello", Nil{})
    loaded_maybe : Maybe<&2, ContentObject.ContentObject> <- ContentObject.load_content_object(first_hash)
    missing_maybe : Maybe<&2, ContentObject.ContentObject> <- ContentObject.load_content_object("deadbeefmissing0000000000000000000000000000000000000000000000")
    return Con{flag_text("hash-stable", String.eq(first_hash, second_hash)), Con{flag_text("load-roundtrip", check_loaded_payload(loaded_maybe, "hello")), Con{flag_text("load-missing-none", Bool.not(check_loaded_payload(missing_maybe, "hello"))), Nil{}}}}

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
  opened_store = MyLsmStore.open("content-check")
  print_scenario_result(MyLsmStore.run_sess(&2, List<&2, String>, opened_store, scenario_texts()))
