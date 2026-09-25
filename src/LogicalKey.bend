import Base

type LogicalKey is Data:
  Make{namespace_name: String, record_identifier: String}

def encode_logical_key(logical_key: LogicalKey) -> String:
  match logical_key:
    case Make{namespace_name, record_identifier}:
      namespace_name ++ "/" ++ record_identifier

def build_object_storage_key(content_hash: String) -> String:
  "object/" ++ content_hash

def build_tree_storage_key(tree_hash_value: String) -> String:
  "tree/" ++ tree_hash_value

def build_commit_storage_key(commit_identifier: String) -> String:
  "commit/" ++ commit_identifier

def build_index_storage_key(namespace_name: String, record_identifier: String, commit_identifier: String) -> String:
  "index/" ++ namespace_name ++ "/" ++ record_identifier ++ "/" ++ commit_identifier

def build_stage_storage_key(session_identifier: String, namespace_name: String, record_identifier: String) -> String:
  "stage/" ++ session_identifier ++ "/" ++ namespace_name ++ "/" ++ record_identifier

# Combined-key spellings (same layout, for code holding "namespace/record" as one string).
def build_version_index_key(combined_key: String, commit_identifier: String) -> String:
  "index/" ++ combined_key ++ "/" ++ commit_identifier

def build_stage_storage_key_combined(session_identifier: String, combined_key: String) -> String:
  "stage/" ++ session_identifier ++ "/" ++ combined_key

# Inverse of encode_logical_key: splits at the FIRST "/".
# Nested match on the pattern-bound head_char (allowed: scrutinee is a
# pattern-bound variable, never a computed value).
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

def split_combined_key(combined_key: String) -> LogicalKey:
  split_scan(combined_key, "")
