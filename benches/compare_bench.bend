import Base
import ../src/Reading.bend as Reading
import ../src/Comparison.bend as Comparison
import ../src/LogicalKey.bend as LogicalKey

# Bench: generated entry lists, sequential vs fanned compare, wall-timed
# natively. Checker-normalized runs are NOT timed.

# Generates the base entry list with versioned values.
def gen_first_entries(remaining: Nat, accum_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match remaining:
    case 0n:
      accum_entries
    case 1n++rest_count:
      gen_first_entries(rest_count, Con{Reading.make_entry("bench/key-" ++ Nat.show(rest_count), "version-" ++ Nat.show(rest_count)), accum_entries})

# Appends -changed to every fifth value.
def changed_suffix(is_changed: Bool, +remaining: Nat) -> String:
  match is_changed:
    case True{}:
      "version-" ++ Nat.show(remaining) ++ "-changed"
    case False{}:
      "version-" ++ Nat.show(remaining)

# Generates the modified list; every fifth value changed.
def gen_second_entries(remaining: Nat, accum_entries: List<&2, Reading.ChainEntry>) -> List<&2, Reading.ChainEntry>:
  match remaining:
    case 0n:
      accum_entries
    case 1n++rest_count:
      gen_second_entries(rest_count, Con{Reading.make_entry("bench/key-" ++ Nat.show(rest_count), changed_suffix(Nat.is_eq(Nat.mod(rest_count, 5n), 0n), rest_count)), accum_entries})

# Renders one label=count report line.
def count_line(label_text: String, counted: Nat) -> String:
  label_text ++ "=" ++ Nat.show(counted)

# Prints sequential vs fanned counts side by side.
def report_sequential_only(entry_count: Nat, +sequential_result: Comparison.CompareResult) -> IO(Unit):
  do IO<Unit>:
    IO.print("entries=" ++ Nat.show(entry_count))
    IO.print(count_line("sequential-added", List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(sequential_result))))
    IO.print(count_line("sequential-modified", List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(sequential_result))))

# Builds generated lists and runs the fanned compare.
def run_sequential_only(+entry_count: Nat) -> IO(Unit):
  +second_entries : List<&2, Reading.ChainEntry> = gen_second_entries(entry_count, Nil{})
  report_sequential_only(entry_count, Comparison.compare_sorted_entries(gen_first_entries(entry_count, Nil{}), second_entries))

# Prints quad-path counts.
def remaining_head_or_empty(remaining_texts: List<String>) -> String:
  match remaining_texts:
    case Nil{}:
      ""
    case Con{head_text, tail_texts}:
      head_text

# Selects the fanned path on mode fan.
def report_sort_only(entry_count: Nat, +sort_result: Comparison.CompareResult) -> IO(Unit):
  do IO<Unit>:
    IO.print("entries=" ++ Nat.show(entry_count))
    IO.print(count_line("sort-added", List.length(&2, LogicalKey.LogicalKey, Comparison.added_keys_of(sort_result))))
    IO.print(count_line("sort-modified", List.length(&2, Comparison.ModifiedEntry, Comparison.modified_entries_of(sort_result))))

# Builds generated lists and runs the sorted-path compare.
def run_sort_only(+entry_count: Nat) -> IO(Unit):
  +second_entries : List<&2, Reading.ChainEntry> = gen_second_entries(entry_count, Nil{})
  +first_entries : List<&2, Reading.ChainEntry> = gen_first_entries(entry_count, Nil{})
  report_sort_only(entry_count, Comparison.compare_entries_sorted(first_entries, second_entries))

# Selects the sorted path on mode sort.
def use_sort_path(mode_text: String) -> Bool:
  String.eq(mode_text, "sort")

# Runs the sorted path or the sequential reference path.
def dispatch_sort_or_seq(mode_is_sort: Bool, +entry_count: Nat) -> IO(Unit):
  match mode_is_sort:
    case True{}:
      run_sort_only(entry_count)
    case False{}:
      run_sequential_only(entry_count)

# Runs with parsed size, defaulting to 1000 entries.
def bench_with_size(read_maybe: Maybe<&2, Nat>, +mode_text: String) -> IO(Unit):
  match read_maybe:
    case None{}:
      dispatch_sort_or_seq(use_sort_path(mode_text), 1000n)
    case Some{entry_count}:
      dispatch_sort_or_seq(use_sort_path(mode_text), entry_count)

# Parses size and mode args, then runs.
def dispatch_bench_args(args_texts: List<String>) -> IO(Unit):
  match args_texts:
    case Nil{}:
      run_sequential_only(1000n)
    case Con{size_text, remaining_texts}:
      bench_with_size(Nat.read(size_text), remaining_head_or_empty(remaining_texts))

# Entry point: reads argv and runs the bench.
def main() -> IO(Unit):
  do IO<Unit>:
    args_texts : List<String> <- IO.args()
    dispatch_bench_args(args_texts)
