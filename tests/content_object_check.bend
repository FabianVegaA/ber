import Base
import ../ber.bend as Ber
import ../src/Store.bend as Store
import ../src/Value.bend as Value
import ../src/ContentObject.bend as ContentObject

# IO harness: content objects roundtrip by hash; identical payloads dedupe.

def check_payload_text(loaded_object: ContentObject.ContentObject, expected_payload: String) -> Bool:
  match loaded_object:
    case ContentObject.Make{found_hash, found_payload, found_references}:
      match found_payload:
        case Value.Text{content}:
          String.eq(content, expected_payload)
        case _:
          False{}

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

def scenario_texts() -> Store.Op<&2, List<&2, String>>:
  do Store.Op<&2, List<&2, String>>:
    +first_hash : String <- ContentObject.store_content_object(Value.Text{"hello"}, Nil{})
    second_hash : String <- ContentObject.store_content_object(Value.Text{"hello"}, Nil{})
    loaded_maybe : Maybe<&2, ContentObject.ContentObject> <- ContentObject.load_content_object(first_hash)
    missing_maybe : Maybe<&2, ContentObject.ContentObject> <- ContentObject.load_content_object("deadbeefmissing0000000000000000000000000000000000000000000000")
    return Con{flag_text("hash-stable", String.eq(first_hash, second_hash)), Con{flag_text("load-roundtrip", check_loaded_payload(loaded_maybe, "hello")), Con{flag_text("load-missing-none", Bool.not(check_loaded_payload(missing_maybe, "hello"))), Nil{}}}}

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
  opened_store : Store.Handle = Store.open_store("content-check")
  print_scenario_result(Store.run_op(&2, List<&2, String>, opened_store, scenario_texts()))
