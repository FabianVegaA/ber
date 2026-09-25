import Base

# Pure chain-reading cores. Laws in LAWS.bend quantify over THESE functions,
# never over IO/Sess actions. The Sess shells (Task 4+) only build the
# ancestor_chain (by walking parent_commit_identifiers) and call lookup_in_chain.
#
# ORDER MATTERS: a def may only call defs declared ABOVE it (no forward
# references, no mutual recursion). Helpers come first, entry points last.

# NOTE: entries are NOT String & String pairs — a & pair defaults to kind Type,
# which List<&2, _> rejects. A named Data constructor carries the kind.
type ChainEntry is Data:
  Entry{entry_key: String, entry_value: String}

def encode_lookup_key(+namespace_name: String, +record_identifier: String) -> String:
  namespace_name ++ "/" ++ record_identifier

def pick_match(key_matches: Bool, stored_value: String, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match key_matches:
    case True{}:
      Some{stored_value}
    case False{}:
      fallback

# Most-recent-wins: the head of the chain is the newest commit.
def lookup_in_chain(+namespace_name: String, +record_identifier: String, ancestor_chain: List<&2, ChainEntry>) -> Maybe<&2, String>:
  match ancestor_chain:
    case Nil{}:
      None{}
    case Con{head_entry, remaining_chain}:
      match head_entry:
        case Entry{entry_key, entry_value}:
          pick_match(String.eq(entry_key, encode_lookup_key(namespace_name, record_identifier)), entry_value, lookup_in_chain(namespace_name, record_identifier, remaining_chain))

def drop_tombstone(is_tombstone: Bool, stored_value: String) -> Maybe<&2, String>:
  match is_tombstone:
    case True{}:
      None{}
    case False{}:
      Some{stored_value}

def resolve_tombstone(maybe_value: Maybe<&2, String>) -> Maybe<&2, String>:
  match maybe_value:
    case None{}:
      None{}
    case Some{+stored_value}:
      drop_tombstone(String.eq(stored_value, "TOMBSTONE"), stored_value)

def drop_or_keep(is_match: Bool, stored_key: String, stored_value: String, filtered_tail: List<&2, ChainEntry>) -> List<&2, ChainEntry>:
  match is_match:
    case True{}:
      filtered_tail
    case False{}:
      Con{Entry{stored_key, stored_value}, filtered_tail}

def filter_entry(head_entry: ChainEntry, filtered_tail: List<&2, ChainEntry>, target_key: String) -> List<&2, ChainEntry>:
  match head_entry:
    case Entry{+entry_key, +entry_value}:
      drop_or_keep(String.eq(entry_key, target_key), entry_key, entry_value, filtered_tail)

def remove_key_matches(+target_key: String, ancestor_chain: List<&2, ChainEntry>) -> List<&2, ChainEntry>:
  match ancestor_chain:
    case Nil{}:
      Nil{}
    case Con{head_entry, remaining_chain}:
      filter_entry(head_entry, remove_key_matches(target_key, remaining_chain), target_key)

def attach_head(head_entry: ChainEntry, normalized_tail: List<&2, ChainEntry>) -> List<&2, ChainEntry>:
  match head_entry:
    case Entry{+entry_key, +entry_value}:
      Con{Entry{entry_key, entry_value}, remove_key_matches(entry_key, normalized_tail)}

# Drops older duplicates: keeps the FIRST (newest) occurrence of each key.
# Law read_determinism: shadowed entries never affect a read.
def normalize_chain(ancestor_chain: List<&2, ChainEntry>) -> List<&2, ChainEntry>:
  match ancestor_chain:
    case Nil{}:
      Nil{}
    case Con{head_entry, remaining_chain}:
      attach_head(head_entry, normalize_chain(remaining_chain))

# Shared vocabulary: other modules build/inspect ChainEntry through THESE
# (foreign-module constructor patterns are avoided on purpose).
def make_entry(entry_key: String, entry_value: String) -> ChainEntry:
  Entry{entry_key, entry_value}

def entry_key_of(chain_entry: ChainEntry) -> String:
  match chain_entry:
    case Entry{entry_key, entry_value}:
      entry_key

def entry_value_of(chain_entry: ChainEntry) -> String:
  match chain_entry:
    case Entry{entry_key, entry_value}:
      entry_value
