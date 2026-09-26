import Base
import ./vendor/json/json.bend as Rootagi
import bend-kit-json@0.3.0.0/json.bend as Kit

# One-shot migration gate: prove kit emits byte-identical canonical text to
# vendored rootagi for every document shape ber-core persists. Deleted with
# vendor/ after the migration lands.

def probe_fold(fields: List<&2, Sigma<&2, &2, String, _ => Kit.Val>>, field_map: Map<&2, Kit.Val>) -> Map<&2, Kit.Val>:
  match fields:
    case Nil{}:
      field_map
    case (field_key, field_value) <> tail_fields:
      probe_fold(tail_fields, Map.set(&2, Kit.Val, field_map, field_key, field_value))

def probe_obj(fields: List<&2, Sigma<&2, &2, String, _ => Kit.Val>>) -> Kit.Val:
  Kit.Obj{probe_fold(fields, Map.new(&2, Kit.Val))}

# --- content-object shape ---

def rootagi_ref_list() -> List<&2, Rootagi.Json>:
  Con{Rootagi.str("ref_a"), Nil{}}

def rootagi_content_fields() -> List<&2, Sigma<&2, &2, String, _ => Rootagi.Json>>:
  Con{Rootagi.kv("payload", Rootagi.str("hello")), Con{Rootagi.kv("references", Rootagi.arr(rootagi_ref_list())), Nil{}}}

def rootagi_content_object() -> String:
  Rootagi.stringify(Rootagi.sort_keys(Rootagi.obj(rootagi_content_fields())))

def kit_ref_list() -> List<&2, Kit.Val>:
  Con{Kit.Str{"ref_a"}, Nil{}}

def kit_content_fields() -> List<&2, Sigma<&2, &2, String, _ => Kit.Val>>:
  Con{("payload", Kit.Str{"hello"}), Con{("references", Kit.Arr{kit_ref_list()}), Nil{}}}

def kit_content_object() -> String:
  Kit.encode(probe_obj(kit_content_fields()))

# --- commit shape ---

def rootagi_parent_list() -> List<&2, Rootagi.Json>:
  Con{Rootagi.str("parent_one"), Nil{}}

def rootagi_meta_pair() -> Rootagi.Json:
  Rootagi.arr(Con{Rootagi.str("strategy"), Con{Rootagi.str("union-disjoint"), Nil{}}})

def rootagi_meta_list() -> List<&2, Rootagi.Json>:
  Con{rootagi_meta_pair(), Nil{}}

def rootagi_commit_fields() -> List<&2, Sigma<&2, &2, String, _ => Rootagi.Json>>:
  Con{Rootagi.kv("parents", Rootagi.arr(rootagi_parent_list())), Con{Rootagi.kv("tree", Rootagi.str("abc123")), Con{Rootagi.kv("meta", Rootagi.arr(rootagi_meta_list())), Nil{}}}}

def rootagi_commit() -> String:
  Rootagi.stringify(Rootagi.sort_keys(Rootagi.obj(rootagi_commit_fields())))

def kit_parent_list() -> List<&2, Kit.Val>:
  Con{Kit.Str{"parent_one"}, Nil{}}

def kit_meta_pair() -> Kit.Val:
  Kit.Arr{Con{Kit.Str{"strategy"}, Con{Kit.Str{"union-disjoint"}, Nil{}}}}

def kit_meta_list() -> List<&2, Kit.Val>:
  Con{kit_meta_pair(), Nil{}}

def kit_commit_fields() -> List<&2, Sigma<&2, &2, String, _ => Kit.Val>>:
  Con{("parents", Kit.Arr{kit_parent_list()}), Con{("tree", Kit.Str{"abc123"}), Con{("meta", Kit.Arr{kit_meta_list()}), Nil{}}}}

def kit_commit() -> String:
  Kit.encode(probe_obj(kit_commit_fields()))

# --- tree shape ---

def rootagi_entry_pair(entry_key: String, entry_value: String) -> Rootagi.Json:
  Rootagi.arr(Con{Rootagi.str(entry_key), Con{Rootagi.str(entry_value), Nil{}}})

def rootagi_entry_list() -> List<&2, Rootagi.Json>:
  Con{rootagi_entry_pair("ledger/record_a", "hash_a"), Con{rootagi_entry_pair("ledger/record_b", "hash_b"), Nil{}}}

def rootagi_tree_fields() -> List<&2, Sigma<&2, &2, String, _ => Rootagi.Json>>:
  Con{Rootagi.kv("hash", Rootagi.str("tree_hash_value")), Con{Rootagi.kv("entries", Rootagi.arr(rootagi_entry_list())), Con{Rootagi.kv("children", Rootagi.arr(Nil{})), Nil{}}}}

def rootagi_tree() -> String:
  Rootagi.stringify(Rootagi.sort_keys(Rootagi.obj(rootagi_tree_fields())))

def kit_entry_pair(entry_key: String, entry_value: String) -> Kit.Val:
  Kit.Arr{Con{Kit.Str{entry_key}, Con{Kit.Str{entry_value}, Nil{}}}}

def kit_entry_list() -> List<&2, Kit.Val>:
  Con{kit_entry_pair("ledger/record_a", "hash_a"), Con{kit_entry_pair("ledger/record_b", "hash_b"), Nil{}}}

def kit_tree_fields() -> List<&2, Sigma<&2, &2, String, _ => Kit.Val>>:
  Con{("hash", Kit.Str{"tree_hash_value"}), Con{("entries", Kit.Arr{kit_entry_list()}), Con{("children", Kit.Arr{Nil{}}), Nil{}}}}

def kit_tree() -> String:
  Kit.encode(probe_obj(kit_tree_fields()))

# --- stage-index shape (plain array, no key sorting) ---

def rootagi_stage_index() -> String:
  Rootagi.stringify(Rootagi.arr(Con{Rootagi.str("stage/s/ledger/r1"), Con{Rootagi.str("stage/s/ledger/r2"), Nil{}}}))

def kit_stage_keys() -> List<&2, Kit.Val>:
  Con{Kit.Str{"stage/s/ledger/r1"}, Con{Kit.Str{"stage/s/ledger/r2"}, Nil{}}}

def kit_stage_index() -> String:
  Kit.encode(Kit.Arr{kit_stage_keys()})

# --- verdict ---

def flag_line(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def val_text_or_empty(json_value: Kit.Val) -> String:
  match json_value:
    case Kit.Str{text}:
      text
    case _:
      ""

def payload_field_text(payload_maybe: Maybe<&2, Kit.Val>) -> String:
  match payload_maybe:
    case None{}:
      ""
    case Some{payload_val}:
      val_text_or_empty(payload_val)

def parsed_payload_text(parse_result: Maybe<&2, Kit.Val>) -> String:
  match parse_result:
    case None{}:
      ""
    case Some{parsed_doc}:
      payload_field_text(Kit.get(parsed_doc, "payload"))

def payload_roundtrip_ok() -> Bool:
  String.eq(parsed_payload_text(Kit.parse(kit_content_object())), "hello")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(flag_line("content-object-bytes", String.eq(rootagi_content_object(), kit_content_object())))
    IO.print(flag_line("commit-bytes", String.eq(rootagi_commit(), kit_commit())))
    IO.print(flag_line("tree-bytes", String.eq(rootagi_tree(), kit_tree())))
    IO.print(flag_line("stage-index-bytes", String.eq(rootagi_stage_index(), kit_stage_index())))
    IO.print(flag_line("kit-parse-roundtrip", payload_roundtrip_ok()))
