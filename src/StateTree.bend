import Base
import ./Reading.bend as Reading
import ./ContentHash.bend as ContentHash
import ./JsonAdapter.bend as JsonAdapter
import bend-kit-json@0.3.0.0/json.bend as Json

# Flat sorted state tree (v0.1: no children partitioning). Entries sorted by
# combined key ("namespace/record"); staged entries win ties. The tree hash
# covers the flattened entries only, never the JSON text. This module owns
# both tree directions (serialize + parse); History only calls them.
# Kit is named for the Val TYPE only; operations go through JsonAdapter.

type StateTreeNode is Data:
  Make{tree_hash: String, entries: List<&2, Reading.ChainEntry>, children_hashes: List<&2, String>}

def tree_entries(tree_node: StateTreeNode) -> List<&2, Reading.ChainEntry>:
  match tree_node:
    case Make{tree_hash, entries, children_hashes}:
      entries

def tree_hash_of(tree_node: StateTreeNode) -> String:
  match tree_node:
    case Make{tree_hash, entries, children_hashes}:
      tree_hash

def flatten_head(+head_entry: Reading.ChainEntry, flattened_tail: String) -> String:
  Reading.entry_key_of(head_entry) ++ "=" ++ Reading.entry_value_of(head_entry) ++ ";" ++ flattened_tail

def flatten_entries(sorted_entries: List<&2, Reading.ChainEntry>) -> String:
  match sorted_entries:
    case Nil{}:
      ""
    case Con{head_entry, remaining_entries}:
      flatten_head(head_entry, flatten_entries(remaining_entries))

def compute_tree_hash(sorted_entries: List<&2, Reading.ChainEntry>) -> String:
  ContentHash.compute_sha256_hex(flatten_entries(sorted_entries))

def decide_ordering(ordering: Cmp, base_head: Reading.ChainEntry, base_tail: List<&2, Reading.ChainEntry>, staged_head: Reading.ChainEntry, inserted_tail: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match ordering:
    case LT{}:
      Con{base_head, inserted_tail}
    case GT{}:
      Con{staged_head, Con{base_head, base_tail}}
    case EQ{}:
      Con{staged_head, base_tail}

def decide_insert(cmp_result: (String & String) & Cmp, base_head: Reading.ChainEntry, base_tail: List<&2, Reading.ChainEntry>, staged_head: Reading.ChainEntry, inserted_tail: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match cmp_result:
    case ((returned_first, returned_second), ordering):
      decide_ordering(ordering, base_head, base_tail, staged_head, inserted_tail)

def insert_single_entry(base_entries: List<&2, Reading.ChainEntry>, +staged_head: Reading.ChainEntry) -> List<&2, Reading.ChainEntry>:
  match base_entries:
    case Nil{}:
      Con{staged_head, Nil{}}
    case Con{+base_head, +base_tail}:
      decide_insert(String.cmp(Reading.entry_key_of(base_head), Reading.entry_key_of(staged_head)), base_head, base_tail, staged_head, insert_single_entry(base_tail, staged_head))

def merge_sorted_entries(staged_entries: List<&2, Reading.ChainEntry>, base_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match staged_entries:
    case Nil{}:
      base_entries
    case Con{staged_head, staged_tail}:
      merge_sorted_entries(staged_tail, insert_single_entry(base_entries, staged_head))

def entry_pair_to_json(+head_entry: Reading.ChainEntry) -> Json.Val:
  JsonAdapter.make_arr(Con{JsonAdapter.make_str(Reading.entry_key_of(head_entry)), Con{JsonAdapter.make_str(Reading.entry_value_of(head_entry)), Nil{}}})

def entry_list_to_json(sorted_entries: List<&2, Reading.ChainEntry>) -> List<&2, Json.Val>:
  match sorted_entries:
    case Nil{}:
      Nil{}
    case Con{head_entry, remaining_entries}:
      Con{entry_pair_to_json(head_entry), entry_list_to_json(remaining_entries)}

def finalize_tree_document(hash_field: Sigma<&2, &2, String, _ => Json.Val>, entries_field: Sigma<&2, &2, String, _ => Json.Val>, children_field: Sigma<&2, &2, String, _ => Json.Val>) -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(Con{hash_field, Con{entries_field, Con{children_field, Nil{}}}}))

def serialize_tree(+merged_entries: List<&2, Reading.ChainEntry>, +tree_hash_value: String) -> String:
  finalize_tree_document(JsonAdapter.make_kv("hash", JsonAdapter.make_str(tree_hash_value)), JsonAdapter.make_kv("entries", JsonAdapter.make_arr(entry_list_to_json(merged_entries))), JsonAdapter.make_kv("children", JsonAdapter.make_arr(Nil{})))

def prepend_entry_pair(key_text: String, value_text: String, parsed_tail: Maybe<&2, List<&2, Reading.ChainEntry>>) -> Maybe<&2, List<&2, Reading.ChainEntry>>:
  match parsed_tail:
    case None{}:
      None{}
    case Some{tail_entries}:
      Some{Con{Reading.make_entry(key_text, value_text), tail_entries}}

def prepend_value_text(key_text: String, value_maybe: Maybe<&2, String>, parsed_tail: Maybe<&2, List<&2, Reading.ChainEntry>>) -> Maybe<&2, List<&2, Reading.ChainEntry>>:
  match value_maybe:
    case None{}:
      None{}
    case Some{value_text}:
      prepend_entry_pair(key_text, value_text, parsed_tail)

def prepend_pair_texts(key_maybe: Maybe<&2, String>, value_maybe: Maybe<&2, String>, parsed_tail: Maybe<&2, List<&2, Reading.ChainEntry>>) -> Maybe<&2, List<&2, Reading.ChainEntry>>:
  match key_maybe:
    case None{}:
      None{}
    case Some{key_text}:
      prepend_value_text(key_text, value_maybe, parsed_tail)

def prepend_pair_items(pair_items: List<&2, Json.Val>, parsed_tail: Maybe<&2, List<&2, Reading.ChainEntry>>) -> Maybe<&2, List<&2, Reading.ChainEntry>>:
  match pair_items:
    case Con{key_json, Con{value_json, Nil{}}}:
      prepend_pair_texts(JsonAdapter.as_str(key_json), JsonAdapter.as_str(value_json), parsed_tail)
    case _:
      None{}

def prepend_parsed_pair(pair_maybe: Maybe<&2, List<&2, Json.Val>>, parsed_tail: Maybe<&2, List<&2, Reading.ChainEntry>>) -> Maybe<&2, List<&2, Reading.ChainEntry>>:
  match pair_maybe:
    case None{}:
      None{}
    case Some{pair_items}:
      prepend_pair_items(pair_items, parsed_tail)

def prepend_parsed_entry(head_item: Json.Val, parsed_tail: Maybe<&2, List<&2, Reading.ChainEntry>>) -> Maybe<&2, List<&2, Reading.ChainEntry>>:
  prepend_parsed_pair(JsonAdapter.as_arr(head_item), parsed_tail)

def parse_entry_list(entry_items: List<&2, Json.Val>) -> Maybe<&2, List<&2, Reading.ChainEntry>>:
  match entry_items:
    case Nil{}:
      Some{Nil{}}
    case Con{head_item, remaining_items}:
      prepend_parsed_entry(head_item, parse_entry_list(remaining_items))

def prepend_child_tail(head_text: String, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match parsed_tail:
    case None{}:
      None{}
    case Some{tail_texts}:
      Some{Con{head_text, tail_texts}}

def prepend_child_text(head_maybe: Maybe<&2, String>, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match head_maybe:
    case None{}:
      None{}
    case Some{head_text}:
      prepend_child_tail(head_text, parsed_tail)

def prepend_child_string(head_item: Json.Val, parsed_tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  prepend_child_text(JsonAdapter.as_str(head_item), parsed_tail)

def extract_child_strings(child_items: List<&2, Json.Val>) -> Maybe<&2, List<&2, String>>:
  match child_items:
    case Nil{}:
      Some{Nil{}}
    case Con{head_item, remaining_items}:
      prepend_child_string(head_item, extract_child_strings(remaining_items))

def finish_tree_node(tree_hash_text: String, parsed_entries: List<&2, Reading.ChainEntry>, strings_maybe: Maybe<&2, List<&2, String>>) -> Maybe<&2, StateTreeNode>:
  match strings_maybe:
    case None{}:
      None{}
    case Some{child_hashes}:
      Some{Make{tree_hash_text, parsed_entries, child_hashes}}

def finish_children_strings(tree_hash_text: String, parsed_entries: List<&2, Reading.ChainEntry>, items_maybe: Maybe<&2, List<&2, Json.Val>>) -> Maybe<&2, StateTreeNode>:
  match items_maybe:
    case None{}:
      None{}
    case Some{child_items}:
      finish_tree_node(tree_hash_text, parsed_entries, extract_child_strings(child_items))

def extract_children_array(tree_hash_text: String, parsed_entries: List<&2, Reading.ChainEntry>, children_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, StateTreeNode>:
  match children_maybe:
    case None{}:
      None{}
    case Some{children_json}:
      finish_children_strings(tree_hash_text, parsed_entries, JsonAdapter.as_arr(children_json))

def extract_children(+document: Json.Val, tree_hash_text: String, entries_maybe: Maybe<&2, List<&2, Reading.ChainEntry>>) -> Maybe<&2, StateTreeNode>:
  match entries_maybe:
    case None{}:
      None{}
    case Some{parsed_entries}:
      extract_children_array(tree_hash_text, parsed_entries, JsonAdapter.get_field(document, "children"))

def extract_entry_items(+document: Json.Val, tree_hash_text: String, items_maybe: Maybe<&2, List<&2, Json.Val>>) -> Maybe<&2, StateTreeNode>:
  match items_maybe:
    case None{}:
      None{}
    case Some{entry_items}:
      extract_children(document, tree_hash_text, parse_entry_list(entry_items))

def extract_entry_array(+document: Json.Val, tree_hash_text: String, entries_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, StateTreeNode>:
  match entries_maybe:
    case None{}:
      None{}
    case Some{entries_json}:
      extract_entry_items(document, tree_hash_text, JsonAdapter.as_arr(entries_json))

def extract_with_tree_entries(+document: Json.Val, hash_text_maybe: Maybe<&2, String>, entries_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, StateTreeNode>:
  match hash_text_maybe:
    case None{}:
      None{}
    case Some{tree_hash_text}:
      extract_entry_array(document, tree_hash_text, entries_maybe)

def extract_with_tree_hash(+document: Json.Val, hash_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, StateTreeNode>:
  match hash_maybe:
    case None{}:
      None{}
    case Some{hash_json}:
      extract_with_tree_entries(document, JsonAdapter.as_str(hash_json), JsonAdapter.get_field(document, "entries"))

def extract_tree_fields(+document: Json.Val) -> Maybe<&2, StateTreeNode>:
  extract_with_tree_hash(document, JsonAdapter.get_field(document, "hash"))

def tree_from_parse(parse_result: Maybe<&2, Json.Val>) -> Maybe<&2, StateTreeNode>:
  match parse_result:
    case None{}:
      None{}
    case Some{+document}:
      extract_tree_fields(document)

def parse_tree_document(stored_text: String) -> Maybe<&2, StateTreeNode>:
  tree_from_parse(JsonAdapter.parse_text(stored_text))
