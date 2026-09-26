import Base
import ./ContentHash.bend as ContentHash
import ./LogicalKey.bend as LogicalKey
import ./JsonAdapter.bend as JsonAdapter
import ./Value.bend as Value
import ./Store.bend as Store
import bend-kit-json@0.3.0.0/json.bend as Json

# Content-addressed objects persisted as canonical JSON: equal content gives
# byte-identical text, so the SHA-256 of the text is a stable address.
# Payloads are multi-type Values (text, document, blob); references stay
# string lists. Kit and Value are named for TYPES only; all operations go
# through JsonAdapter and Value. Effects are Store Op actions in do-blocks.

# Addressable payload with content hash and references.
type ContentObject is Data:
  Make{content_hash: String, payload: Value.Value, references: List<&2, String>}

# Encodes each reference string as a JSON string.
def encode_each_reference(references: List<&2, String>) -> List<&2, Json.Val>:
  match references:
    case Nil{}:
      Nil{}
    case Con{head_reference, remaining_references}:
      Con{JsonAdapter.make_str(head_reference), encode_each_reference(remaining_references)}

# Builds the payload/references field list.
def encode_reference_list(payload: Value.Value, references: List<&2, String>) -> List<&2, Sigma<&2, &2, String, _ => Json.Val>>:
  Con{JsonAdapter.make_kv("payload", Value.value_to_json(payload)), Con{JsonAdapter.make_kv("references", JsonAdapter.make_arr(encode_each_reference(references))), Nil{}}}

# Canonical text of a content object; the hashed bytes.
def canonical_content(payload: Value.Value, references: List<&2, String>) -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(encode_reference_list(payload, references)))

# Persists the text under its hash and returns the hash.
def finish_store(+content_hash: String, +canonical_text: String) -> Store.Op<&2, String>:
  do Store.Op<&2, String>:
    stored_unit : Unit <- Store.oput(LogicalKey.build_object_storage_key(content_hash), canonical_text)
    return content_hash

# Hashes the text, then stores it.
def wrap_store(+canonical_text: String) -> Store.Op<&2, String>:
  finish_store(ContentHash.compute_sha256_hex(canonical_text), canonical_text)

# SHA-256 of the canonical text; the address consumers store and load by.
def store_content_object(payload: Value.Value, references: List<&2, String>) -> Store.Op<&2, String>:
  wrap_store(canonical_content(payload, references))

# Conses decoded text onto the tail, failing closed on None.
def prepend_tail_text(head_text: String, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match parsed_tail:
    case None{}:
      None{}
    case Some{tail_texts}:
      Some{Con{head_text, tail_texts}}

# Unwraps the head string, then prepends.
def prepend_string_value(head_maybe: Maybe<&2, String>, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match head_maybe:
    case None{}:
      None{}
    case Some{head_text}:
      prepend_tail_text(head_text, parsed_tail)

# Decodes one JSON array item as a string.
def prepend_string(head_item: Json.Val, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  prepend_string_value(JsonAdapter.as_str(head_item), parsed_tail)

# Decodes a JSON string array; None on any non-string.
def extract_each_string(json_items: List<&2, Json.Val>) -> Maybe<&2, List<&2, String>>:
  match json_items:
    case Nil{}:
      Some{Nil{}}
    case Con{head_item, remaining_items}:
      prepend_string(head_item, extract_each_string(remaining_items))

# Reassembles the object once references decode.
def wrap_reference_texts(content_hash: String, payload_value: Value.Value, texts_maybe: Maybe<&2, List<&2, String>>) -> Maybe<&2, ContentObject>:
  match texts_maybe:
    case None{}:
      None{}
    case Some{reference_texts}:
      Some{Make{content_hash, payload_value, reference_texts}}

# Unwraps the references array, then reassembles.
def finish_object(content_hash: String, payload_value: Value.Value, references_maybe: Maybe<&2, List<&2, Json.Val>>) -> Maybe<&2, ContentObject>:
  match references_maybe:
    case None{}:
      None{}
    case Some{reference_items}:
      wrap_reference_texts(content_hash, payload_value, extract_each_string(reference_items))

# Unwraps the references field, then finishes.
def extract_with_references(content_hash: String, payload_value: Value.Value, references_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match references_maybe:
    case None{}:
      None{}
    case Some{references_json}:
      finish_object(content_hash, payload_value, JsonAdapter.as_arr(references_json))

# Unwraps the payload value, then continues.
def extract_with_payload_value(content_hash: String, payload_value_maybe: Maybe<&2, Value.Value>, references_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match payload_value_maybe:
    case None{}:
      None{}
    case Some{payload_value}:
      extract_with_references(content_hash, payload_value, references_maybe)

# Unwraps the payload field, then continues.
def extract_with_payload(content_hash: String, +document: Json.Val, payload_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match payload_maybe:
    case None{}:
      None{}
    case Some{payload_json}:
      extract_with_payload_value(content_hash, Value.value_from_json(payload_json), JsonAdapter.get_field(document, "references"))

# Builds the object from parsed JSON; None on malformed input.
def object_from_parse_result(content_hash: String, parse_result: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match parse_result:
    case None{}:
      None{}
    case Some{+document}:
      extract_with_payload(content_hash, document, JsonAdapter.get_field(document, "payload"))

# Parses stored canonical text into an object.
def parse_canonical_object(content_hash: String, stored_text: String) -> Maybe<&2, ContentObject>:
  object_from_parse_result(content_hash, JsonAdapter.parse_text(stored_text))

# Parses loaded text; missing storage reads as None.
def parse_loaded_object(content_hash: String, stored_maybe: Maybe<&2, String>) -> Maybe<&2, ContentObject>:
  match stored_maybe:
    case None{}:
      None{}
    case Some{stored_text}:
      parse_canonical_object(content_hash, stored_text)

# None on missing or malformed stored text; never returns a corrupt object.
def load_content_object(+content_hash: String) -> Store.Op<&2, Maybe<&2, ContentObject>>:
  do Store.Op<&2, Maybe<&2, ContentObject>>:
    stored_maybe : Maybe<&2, String> <- Store.oget(LogicalKey.build_object_storage_key(content_hash))
    return parse_loaded_object(content_hash, stored_maybe)

# Projects the payload out of an object.
def object_payload_of(content_object: ContentObject) -> Value.Value:
  match content_object:
    case Make{content_hash, payload, references}:
      payload
