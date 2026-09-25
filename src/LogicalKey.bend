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
