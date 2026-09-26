import Base

# Logical keys and the physical MyLSM key layout. All keys are ASCII with
# "/" separators so prefix scan stays possible at the storage layer.
type LogicalKey is Data:
  Make{namespace_name: String, record_identifier: String}

# Renders a key as "namespace/record".
def encode_logical_key(logical_key: LogicalKey) -> String:
  match logical_key:
    case Make{namespace_name, record_identifier}:
      namespace_name ++ "/" ++ record_identifier

# Addresses a content-addressed object by its hash.
def build_object_storage_key(content_hash: String) -> String:
  "object/" ++ content_hash

# Addresses a persisted state tree by its hash.
def build_tree_storage_key(tree_hash_value: String) -> String:
  "tree/" ++ tree_hash_value

# Addresses a persisted commit by its identifier.
def build_commit_storage_key(commit_identifier: String) -> String:
  "commit/" ++ commit_identifier

# Addresses one versioned index entry: value hash or TOMBSTONE.
def build_index_storage_key(namespace_name: String, record_identifier: String, commit_identifier: String) -> String:
  "index/" ++ namespace_name ++ "/" ++ record_identifier ++ "/" ++ commit_identifier

# Addresses one uncommitted staged value.
def build_stage_storage_key(session_identifier: String, namespace_name: String, record_identifier: String) -> String:
  "stage/" ++ session_identifier ++ "/" ++ namespace_name ++ "/" ++ record_identifier

# Same version-index layout for callers holding "namespace/record" as one string.
def build_version_index_key(combined_key: String, commit_identifier: String) -> String:
  "index/" ++ combined_key ++ "/" ++ commit_identifier

# Same stage layout for callers holding "namespace/record" as one string.
def build_stage_storage_key_combined(session_identifier: String, combined_key: String) -> String:
  "stage/" ++ session_identifier ++ "/" ++ combined_key

# Scans for the first "/"; the head match is on a pattern-bound variable.
def split_scan(remaining_text: String, namespace_accum: String) -> LogicalKey:
  match remaining_text:
    case SNil{}:
      Make{namespace_accum, ""}
    case SCon{head_char, remaining_chars}:
      match head_char:
        case '/':
          Make{namespace_accum, remaining_chars}
        case _:
          split_scan(remaining_chars, String.append(namespace_accum, SCon{head_char, SNil{}}))

# Inverse of encode_logical_key: splits at the FIRST "/".
def split_combined_key(combined_key: String) -> LogicalKey:
  split_scan(combined_key, "")
