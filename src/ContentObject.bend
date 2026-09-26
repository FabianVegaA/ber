import Base
import ./ContentHash.bend as ContentHash
import ./LogicalKey.bend as LogicalKey
import ./JsonAdapter.bend as JsonAdapter
import mylsm-lsm-store@0.3.1.0/mylsm.bend as MyLsmStore
import bend-kit-json@0.3.0.0/json.bend as Json

# Content-addressed objects persisted as canonical JSON: equal content gives
# byte-identical text, so the SHA-256 of the text is a stable address.
# Payloads and references stay strings-only, inside the probed doc shapes.
# Kit is named for the Val TYPE only; all operations go through JsonAdapter.
# Effects are MyLSM Sess actions composed in do-blocks.

type ContentObject is Data:
  Make{content_hash: String, payload: String, references: List<&2, String>}

def encode_each_reference(references: List<&2, String>) -> List<&2, Json.Val>:
  match references:
    case Nil{}:
      Nil{}
    case Con{head_reference, remaining_references}:
      Con{JsonAdapter.make_str(head_reference), encode_each_reference(remaining_references)}

def encode_reference_list(payload: String, references: List<&2, String>) -> List<&2, Sigma<&2, &2, String, _ => Json.Val>>:
  Con{JsonAdapter.make_kv("payload", JsonAdapter.make_str(payload)), Con{JsonAdapter.make_kv("references", JsonAdapter.make_arr(encode_each_reference(references))), Nil{}}}

def canonical_content(payload: String, references: List<&2, String>) -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(encode_reference_list(payload, references)))

def finish_store(+content_hash: String, +canonical_text: String) -> MyLsmStore.Sess<&2, String>:
  do MyLsmStore.Sess<&2, String>:
    stored_unit : Unit <- MyLsmStore.sput(LogicalKey.build_object_storage_key(content_hash), canonical_text)
    return content_hash

def wrap_store(+canonical_text: String) -> MyLsmStore.Sess<&2, String>:
  finish_store(ContentHash.compute_sha256_hex(canonical_text), canonical_text)

# SHA-256 of the canonical text; the address consumers store and load by.
def store_content_object(payload: String, references: List<&2, String>) -> MyLsmStore.Sess<&2, String>:
  wrap_store(canonical_content(payload, references))

def prepend_tail_text(head_text: String, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match parsed_tail:
    case None{}:
      None{}
    case Some{tail_texts}:
      Some{Con{head_text, tail_texts}}

def prepend_string_value(head_maybe: Maybe<&2, String>, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match head_maybe:
    case None{}:
      None{}
    case Some{head_text}:
      prepend_tail_text(head_text, parsed_tail)

def prepend_string(head_item: Json.Val, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  prepend_string_value(JsonAdapter.as_str(head_item), parsed_tail)

def extract_each_string(json_items: List<&2, Json.Val>) -> Maybe<&2, List<&2, String>>:
  match json_items:
    case Nil{}:
      Some{Nil{}}
    case Con{head_item, remaining_items}:
      prepend_string(head_item, extract_each_string(remaining_items))

def wrap_reference_texts(content_hash: String, payload_text: String, texts_maybe: Maybe<&2, List<&2, String>>) -> Maybe<&2, ContentObject>:
  match texts_maybe:
    case None{}:
      None{}
    case Some{reference_texts}:
      Some{Make{content_hash, payload_text, reference_texts}}

def finish_object(content_hash: String, payload_text: String, references_maybe: Maybe<&2, List<&2, Json.Val>>) -> Maybe<&2, ContentObject>:
  match references_maybe:
    case None{}:
      None{}
    case Some{reference_items}:
      wrap_reference_texts(content_hash, payload_text, extract_each_string(reference_items))

def extract_with_references(content_hash: String, payload_text: String, references_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match references_maybe:
    case None{}:
      None{}
    case Some{references_json}:
      finish_object(content_hash, payload_text, JsonAdapter.as_arr(references_json))

def extract_with_payload_text(content_hash: String, payload_text: Maybe<&2, String>, references_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match payload_text:
    case None{}:
      None{}
    case Some{actual_payload}:
      extract_with_references(content_hash, actual_payload, references_maybe)

def extract_with_payload(content_hash: String, +document: Json.Val, payload_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match payload_maybe:
    case None{}:
      None{}
    case Some{payload_json}:
      extract_with_payload_text(content_hash, JsonAdapter.as_str(payload_json), JsonAdapter.get_field(document, "references"))

def object_from_parse_result(content_hash: String, parse_result: Maybe<&2, Json.Val>) -> Maybe<&2, ContentObject>:
  match parse_result:
    case None{}:
      None{}
    case Some{+document}:
      extract_with_payload(content_hash, document, JsonAdapter.get_field(document, "payload"))

def parse_canonical_object(content_hash: String, stored_text: String) -> Maybe<&2, ContentObject>:
  object_from_parse_result(content_hash, JsonAdapter.parse_text(stored_text))

def parse_loaded_object(content_hash: String, stored_maybe: Maybe<&2, String>) -> Maybe<&2, ContentObject>:
  match stored_maybe:
    case None{}:
      None{}
    case Some{stored_text}:
      parse_canonical_object(content_hash, stored_text)

# None on missing or malformed stored text; never returns a corrupt object.
def load_content_object(+content_hash: String) -> MyLsmStore.Sess<&2, Maybe<&2, ContentObject>>:
  do MyLsmStore.Sess<&2, Maybe<&2, ContentObject>>:
    stored_maybe : Maybe<&2, String> <- MyLsmStore.sget(LogicalKey.build_object_storage_key(content_hash))
    return parse_loaded_object(content_hash, stored_maybe)

def object_payload_of(content_object: ContentObject) -> String:
  match content_object:
    case Make{content_hash, payload, references}:
      payload
