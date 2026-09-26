import Base
import ./src/Store.bend as Store
import ./src/Value.bend as Value
import ./src/LogicalKey.bend as LogicalKey
import ./src/Staging.bend as Staging
import ./src/History.bend as History
import ./src/StateTree.bend as StateTree
import ./src/Comparison.bend as Comparison
import ./src/Merging.bend as Merging
import ./src/Certificate.bend as Certificate
import ./src/JsonAdapter.bend as JsonAdapter

# Public API of ber-core. Single import for consumers; Store carries the
# Op/Handle session types. Level 2 delegates expose full power with internal
# types visible; Level 1 composes the common paths into opaque String
# results. Values are multi-type (text, document, binary blob), never bare
# text; reports are human-readable Strings, never domain values.

# --- Level 2: domain delegates (1:1) ---

# Stages one value for later commit.
def put_record(+session_id: String, +namespace_name: String, +record_id: String, value: Value.Value) -> Store.Op<&2, LogicalKey.LogicalKey>:
  Staging.put_record(session_id, namespace_name, record_id, value)

# Stages a tombstone for later commit.
def delete_record(+session_id: String, +namespace_name: String, +record_id: String) -> Store.Op<&2, LogicalKey.LogicalKey>:
  Staging.delete_record(session_id, namespace_name, record_id)

# Materializes stage plus base into a new commit.
def create_commit(+session_id: String, +parent_ids: List<&2, String>, metadata: List<&2, History.CommitMeta>) -> Store.Op<&2, History.Commit>:
  History.create_commit(session_id, parent_ids, metadata)

# Reads a namespaced value at a commit.
def read_value_at(+namespace_name: String, +record_id: String, +commit_id: String) -> Store.Op<&2, Maybe<&2, Value.Value>>:
  History.read_value_at(namespace_name, record_id, commit_id)

# Reads the tree for a commit identifier.
def read_tree_at(+commit_id: String) -> Store.Op<&2, Maybe<&2, StateTree.StateTreeNode>>:
  History.read_tree_at(commit_id)

# Diffs two commits with hash pruning.
def compare_commits(+first_id: String, +second_id: String) -> Store.Op<&2, Comparison.CompareResult>:
  Comparison.compare_commits(first_id, second_id)

# Merges two commits by strategy name.
def merge_commits(+first_id: String, +second_id: String, +strategy_name: String) -> Store.Op<&2, Merging.MergeResult>:
  Merging.merge_commits(first_id, second_id, strategy_name)

# Verifies a merge certificate against stored trees.
def verify_certificate(+certificate: Merging.MergeCertificate) -> Store.Op<&2, Bool>:
  Certificate.verify_certificate(certificate)

# --- Level 1: composed operations (primary API) ---

# Stages a value and commits in one step; returns the new commit identifier.
def commit_value(+session_id: String, +namespace_name: String, +record_id: String, value: Value.Value, parents: List<&2, String>) -> Store.Op<&2, String>:
  do Store.Op<&2, String>:
    staged_key : LogicalKey.LogicalKey <- Staging.put_record(session_id, namespace_name, record_id, value)
    new_commit : History.Commit <- History.create_commit(session_id, parents, Nil{})
    return History.commit_identifier_of(new_commit)

# Stages a tombstone and commits in one step; returns the new commit identifier.
def remove_record(+session_id: String, +namespace_name: String, +record_id: String, parents: List<&2, String>) -> Store.Op<&2, String>:
  do Store.Op<&2, String>:
    staged_key : LogicalKey.LogicalKey <- Staging.delete_record(session_id, namespace_name, record_id)
    new_commit : History.Commit <- History.create_commit(session_id, parents, Nil{})
    return History.commit_identifier_of(new_commit)

# Renders one diff count line.
def render_compare_counts(+compare_result: Comparison.CompareResult) -> String:
  "added=" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(compare_result))) ++ " removed=" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(compare_result))) ++ " modified=" ++ Nat.show(List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(compare_result)))

# Diffs two commits and renders the counts.
def compare_summary(+first_id: String, +second_id: String) -> Store.Op<&2, String>:
  do Store.Op<&2, String>:
    compared : Comparison.CompareResult <- Comparison.compare_commits(first_id, second_id)
    return render_compare_counts(compared)

# Renders a verified merge; failed verification is unprovable.
def decide_verified_text(verified_ok: Bool, +commit_id: String) -> String:
  match verified_ok:
    case True{}:
      "merged:" ++ commit_id
    case False{}:
      "unprovable:verify-failed"

# Verifies a successful merge and renders the verdict.
def verify_successful_merge(+resulting_commit: History.Commit, +certificate: Merging.MergeCertificate) -> Store.Op<&2, String>:
  do Store.Op<&2, String>:
    verified_ok : Bool <- Certificate.verify_certificate(certificate)
    return decide_verified_text(verified_ok, History.commit_identifier_of(resulting_commit))

# Renders a merge outcome; conflicts count keys, unprovable names the reason.
def verify_merge_outcome(merge_result: Merging.MergeResult) -> Store.Op<&2, String>:
  match merge_result:
    case Merging.MergeSuccess{resulting_commit, certificate}:
      verify_successful_merge(resulting_commit, certificate)
    case Merging.MergeConflict{conflicting_keys}:
      Store.Op.pure(&2, String, "conflict:" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, conflicting_keys)))
    case Merging.MergeUnprovable{reason}:
      Store.Op.pure(&2, String, "unprovable:" ++ reason)

# Merges union-disjoint and verifies; renders merged, conflict or unprovable.
def merge_and_verify(+first_id: String, +second_id: String) -> Store.Op<&2, String>:
  do Store.Op<&2, String>:
    merged_result : Merging.MergeResult <- Merging.merge_commits(first_id, second_id, "union-disjoint")
    verify_merge_outcome(merged_result)

# Renders one found value; blobs show size, never raw bytes.
def render_found_value(found_value: Value.Value) -> String:
  match found_value:
    case Value.Text{content}:
      "read=" ++ content
    case Value.Object{document}:
      "read=" ++ JsonAdapter.encode_canonical(document)
    case Value.Blob{byte_list}:
      "read=<blob " ++ Nat.show(List.length(&2, U32, byte_list)) ++ " bytes>"

# Renders a read; absent reads as absent.
def render_read_value(read_value: Maybe<&2, Value.Value>) -> String:
  match read_value:
    case None{}:
      "read=absent"
    case Some{found_value}:
      render_found_value(found_value)

# Renders a read plus diff and merge lines; the demo report shape.
def format_report(read_value: Maybe<&2, Value.Value>, +diff_line: String, +merge_line: String) -> String:
  render_read_value(read_value) ++ "\n" ++ diff_line ++ "\n" ++ merge_line
