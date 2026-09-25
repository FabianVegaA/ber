import Base
import ./src/Reading.bend as Reading

# LAW 1, v0.1 instances: empty-history behavior, proven below (green gate).
# Each pins a base case against regressions; none branches on key comparison,
# so all hold by computation ({==}).
#
# The GENERAL shadow-invariance law
#   lookup(ns, id, normalize(chain)) == lookup(ns, id, chain)
# is PROOF-DEFERRED (see spec): its False-branch needs String.eq
# transitivity/symmetry, a characterization library neither Base nor
# bend-lemmas ships. It becomes the first law of the v0.2 lemma-library epic.
law empty_chain_reads_none:
  for namespace_name: String
  for record_identifier: String
  {Reading.lookup_in_chain(namespace_name, record_identifier, Nil{}) == None{} : Maybe<&2, String>}

law resolve_none_stable:
  {Reading.resolve_tombstone(None{}) == None{} : Maybe<&2, String>}

law normalize_nil_stable:
  {Reading.normalize_chain(Nil{}) == Nil{} : List<&2, Reading.ChainEntry>}
