import Base
import ./LogicalKey.bend as LogicalKey
import ./ContentObject.bend as ContentObject
import ./MyLsmBinding.bend as Binding
import 0x0ae7ac793853e753f5f74c16e06ee078/mylsm.bend as MyLsmStore
import ../vendor/json/json.bend as JsonLib

# Uncommitted working set. Staged keys live at stage/{session}/{ns}/{id};
# the per-session key manifest lives at stage-index/{session} (a JSON string
# list). Point operations ONLY — no prefix scan anywhere. Effects via Binding;
# MyLsmStore named for Sess types only.

def stage_index_key(+session_identifier: String) -> String:
  "stage-index/" ++ session_identifier

def serialize_key_list(staged_keys: List<&2, String>) -> String:
  JsonLib.stringify(JsonLib.arr(ContentObject.encode_each_reference(staged_keys)))

def index_from_strings(strings_maybe: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match strings_maybe:
    case None{}:
      Nil{}
    case Some{key_texts}:
      key_texts

def index_from_document(items_maybe: Maybe<&2, List<&2, JsonLib.Json>>) -> List<&2, String>:
  match items_maybe:
    case None{}:
      Nil{}
    case Some{json_items}:
      index_from_strings(ContentObject.extract_each_string(json_items))

def index_from_text(parse_result: Result<&2, &2, String, JsonLib.Json>) -> List<&2, String>:
  match parse_result:
    case Fail{parse_error}:
      Nil{}
    case Done{document}:
      index_from_document(JsonLib.as_arr(document))

def parse_stage_index(stored_maybe: Maybe<&2, String>) -> List<&2, String>:
  match stored_maybe:
    case None{}:
      Nil{}
    case Some{stored_text}:
      index_from_text(JsonLib.parse(stored_text))

def decide_contains(head_matches: Bool, recursive_result: Bool) -> Bool:
  match head_matches:
    case True{}:
      True{}
    case False{}:
      recursive_result

def contains_staged_key(+target_key: String, staged_keys: List<&2, String>) -> Bool:
  match staged_keys:
    case Nil{}:
      False{}
    case Con{head_key, remaining_keys}:
      decide_contains(String.eq(head_key, target_key), contains_staged_key(target_key, remaining_keys))

def prepend_unless_present(already_present: Bool, target_key: String, staged_keys: List<&2, String>) -> List<&2, String>:
  match already_present:
    case True{}:
      staged_keys
    case False{}:
      Con{target_key, staged_keys}

def add_key_unless_present(+target_key: String, +staged_keys: List<&2, String>) -> List<&2, String>:
  prepend_unless_present(contains_staged_key(target_key, staged_keys), target_key, staged_keys)

def load_stage_index(+session_identifier: String) -> MyLsmStore.Sess<&2, List<&2, String>>:
  do MyLsmStore.Sess<&2, List<&2, String>>:
    stored_maybe : Maybe<&2, String> <- Binding.load_value(stage_index_key(session_identifier))
    return parse_stage_index(stored_maybe)

def record_stage_entry(+session_identifier: String, +namespace_name: String, +record_identifier: String, value_hash: String) -> MyLsmStore.Sess<&2, LogicalKey.LogicalKey>:
  do MyLsmStore.Sess<&2, LogicalKey.LogicalKey>:
    +full_key_text : String = LogicalKey.encode_logical_key(LogicalKey.Make{namespace_name, record_identifier})
    current_index : List<&2, String> <- load_stage_index(session_identifier)
    stored_unit : Unit <- Binding.store_value(LogicalKey.build_stage_storage_key(session_identifier, namespace_name, record_identifier), value_hash)
    saved_unit : Unit <- Binding.store_value(stage_index_key(session_identifier), serialize_key_list(add_key_unless_present(full_key_text, current_index)))
    return LogicalKey.Make{namespace_name, record_identifier}

def put_record(+session_identifier: String, +namespace_name: String, +record_identifier: String, value: String) -> MyLsmStore.Sess<&2, LogicalKey.LogicalKey>:
  do MyLsmStore.Sess<&2, LogicalKey.LogicalKey>:
    +value_hash : String <- ContentObject.store_content_object(value, Nil{})
    staged_key : LogicalKey.LogicalKey <- record_stage_entry(session_identifier, namespace_name, record_identifier, value_hash)
    return staged_key

def delete_record(+session_identifier: String, +namespace_name: String, +record_identifier: String) -> MyLsmStore.Sess<&2, LogicalKey.LogicalKey>:
  do MyLsmStore.Sess<&2, LogicalKey.LogicalKey>:
    staged_key : LogicalKey.LogicalKey <- record_stage_entry(session_identifier, namespace_name, record_identifier, "TOMBSTONE")
    return staged_key
