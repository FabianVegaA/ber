import Base
import bend-kit-json@0.3.0.0/json.bend as Json
import ./JsonAdapter.bend as JsonAdapter
import bend-codec-lib@0.2.0.0/bytes.bend as ByteLib
import bend-codec-lib@0.2.0.0/hex.bend as HexLib

# Multi-type stored values. Canonical forms are single-key objects so every
# constructor hashes differently: {"t": s}, {"o": doc}, {"b": hex}. Binary
# blobs hex-encode through the pinned codec and stay generic binary data,
# never format-specific. Kit is named for the Val TYPE only; all JSON work
# goes through JsonAdapter.

# One stored record value: text, structured document, or binary blob.
type Value is Data:
  Text{content: String}
  Object{object: Json.Val}
  Blob{bytes: List<&2, U32>}

# Canonical JSON of a value; the hashed bytes. Distinct keys per
# constructor keep different values from sharing an address.
def value_to_json(value: Value) -> Json.Val:
  match value:
    case Text{content}:
      JsonAdapter.make_obj(Con{JsonAdapter.make_kv("t", JsonAdapter.make_str(content)), Nil{}})
    case Object{document}:
      JsonAdapter.make_obj(Con{JsonAdapter.make_kv("o", document), Nil{}})
    case Blob{byte_list}:
      JsonAdapter.make_obj(Con{JsonAdapter.make_kv("b", JsonAdapter.make_str(HexLib.Hex.encode(ByteLib.Bytes{byte_list}, HexLib.HexLower{}))), Nil{}})

# Canonical text of a value.
def value_to_canonical(value: Value) -> String:
  JsonAdapter.encode_canonical(value_to_json(value))

# Reads the "t" field as text.
def text_string_or_nothing(text_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, String>:
  match text_maybe:
    case None{}:
      None{}
    case Some{text_val}:
      JsonAdapter.as_str(text_val)

# Unwraps the decoded byte box.
def bytes_data(byte_box: ByteLib.Bytes) -> List<&2, U32>:
  match byte_box:
    case ByteLib.Bytes{raw_data}:
      raw_data

# Reads a hex decode result as a blob; malformed hex reads as None.
def blob_or_nothing(decode_result: Result<&2, &2, HexLib.Hex.Error, ByteLib.Bytes>) -> Maybe<&2, Value>:
  match decode_result:
    case Fail{decode_error}:
      None{}
    case Done{byte_box}:
      Some{Blob{bytes_data(byte_box)}}

# Reads the "b" field as a blob.
def blob_from_hex(hex_maybe: Maybe<&2, String>) -> Maybe<&2, Value>:
  match hex_maybe:
    case None{}:
      None{}
    case Some{hex_text}:
      blob_or_nothing(HexLib.Hex.decode(hex_text))

# Reads the hex text behind the "b" field.
def hex_text_or_nothing(hex_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, String>:
  match hex_maybe:
    case None{}:
      None{}
    case Some{hex_val}:
      JsonAdapter.as_str(hex_val)

# Falls through from text to object to blob; unknown shapes read as None.
def from_object_value(object_maybe: Maybe<&2, Json.Val>, hex_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, Value>:
  match object_maybe:
    case None{}:
      blob_from_hex(hex_text_or_nothing(hex_maybe))
    case Some{document}:
      Some{Object{document}}

# Falls through from text to the remaining shapes.
def from_text_string(text_maybe: Maybe<&2, String>, +document: Json.Val) -> Maybe<&2, Value>:
  match text_maybe:
    case None{}:
      from_object_value(JsonAdapter.get_field(document, "o"), JsonAdapter.get_field(document, "b"))
    case Some{content}:
      Some{Text{content}}

# Parses canonical value JSON; unknown shapes read as None.
def value_from_json(+document: Json.Val) -> Maybe<&2, Value>:
  from_text_string(text_string_or_nothing(JsonAdapter.get_field(document, "t")), document)
