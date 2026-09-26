import Base
import ./Reading.bend as Reading
import ./LogicalKey.bend as LogicalKey
import ./ContentHash.bend as ContentHash
import ./StateTree.bend as StateTree
import ./Staging.bend as Staging
import ./ContentObject.bend as ContentObject
import ./JsonAdapter.bend as JsonAdapter
import mylsm-lsm-store@0.3.1.0/mylsm.bend as MyLsmStore
import bend-kit-json@0.3.0.0/json.bend as Json

# Linear history: staging -> merged tree -> commit -> per-key version index.
# Commits serialize as canonical JSON without timestamp/certificate (both
# re-materialize on load: 0 / None). Loads re-serialize the parsed fields and
# compare against the stored text: a mismatch yields None, never corruption.
# Kit is named for the Val TYPE only; operations go through JsonAdapter.
# Effects are MyLSM Sess actions composed in do-blocks.

# One metadata key/value field.
type CommitMeta is Data:
  Field{field_key: String, field_value: String}

# Identifier, parents, tree hash, timestamp, metadata and certificate.
type Commit is Data:
  Make{commit_identifier: String, parent_commit_identifiers: List<&2, String>, tree_hash: String, timestamp: Nat, metadata: List<&2, CommitMeta>, certificate_hash: Maybe<&2, String>}

# Projects the identifier out of a commit.
def commit_identifier_of(commit_value: Commit) -> String:
  match commit_value:
    case Make{commit_identifier, parent_commit_identifiers, tree_hash, timestamp, metadata, certificate_hash}:
      commit_identifier

# Projects the tree hash out of a commit.
def commit_tree_of(commit_value: Commit) -> String:
  match commit_value:
    case Make{commit_identifier, parent_commit_identifiers, tree_hash, timestamp, metadata, certificate_hash}:
      tree_hash

# Encodes one metadata field as a two-item array.
def meta_pair_to_json(meta_field: CommitMeta) -> Json.Val:
  match meta_field:
    case Field{field_key, field_value}:
      JsonAdapter.make_arr(Con{JsonAdapter.make_str(field_key), Con{JsonAdapter.make_str(field_value), Nil{}}})

# Encodes the metadata list.
def meta_list_to_json(metadata: List<&2, CommitMeta>) -> List<&2, Json.Val>:
  match metadata:
    case Nil{}:
      Nil{}
    case Con{head_field, remaining_fields}:
      Con{meta_pair_to_json(head_field), meta_list_to_json(remaining_fields)}

# Encodes parent identifiers as strings.
def encode_parent_list(parent_commit_identifiers: List<&2, String>) -> List<&2, Json.Val>:
  match parent_commit_identifiers:
    case Nil{}:
      Nil{}
    case Con{head_parent, remaining_parents}:
      Con{JsonAdapter.make_str(head_parent), encode_parent_list(remaining_parents)}

# Encodes the parents/tree/meta document canonically.
def finalize_commit_document(parents_field: Sigma<&2, &2, String, _ => Json.Val>, tree_field: Sigma<&2, &2, String, _ => Json.Val>, meta_field: Sigma<&2, &2, String, _ => Json.Val>) -> String:
  JsonAdapter.encode_canonical(JsonAdapter.make_obj(Con{parents_field, Con{tree_field, Con{meta_field, Nil{}}}}))

# Serializes parents, tree and metadata; the hashed bytes.
def serialize_commit(parent_commit_identifiers: List<&2, String>, metadata: List<&2, CommitMeta>, tree_hash_value: String) -> String:
  finalize_commit_document(JsonAdapter.make_kv("parents", JsonAdapter.make_arr(encode_parent_list(parent_commit_identifiers))), JsonAdapter.make_kv("tree", JsonAdapter.make_str(tree_hash_value)), JsonAdapter.make_kv("meta", JsonAdapter.make_arr(meta_list_to_json(metadata))))

# Conses a decoded meta field onto the tail.
def prepend_meta_field(field_key: String, field_value: String, parsed_tail: Maybe<&2, List<&2, CommitMeta>>) -> Maybe<&2, List<&2, CommitMeta>>:
  match parsed_tail:
    case None{}:
      None{}
    case Some{tail_fields}:
      Some{Con{Field{field_key, field_value}, tail_fields}}

# Unwraps the field value, then prepends.
def prepend_meta_value(field_key: String, value_maybe: Maybe<&2, String>, parsed_tail: Maybe<&2, List<&2, CommitMeta>>) -> Maybe<&2, List<&2, CommitMeta>>:
  match value_maybe:
    case None{}:
      None{}
    case Some{field_value}:
      prepend_meta_field(field_key, field_value, parsed_tail)

# Unwraps the key text, then continues.
def prepend_meta_texts(key_maybe: Maybe<&2, String>, value_maybe: Maybe<&2, String>, parsed_tail: Maybe<&2, List<&2, CommitMeta>>) -> Maybe<&2, List<&2, CommitMeta>>:
  match key_maybe:
    case None{}:
      None{}
    case Some{field_key}:
      prepend_meta_value(field_key, value_maybe, parsed_tail)

# Decodes one [key, value] array; None on wrong shape.
def prepend_meta_items(pair_items: List<&2, Json.Val>, parsed_tail: Maybe<&2, List<&2, CommitMeta>>) -> Maybe<&2, List<&2, CommitMeta>>:
  match pair_items:
    case Con{key_json, Con{value_json, Nil{}}}:
      prepend_meta_texts(JsonAdapter.as_str(key_json), JsonAdapter.as_str(value_json), parsed_tail)
    case _:
      None{}

# Unwraps the pair array, then decodes.
def prepend_parsed_meta(pair_maybe: Maybe<&2, List<&2, Json.Val>>, parsed_tail: Maybe<&2, List<&2, CommitMeta>>) -> Maybe<&2, List<&2, CommitMeta>>:
  match pair_maybe:
    case None{}:
      None{}
    case Some{pair_items}:
      prepend_meta_items(pair_items, parsed_tail)

# Decodes one metadata item.
def prepend_meta_entry(head_item: Json.Val, parsed_tail: Maybe<&2, List<&2, CommitMeta>>) -> Maybe<&2, List<&2, CommitMeta>>:
  prepend_parsed_meta(JsonAdapter.as_arr(head_item), parsed_tail)

# Decodes the metadata array; None on any bad item.
def parse_meta_list(meta_items: List<&2, Json.Val>) -> Maybe<&2, List<&2, CommitMeta>>:
  match meta_items:
    case Nil{}:
      Some{Nil{}}
    case Con{head_item, remaining_items}:
      prepend_meta_entry(head_item, parse_meta_list(remaining_items))

# Accepts only when re-serialization matches stored bytes.
def verify_commit_text(text_matches: Bool, +requested_identifier: String, +parent_list: List<&2, String>, +tree_text: String, +parsed_meta: List<&2, CommitMeta>) -> Maybe<&2, Commit>:
  match text_matches:
    case True{}:
      Some{Make{requested_identifier, parent_list, tree_text, 0n, parsed_meta, None{}}}
    case False{}:
      None{}

# Continues commit extraction once metadata decodes.
def finish_commit_meta(+requested_identifier: String, +stored_text: String, +parent_list: List<&2, String>, +tree_text: String, meta_maybe: Maybe<&2, List<&2, CommitMeta>>) -> Maybe<&2, Commit>:
  match meta_maybe:
    case None{}:
      None{}
    case Some{+parsed_meta}:
      verify_commit_text(String.eq(serialize_commit(parent_list, parsed_meta, tree_text), stored_text), requested_identifier, parent_list, tree_text, parsed_meta)

# Continues commit extraction once the meta items decode.
def finish_commit(+requested_identifier: String, +stored_text: String, +parent_list: List<&2, String>, +tree_text: String, meta_items_maybe: Maybe<&2, List<&2, Json.Val>>) -> Maybe<&2, Commit>:
  match meta_items_maybe:
    case None{}:
      None{}
    case Some{meta_items}:
      finish_commit_meta(requested_identifier, stored_text, parent_list, tree_text, parse_meta_list(meta_items))

# Unwraps the meta array, then continues.
def finish_meta_array(+requested_identifier: String, +stored_text: String, +parent_list: List<&2, String>, +tree_text: String, meta_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, Commit>:
  match meta_maybe:
    case None{}:
      None{}
    case Some{meta_json}:
      finish_commit(requested_identifier, stored_text, parent_list, tree_text, JsonAdapter.as_arr(meta_json))

# Unwraps the tree field as text.
def tree_maybe_as_text(tree_maybe: Maybe<&2, Json.Val>) -> Maybe<&2, String>:
  match tree_maybe:
    case None{}:
      None{}
    case Some{tree_json}:
      JsonAdapter.as_str(tree_json)

# Continues commit extraction once the tree text decodes.
def extract_commit_meta(+requested_identifier: String, +stored_text: String, +parent_list: List<&2, String>, tree_text_maybe: Maybe<&2, String>, +document: Json.Val) -> Maybe<&2, Commit>:
  match tree_text_maybe:
    case None{}:
      None{}
    case Some{tree_text}:
      finish_meta_array(requested_identifier, stored_text, parent_list, tree_text, JsonAdapter.get_field(document, "meta"))

# Continues commit extraction once parents decode.
def extract_commit_tree(+requested_identifier: String, +stored_text: String, parent_strings_maybe: Maybe<&2, List<&2, String>>, tree_maybe: Maybe<&2, Json.Val>, +document: Json.Val) -> Maybe<&2, Commit>:
  match parent_strings_maybe:
    case None{}:
      None{}
    case Some{parent_list}:
      extract_commit_meta(requested_identifier, stored_text, parent_list, tree_maybe_as_text(tree_maybe), document)

# Unwraps the parent items, then continues.
def extract_parents_items(+requested_identifier: String, +stored_text: String, items_maybe: Maybe<&2, List<&2, Json.Val>>, +document: Json.Val) -> Maybe<&2, Commit>:
  match items_maybe:
    case None{}:
      None{}
    case Some{parent_items}:
      extract_commit_tree(requested_identifier, stored_text, ContentObject.extract_each_string(parent_items), JsonAdapter.get_field(document, "tree"), document)

# Unwraps the parents field, then continues.
def extract_parents_array(+requested_identifier: String, +stored_text: String, parents_maybe: Maybe<&2, Json.Val>, +document: Json.Val) -> Maybe<&2, Commit>:
  match parents_maybe:
    case None{}:
      None{}
    case Some{parents_json}:
      extract_parents_items(requested_identifier, stored_text, JsonAdapter.as_arr(parents_json), document)

# Reads the parents field of the document.
def extract_commit_parents(+requested_identifier: String, +stored_text: String, +document: Json.Val) -> Maybe<&2, Commit>:
  extract_parents_array(requested_identifier, stored_text, JsonAdapter.get_field(document, "parents"), document)

# Builds the commit from parsed JSON; None on malformed input.
def commit_from_parse(requested_identifier: String, stored_text: String, parse_result: Maybe<&2, Json.Val>) -> Maybe<&2, Commit>:
  match parse_result:
    case None{}:
      None{}
    case Some{+document}:
      extract_commit_parents(requested_identifier, stored_text, document)

# Parses stored commit text.
def parse_commit_text(requested_identifier: String, +stored_text: String) -> Maybe<&2, Commit>:
  commit_from_parse(requested_identifier, stored_text, JsonAdapter.parse_text(stored_text))

# Parses loaded text; missing storage reads as None.
def parse_commit(requested_identifier: String, stored_maybe: Maybe<&2, String>) -> Maybe<&2, Commit>:
  match stored_maybe:
    case None{}:
      None{}
    case Some{stored_text}:
      parse_commit_text(requested_identifier, stored_text)

# Loads and verifies a commit by identifier.
def load_commit(+requested_identifier: String) -> MyLsmStore.Sess<&2, Maybe<&2, Commit>>:
  do MyLsmStore.Sess<&2, Maybe<&2, Commit>>:
    stored_maybe : Maybe<&2, String> <- MyLsmStore.sget(LogicalKey.build_commit_storage_key(requested_identifier))
    return parse_commit(requested_identifier, stored_maybe)

# Empty Sess result of unit type.
def empty_unit() -> MyLsmStore.Sess<&2, Unit>:
  do MyLsmStore.Sess<&2, Unit>:
    return Unit{}

# Empty Sess result of entry-list type.
def empty_pair_list() -> MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
  do MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
    return Nil{}

# Empty Sess result of tree type.
def empty_tree_maybe() -> MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
  do MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
    return None{}

# Serializes, hashes and stores a commit.
def persist_commit(+parent_commit_identifiers: List<&2, String>, +metadata: List<&2, CommitMeta>, +tree_hash_value: String) -> MyLsmStore.Sess<&2, Commit>:
  do MyLsmStore.Sess<&2, Commit>:
    +commit_text : String = serialize_commit(parent_commit_identifiers, metadata, tree_hash_value)
    +commit_identifier : String = ContentHash.compute_sha256_hex(commit_text)
    stored_unit : Unit <- MyLsmStore.sput(LogicalKey.build_commit_storage_key(commit_identifier), commit_text)
    return Make{commit_identifier, parent_commit_identifiers, tree_hash_value, 0n, metadata, None{}}

# Hashes and stores a merged entry list as a tree.
def persist_tree(+merged_entries: List<&2, Reading.ChainEntry>) -> MyLsmStore.Sess<&2, String>:
  do MyLsmStore.Sess<&2, String>:
    +tree_hash_value : String = StateTree.compute_tree_hash(merged_entries)
    stored_unit : Unit <- MyLsmStore.sput(LogicalKey.build_tree_storage_key(tree_hash_value), StateTree.serialize_tree(merged_entries, tree_hash_value))
    return tree_hash_value

# Writes one version-index entry per merged entry.
def write_each_index(merged_entries: List<&2, Reading.ChainEntry>, +commit_value: Commit) -> MyLsmStore.Sess<&2, Unit>:
  match merged_entries:
    case Nil{}:
      empty_unit()
    case Con{+head_entry, remaining_entries}:
      do MyLsmStore.Sess<&2, Unit>:
        head_unit : Unit <- MyLsmStore.sput(LogicalKey.build_version_index_key(Reading.entry_key_of(head_entry), commit_identifier_of(commit_value)), Reading.entry_value_of(head_entry))
        tail_unit : Unit <- write_each_index(remaining_entries, commit_value)
        return tail_unit

# Removes staged keys consumed by the commit.
def clear_stage_keys(+session_identifier: String, merged_entries: List<&2, Reading.ChainEntry>) -> MyLsmStore.Sess<&2, Unit>:
  match merged_entries:
    case Nil{}:
      empty_unit()
    case Con{head_entry, remaining_entries}:
      do MyLsmStore.Sess<&2, Unit>:
        cleared_unit : Unit <- MyLsmStore.sdel(LogicalKey.build_stage_storage_key_combined(session_identifier, Reading.entry_key_of(head_entry)))
        cleared_tail : Unit <- clear_stage_keys(session_identifier, remaining_entries)
        return cleared_tail

# Writes the index and clears the stage in sequence.
def persist_index_and_clear(+session_identifier: String, +merged_entries: List<&2, Reading.ChainEntry>, +commit_value: Commit) -> MyLsmStore.Sess<&2, Unit>:
  do MyLsmStore.Sess<&2, Unit>:
    indexed_unit : Unit <- write_each_index(merged_entries, commit_value)
    cleared_unit : Unit <- clear_stage_keys(session_identifier, merged_entries)
    index_cleared_unit : Unit <- MyLsmStore.sdel(Staging.stage_index_key(session_identifier))
    return index_cleared_unit

# Persists tree, commit and index, then clears the stage.
def materialize_commit(+session_identifier: String, +parent_commit_identifiers: List<&2, String>, metadata: List<&2, CommitMeta>, +merged_entries: List<&2, Reading.ChainEntry>) -> MyLsmStore.Sess<&2, Commit>:
  do MyLsmStore.Sess<&2, Commit>:
    +tree_hash_value : String <- persist_tree(merged_entries)
    +commit_value : Commit <- persist_commit(parent_commit_identifiers, metadata, tree_hash_value)
    cleared_unit : Unit <- persist_index_and_clear(session_identifier, merged_entries, commit_value)
    return commit_value

# Parses loaded tree text.
def parse_tree_text(tree_hash_value: String, tree_maybe: Maybe<&2, String>) -> Maybe<&2, StateTree.StateTreeNode>:
  match tree_maybe:
    case None{}:
      None{}
    case Some{tree_text}:
      StateTree.parse_tree_document(tree_text)

# Loads a tree by hash.
def load_tree_text(+tree_hash_value: String) -> MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
  do MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
    tree_maybe : Maybe<&2, String> <- MyLsmStore.sget(LogicalKey.build_tree_storage_key(tree_hash_value))
    return parse_tree_text(tree_hash_value, tree_maybe)

# Loads the tree a commit points at.
def load_tree_by_commit(commit_maybe: Maybe<&2, Commit>) -> MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
  match commit_maybe:
    case None{}:
      empty_tree_maybe()
    case Some{found_commit}:
      load_tree_text(commit_tree_of(found_commit))

# Reads the tree for a commit identifier.
def read_tree_at(+commit_identifier: String) -> MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
  do MyLsmStore.Sess<&2, Maybe<&2, StateTree.StateTreeNode>>:
    commit_maybe : Maybe<&2, Commit> <- load_commit(commit_identifier)
    loaded_tree : Maybe<&2, StateTree.StateTreeNode> <- load_tree_by_commit(commit_maybe)
    return loaded_tree

# Missing base trees read as empty.
def base_or_empty(tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> List<&2, Reading.ChainEntry>:
  match tree_maybe:
    case None{}:
      Nil{}
    case Some{parent_tree}:
      StateTree.tree_entries(parent_tree)

# Loads the first parent entries.
def load_parent_tree(head_parent: String) -> MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
  do MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
    tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- read_tree_at(head_parent)
    return base_or_empty(tree_maybe)

# Loads base entries; root commits start empty.
def load_base_entries(parent_commit_identifiers: List<&2, String>) -> MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
  match parent_commit_identifiers:
    case Nil{}:
      empty_pair_list()
    case Con{head_parent, remaining_parents}:
      load_parent_tree(head_parent)

# Skips missing staged values, keeps present ones.
def prepend_pair_maybe(+head_key: String, head_value_maybe: Maybe<&2, String>, tail_pairs: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match head_value_maybe:
    case None{}:
      tail_pairs
    case Some{head_value}:
      Con{Reading.make_entry(head_key, head_value), tail_pairs}

# Loads one staged value and prepends it.
def prepend_loaded_pair(+session_identifier: String, +head_key: String, tail_action: MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>) -> MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
  do MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
    head_value_maybe : Maybe<&2, String> <- MyLsmStore.sget(LogicalKey.build_stage_storage_key_combined(session_identifier, head_key))
    tail_pairs : List<&2, Reading.ChainEntry> <- tail_action
    return prepend_pair_maybe(head_key, head_value_maybe, tail_pairs)

# Loads every staged key in the manifest.
def load_each_pair(+session_identifier: String, staged_keys: List<&2, String>) -> MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
  match staged_keys:
    case Nil{}:
      empty_pair_list()
    case Con{head_key, remaining_keys}:
      prepend_loaded_pair(session_identifier, head_key, load_each_pair(session_identifier, remaining_keys))

# Collects the session staged pairs.
def collect_staged_pairs(+session_identifier: String) -> MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
  do MyLsmStore.Sess<&2, List<&2, Reading.ChainEntry>>:
    staged_keys : List<&2, String> <- Staging.load_stage_index(session_identifier)
    collected_pairs : List<&2, Reading.ChainEntry> <- load_each_pair(session_identifier, staged_keys)
    return collected_pairs

# Materializes stage plus base into a new commit.
def create_commit(+session_identifier: String, +parent_commit_identifiers: List<&2, String>, metadata: List<&2, CommitMeta>) -> MyLsmStore.Sess<&2, Commit>:
  do MyLsmStore.Sess<&2, Commit>:
    staged_pairs : List<&2, Reading.ChainEntry> <- collect_staged_pairs(session_identifier)
    base_entries : List<&2, Reading.ChainEntry> <- load_base_entries(parent_commit_identifiers)
    finished_commit : Commit <- materialize_commit(session_identifier, parent_commit_identifiers, metadata, StateTree.merge_sorted_entries(staged_pairs, base_entries))
    return finished_commit

# Versioned reads walk the first-parent chain with Nat fuel; unknown
# commits contribute "" links that never match a real index key.
def commit_parents_of(commit_value: Commit) -> List<&2, String>:
  match commit_value:
    case Make{commit_identifier, parent_commit_identifiers, tree_hash, timestamp, metadata, certificate_hash}:
      parent_commit_identifiers

# Empty Sess result of string-list type.
def empty_string_list() -> MyLsmStore.Sess<&2, List<&2, String>>:
  do MyLsmStore.Sess<&2, List<&2, String>>:
    return Nil{}

# Empty Sess result of entry type.
def empty_entry_maybe() -> MyLsmStore.Sess<&2, Maybe<&2, Reading.ChainEntry>>:
  do MyLsmStore.Sess<&2, Maybe<&2, Reading.ChainEntry>>:
    return None{}

# Empty Sess result of string type.
def empty_string_maybe() -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  do MyLsmStore.Sess<&2, Maybe<&2, String>>:
    return None{}

# Heads the parent list; root commits yield empty.
def first_parent_name(parent_identifiers: List<&2, String>) -> String:
  match parent_identifiers:
    case Nil{}:
      ""
    case Con{head_parent, remaining_parents}:
      head_parent

# Heads the parent list; unknown commits yield empty.
def first_parent_text(commit_maybe: Maybe<&2, Commit>) -> String:
  match commit_maybe:
    case None{}:
      ""
    case Some{found_commit}:
      first_parent_name(commit_parents_of(found_commit))

# Walks first-parents with fuel; newest first.
def walk_commit_chain(remaining_fuel: Nat, +commit_identifier: String) -> MyLsmStore.Sess<&2, List<&2, String>>:
  match remaining_fuel:
    case 0n:
      empty_string_list()
    case 1n+fuel_left:
      do MyLsmStore.Sess<&2, List<&2, String>>:
        commit_maybe : Maybe<&2, Commit> <- load_commit(commit_identifier)
        tail_chain : List<&2, String> <- walk_commit_chain(fuel_left, first_parent_text(commit_maybe))
        return Con{commit_identifier, tail_chain}

# A stored value wins; otherwise the tail result.
def decide_search_hit(stored_maybe: Maybe<&2, String>, +lookup_key: String, tail_result: Maybe<&2, Reading.ChainEntry>) -> Maybe<&2, Reading.ChainEntry>:
  match stored_maybe:
    case None{}:
      tail_result
    case Some{stored_value}:
      Some{Reading.make_entry(lookup_key, stored_value)}

# Searches the ancestor chain newest-first.
def search_chain_entries(ancestor_chain: List<&2, String>, +namespace_name: String, +record_identifier: String) -> MyLsmStore.Sess<&2, Maybe<&2, Reading.ChainEntry>>:
  match ancestor_chain:
    case Nil{}:
      empty_entry_maybe()
    case Con{head_commit, remaining_commits}:
      do MyLsmStore.Sess<&2, Maybe<&2, Reading.ChainEntry>>:
        +lookup_key : String = Reading.encode_lookup_key(namespace_name, record_identifier)
        stored_maybe : Maybe<&2, String> <- MyLsmStore.sget(LogicalKey.build_version_index_key(lookup_key, head_commit))
        tail_result : Maybe<&2, Reading.ChainEntry> <- search_chain_entries(remaining_commits, namespace_name, record_identifier)
        return decide_search_hit(stored_maybe, lookup_key, tail_result)

# Projects the payload out of a loaded object.
def payload_or_empty(loaded_maybe: Maybe<&2, ContentObject.ContentObject>) -> Maybe<&2, String>:
  match loaded_maybe:
    case None{}:
      None{}
    case Some{loaded_object}:
      Some{ContentObject.object_payload_of(loaded_object)}

# Loads an object payload by content hash.
def load_object_payload(+value_hash: String) -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  do MyLsmStore.Sess<&2, Maybe<&2, String>>:
    loaded_maybe : Maybe<&2, ContentObject.ContentObject> <- ContentObject.load_content_object(value_hash)
    return payload_or_empty(loaded_maybe)

# Tombstones read as absent; hashes load payloads.
def decide_resolve_value(is_tombstone: Bool, +stored_value: String) -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  match is_tombstone:
    case True{}:
      empty_string_maybe()
    case False{}:
      load_object_payload(stored_value)

# Resolves one stored index value.
def resolve_entry_value(+stored_value: String) -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  decide_resolve_value(String.eq(stored_value, "TOMBSTONE"), stored_value)

# Resolves a found chain entry to its payload.
def resolve_found_entry(found_maybe: Maybe<&2, Reading.ChainEntry>) -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  match found_maybe:
    case None{}:
      empty_string_maybe()
    case Some{found_entry}:
      resolve_entry_value(Reading.entry_value_of(found_entry))

# Reads a namespaced value at a commit.
def read_value_at(+namespace_name: String, +record_identifier: String, +commit_identifier: String) -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  do MyLsmStore.Sess<&2, Maybe<&2, String>>:
    ancestor_chain : List<&2, String> <- walk_commit_chain(10000n, commit_identifier)
    found_entry : Maybe<&2, Reading.ChainEntry> <- search_chain_entries(ancestor_chain, namespace_name, record_identifier)
    resolved_value : Maybe<&2, String> <- resolve_found_entry(found_entry)
    return resolved_value
