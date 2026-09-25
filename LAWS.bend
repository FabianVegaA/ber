import Base
import ./src/Reading.bend as Reading

# LAW 1 (v0.1): deterministic versioned read.
# Shadowed (older duplicate-key) entries never affect a read: looking up in
# the normalized chain answers exactly what looking up in the raw chain answers.
# Physical layout (compaction order, duplicate accumulation) is invisible.
law read_determinism:
  for namespace_name: String
  for record_identifier: String
  for ancestor_chain: List<&2, Reading.ChainEntry>
  {Reading.lookup_in_chain(namespace_name, record_identifier, Reading.normalize_chain(ancestor_chain)) == Reading.lookup_in_chain(namespace_name, record_identifier, ancestor_chain) : Maybe<&2, String>}
