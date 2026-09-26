import Base
import bend-kit-json@0.3.0.0/json.bend as Json

# Sole owner of JSON operations. Consumers import THIS module for all
# encode/parse/get work; they import the kit package ONLY for the Val type in
# annotations (Bend cannot alias types across modules — same convention as
# MyLsmStore.Sess).
# TRUST BOUNDARY: Json.parse is structural recursion. Json.encode is @unsafe
# upstream (work-list walk, documented in kit source); canonical-bytes
# (equal content => identical text) is covered by json_bytes_probe and the
# differential check vs Python json, not by proof. If kit ships a safe
# encoder, only this file changes.

def make_str(+text: String) -> Json.Val:
  Json.Str{text}

def make_arr(items: List<&2, Json.Val>) -> Json.Val:
  Json.Arr{items}

def make_kv(+field_key: String, field_value: Json.Val) -> Sigma<&2, &2, String, _ => Json.Val>:
  (field_key, field_value)

def fold_pair(field_map: Map<&2, Json.Val>, field_pair: Sigma<&2, &2, String, _ => Json.Val>) -> Map<&2, Json.Val>:
  match field_pair:
    case (field_key, field_value):
      Map.set(&2, Json.Val, field_map, field_key, field_value)

def fold_fields(remaining_fields: List<&2, Sigma<&2, &2, String, _ => Json.Val>>, field_map: Map<&2, Json.Val>) -> Map<&2, Json.Val>:
  match remaining_fields:
    case Nil{}:
      field_map
    case Con{field_pair, tail_fields}:
      fold_fields(tail_fields, fold_pair(field_map, field_pair))

def make_obj(fields: List<&2, Sigma<&2, &2, String, _ => Json.Val>>) -> Json.Val:
  Json.Obj{fold_fields(fields, Map.new(&2, Json.Val))}

def parse_text(+stored_text: String) -> Maybe<&2, Json.Val>:
  Json.parse(stored_text)

def get_field(+document: Json.Val, +field_name: String) -> Maybe<&2, Json.Val>:
  Json.get(document, field_name)

def as_str(json_value: Json.Val) -> Maybe<&2, String>:
  match json_value:
    case Json.Str{text}:
      Some{text}
    case _:
      None{}

def as_arr(json_value: Json.Val) -> Maybe<&2, List<&2, Json.Val>>:
  match json_value:
    case Json.Arr{items}:
      Some{items}
    case _:
      None{}

def encode_canonical(+document: Json.Val) -> String:
  Json.encode(document)
