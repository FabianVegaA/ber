import Base
import ../src/JsonAdapter.bend as JsonAdapter
import bend-kit-json@0.3.0.0/json.bend as Json

# IO harness: adapter encode/parse/get roundtrips and canonical bytes.


def sample_ref_list() -> List<&2, Json.Val>:
  Con{JsonAdapter.make_str("ref_a"), Nil{}}

def sample_fields() -> List<&2, Sigma<&2, &2, String, _ => Json.Val>>:
  Con{JsonAdapter.make_kv("payload", JsonAdapter.make_str("hello")), Con{JsonAdapter.make_kv("references", JsonAdapter.make_arr(sample_ref_list())), Nil{}}}

def sample_text() -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(sample_fields()))

def check_canonical_bytes() -> Bool:
  String.eq(sample_text(), "{\"payload\":\"hello\",\"references\":[\"ref_a\"]}")

def str_maybe_matches(found_maybe: Maybe<&2, String>, +expected_text: String) -> Bool:
  match found_maybe:
    case None{}:
      False{}
    case Some{+found_text}:
      String.eq(found_text, expected_text)

def payload_val_ok(payload_val: Json.Val) -> Bool:
  str_maybe_matches(JsonAdapter.as_str(payload_val), "hello")

def payload_field_ok(payload_maybe: Maybe<&2, Json.Val>) -> Bool:
  match payload_maybe:
    case None{}:
      False{}
    case Some{payload_val}:
      payload_val_ok(payload_val)

def parsed_doc_has_payload(parse_result: Maybe<&2, Json.Val>) -> Bool:
  match parse_result:
    case None{}:
      False{}
    case Some{parsed_doc}:
      payload_field_ok(JsonAdapter.get_field(parsed_doc, "payload"))

def check_roundtrip_payload() -> Bool:
  parsed_doc_has_payload(JsonAdapter.parse_text(sample_text()))

def absent_field_is_none(absent_maybe: Maybe<&2, Json.Val>) -> Bool:
  match absent_maybe:
    case None{}:
      True{}
    case Some{unexpected_val}:
      False{}

def parsed_doc_lacks_absent(parse_result: Maybe<&2, Json.Val>) -> Bool:
  match parse_result:
    case None{}:
      False{}
    case Some{parsed_doc}:
      absent_field_is_none(JsonAdapter.get_field(parsed_doc, "absent"))

def check_missing_field() -> Bool:
  parsed_doc_lacks_absent(JsonAdapter.parse_text(sample_text()))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Bool.show(check_canonical_bytes()))
    IO.print(Bool.show(check_roundtrip_payload()))
    IO.print(Bool.show(check_missing_field()))
