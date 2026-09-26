import Base
import ../src/Value.bend as Value
import ../src/JsonAdapter.bend as JsonAdapter
import bend-kit-json@0.3.0.0/json.bend as Json

# Value check: roundtrips for all three constructors with exact canonical
# bytes pinned, plus injectivity (constructors never share bytes).

def sample_doc() -> Json.Val:
  JsonAdapter.make_obj(Con{JsonAdapter.make_kv("k", JsonAdapter.make_str("v")), Nil{}})

def sample_bytes() -> List<&2, U32>:
  Con{0, Con{1, Con{2, Con{250, Nil{}}}}}

def flag_line(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def parsed_value(parse_result: Maybe<&2, Json.Val>) -> Maybe<&2, Value.Value>:
  match parse_result:
    case None{}:
      None{}
    case Some{document}:
      Value.value_from_json(document)

def text_ok(found_maybe: Maybe<&2, Value.Value>) -> Bool:
  match found_maybe:
    case None{}:
      False{}
    case Some{Value.Text{+content}}:
      String.eq(content, "hello") && String.eq(Value.value_to_canonical(Value.Text{content}), "{\"t\":\"hello\"}")
    case _:
      False{}

def check_text_roundtrip() -> Bool:
  text_ok(parsed_value(JsonAdapter.parse_text(Value.value_to_canonical(Value.Text{"hello"}))))

def object_ok(found_maybe: Maybe<&2, Value.Value>) -> Bool:
  match found_maybe:
    case None{}:
      False{}
    case Some{Value.Object{+document}}:
      String.eq(JsonAdapter.encode_canonical(document), JsonAdapter.encode_canonical(sample_doc())) && String.eq(Value.value_to_canonical(Value.Object{document}), "{\"o\":{\"k\":\"v\"}}")
    case _:
      False{}

def check_object_roundtrip() -> Bool:
  object_ok(parsed_value(JsonAdapter.parse_text(Value.value_to_canonical(Value.Object{sample_doc()}))))

def blob_ok(found_maybe: Maybe<&2, Value.Value>) -> Bool:
  match found_maybe:
    case None{}:
      False{}
    case Some{Value.Blob{+found_bytes}}:
      Nat.is_eq(List.length(&2, U32, found_bytes), 4n) && String.eq(Value.value_to_canonical(Value.Blob{found_bytes}), "{\"b\":\"000102fa\"}")
    case _:
      False{}

def check_blob_roundtrip() -> Bool:
  blob_ok(parsed_value(JsonAdapter.parse_text(Value.value_to_canonical(Value.Blob{sample_bytes()}))))

def text_canon_of() -> String:
  Value.value_to_canonical(Value.Text{"x"})

def object_canon_of() -> String:
  Value.value_to_canonical(Value.Object{JsonAdapter.make_str("x")})

def blob_canon_of() -> String:
  Value.value_to_canonical(Value.Blob{sample_bytes()})

def second_differs(eq_result: Bool) -> Bool:
  match eq_result:
    case True{}:
      False{}
    case False{}:
      True{}

def differs_pairwise(first_eq_second: Bool, +first_text: String, +third_text: String) -> Bool:
  match first_eq_second:
    case True{}:
      False{}
    case False{}:
      second_differs(String.eq(first_text, third_text))

def check_injectivity() -> Bool:
  differs_pairwise(String.eq(text_canon_of(), object_canon_of()), text_canon_of(), blob_canon_of())

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(flag_line("text-roundtrip", check_text_roundtrip()))
    IO.print(flag_line("object-roundtrip", check_object_roundtrip()))
    IO.print(flag_line("blob-roundtrip", check_blob_roundtrip()))
    IO.print(flag_line("canonical-injective", check_injectivity()))
