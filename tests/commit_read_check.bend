import Base
import ../ber.bend as Ber
import ../src/Store.bend as Store
import ../src/Value.bend as Value
import ../src/Reading.bend as Reading
import ../src/StateTree.bend as StateTree
import ../src/LogicalKey.bend as LogicalKey

# IO harness: linear commit materializes stage into tree/commit/index and
# the tree reads back with the expected entries.

def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def count_tree_entries(entries: List<&2, Reading.ChainEntry>) -> Nat:
  match entries:
    case Nil{}:
      0n
    case Con{head_entry, remaining_entries}:
      Nat.add(1n, count_tree_entries(remaining_entries))

def is_count_one(entry_count: Nat) -> Bool:
  match entry_count:
    case 0n:
      False{}
    case 1n+remaining_count:
      match remaining_count:
        case 0n:
          True{}
        case _:
          False{}

def entries_or_empty(tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> List<&2, Reading.ChainEntry>:
  match tree_maybe:
    case None{}:
      Nil{}
    case Some{found_tree}:
      StateTree.tree_entries(found_tree)

def count_flag(check_name: String, tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  flag_text(check_name, is_count_one(count_tree_entries(entries_or_empty(tree_maybe))))

def first_entry_key(entries: List<&2, Reading.ChainEntry>) -> Maybe<&2, String>:
  match entries:
    case Nil{}:
      None{}
    case Con{head_entry, remaining_entries}:
      Some{Reading.entry_key_of(head_entry)}

def first_entry_value(entries: List<&2, Reading.ChainEntry>) -> Maybe<&2, String>:
  match entries:
    case Nil{}:
      None{}
    case Con{head_entry, remaining_entries}:
      Some{Reading.entry_value_of(head_entry)}

def key_flag_value(key_maybe: Maybe<&2, String>) -> String:
  match key_maybe:
    case None{}:
      "first-key-ok: FAIL"
    case Some{found_key}:
      flag_text("first-key-ok", String.eq(found_key, "ledger/record_first"))

def key_flag(tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  key_flag_value(first_entry_key(entries_or_empty(tree_maybe)))

def values_differ_final(first_value: String, second_value_maybe: Maybe<&2, String>) -> String:
  match second_value_maybe:
    case None{}:
      "values-differ: FAIL"
    case Some{second_value}:
      flag_text("values-differ", Bool.not(String.eq(first_value, second_value)))

def values_differ_texts(first_value_maybe: Maybe<&2, String>, second_value_maybe: Maybe<&2, String>) -> String:
  match first_value_maybe:
    case None{}:
      "values-differ: FAIL"
    case Some{first_value}:
      values_differ_final(first_value, second_value_maybe)

def values_differ_second(second_maybe: Maybe<&2, StateTree.StateTreeNode>, first_entries: List<&2, Reading.ChainEntry>) -> String:
  match second_maybe:
    case None{}:
      "values-differ: FAIL"
    case Some{second_tree}:
      values_differ_texts(first_entry_value(first_entries), first_entry_value(StateTree.tree_entries(second_tree)))

def values_differ_flag(first_maybe: Maybe<&2, StateTree.StateTreeNode>, second_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  match first_maybe:
    case None{}:
      "values-differ: FAIL"
    case Some{first_tree}:
      values_differ_second(second_maybe, StateTree.tree_entries(first_tree))

def immutable_second(first_hash: String, again_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  match again_maybe:
    case None{}:
      "first-immutable: FAIL"
    case Some{again_tree}:
      flag_text("first-immutable", String.eq(first_hash, StateTree.tree_hash_of(again_tree)))

def immutable_flag(first_maybe: Maybe<&2, StateTree.StateTreeNode>, again_maybe: Maybe<&2, StateTree.StateTreeNode>) -> String:
  match first_maybe:
    case None{}:
      "first-immutable: FAIL"
    case Some{first_tree}:
      immutable_second(StateTree.tree_hash_of(first_tree), again_maybe)

def scenario_texts() -> Store.Op<&2, List<&2, String>>:
  do Store.Op<&2, List<&2, String>>:
    +first_identifier : String <- Ber.commit_value("session_first", "ledger", "record_first", Value.Text{"first_version"}, Nil{})
    +first_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- Ber.read_tree_at(first_identifier)
    +second_identifier : String <- Ber.commit_value("session_first", "ledger", "record_first", Value.Text{"second_version"}, Con{first_identifier, Nil{}})
    +second_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- Ber.read_tree_at(second_identifier)
    again_tree_maybe : Maybe<&2, StateTree.StateTreeNode> <- Ber.read_tree_at(first_identifier)
    return Con{count_flag("first-count-one", first_tree_maybe), Con{key_flag(first_tree_maybe), Con{count_flag("second-count-one", second_tree_maybe), Con{values_differ_flag(first_tree_maybe, second_tree_maybe), Con{immutable_flag(first_tree_maybe, again_tree_maybe), Nil{}}}}}}

def join_lines(text_lines: List<&2, String>) -> String:
  match text_lines:
    case Nil{}:
      ""
    case Con{head_text, remaining_texts}:
      head_text ++ "\n" ++ join_lines(remaining_texts)

def print_scenario_result(result_pair: Store.Handle & List<&2, String>) -> IO(Unit):
  match result_pair:
    case (unused_store, text_lines):
      IO.print(join_lines(text_lines))

def main() -> IO(Unit):
  opened_store : Store.Handle = Store.open_store("commit-check")
  print_scenario_result(Store.run_op(&2, List<&2, String>, opened_store, scenario_texts()))
