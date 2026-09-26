import Base
import ../src/Reading.bend as Reading
import ../src/Comparison.bend as Comparison
import ../src/LogicalKey.bend as LogicalKey

# IO harness: fanned and sequential compare agree on counts on small inputs.



def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def gen_first_entries(remaining: Nat, accum_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match remaining:
    case 0n:
      accum_entries
    case 1n++rest_count:
      gen_first_entries(rest_count, Con{Reading.make_entry("bench/key-" ++ Nat.show(rest_count), "version-" ++ Nat.show(rest_count)), accum_entries})

def changed_suffix(is_changed: Bool, +remaining: Nat) -> String:
  match is_changed:
    case True{}:
      "version-" ++ Nat.show(remaining) ++ "-changed"
    case False{}:
      "version-" ++ Nat.show(remaining)

def gen_second_entries(remaining: Nat, accum_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match remaining:
    case 0n:
      accum_entries
    case 1n++rest_count:
      gen_second_entries(rest_count, Con{Reading.make_entry("bench/key-" ++ Nat.show(rest_count), changed_suffix(Nat.is_eq(Nat.mod(rest_count, 5n), 0n), rest_count)), accum_entries})

def gen_extra_entries(remaining: Nat, accum_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match remaining:
    case 0n:
      accum_entries
    case 1n++rest_count:
      gen_extra_entries(rest_count, Con{Reading.make_entry("bench/extra-" ++ Nat.show(rest_count), "extra-version"), accum_entries})

def count_added(compare_result: Comparison.CompareResult) -> Nat:
  List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(compare_result))

def count_removed(compare_result: Comparison.CompareResult) -> Nat:
  List.length(&2, LogicalKey.LogicalKey, Comparison.removed_keys_of(compare_result))

def count_modified(compare_result: Comparison.CompareResult) -> Nat:
  List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(compare_result))

def agree_modified_text(modified_equal: Bool) -> String:
  match modified_equal:
    case True{}:
      "paths-agree: PASS"
    case False{}:
      "paths-agree: FAIL"

def agree_removed_text(removed_equal: Bool, modified_equal: Bool) -> String:
  match removed_equal:
    case True{}:
      agree_modified_text(modified_equal)
    case False{}:
      "paths-agree: FAIL"

def counts_agree_text(added_equal: Bool, removed_equal: Bool, modified_equal: Bool) -> String:
  match added_equal:
    case True{}:
      agree_removed_text(removed_equal, modified_equal)
    case False{}:
      "paths-agree: FAIL"

def counts_agree_result(+sequential_result: Comparison.CompareResult, +fanned_result: Comparison.CompareResult) -> String:
  counts_agree_text(Nat.is_eq(count_added(sequential_result), count_added(fanned_result)), Nat.is_eq(count_removed(sequential_result), count_removed(fanned_result)), Nat.is_eq(count_modified(sequential_result), count_modified(fanned_result)))

def report_counts(+first_entries: List<&2, Reading.ChainEntry>, +second_entries: List<&2, Reading.ChainEntry>) -> IO(Unit):
  +sequential_result : Comparison.CompareResult = Comparison.compare_sorted_entries(first_entries, second_entries)
  +fanned_result : Comparison.CompareResult = Comparison.compare_entries_fanned(first_entries, second_entries)
  do IO<Unit>:
    IO.print(flag_text("fanned-added-five", Nat.is_eq(count_added(fanned_result), 5n)))
    IO.print(flag_text("fanned-modified-eight", Nat.is_eq(count_modified(fanned_result), 8n)))
    IO.print(flag_text("sequential-added-five", Nat.is_eq(count_added(sequential_result), 5n)))
    IO.print(counts_agree_result(sequential_result, fanned_result))

def main() -> IO(Unit):
  +first_entries : List<&2, Reading.ChainEntry> = gen_first_entries(40n, Nil{})
  +second_entries : List<&2, Reading.ChainEntry> = List.append(&2, Reading.ChainEntry, gen_second_entries(40n, Nil{}), gen_extra_entries(5n, Nil{}))
  report_counts(first_entries, second_entries)
