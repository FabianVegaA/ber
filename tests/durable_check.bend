import Base
import ../src/Store.bend as Store

# IO harness: the durable shell opens, flushes and reopens. Missing wal.log
# answers empty without touching disk; a flushed put survives reopen.
# Laws cover the pure journal; this covers the open/flush/reopen wiring.
# Uses /tmp (always exists, no mkdir needed); reruns overwrite one key.
# Foreign effects need a binary: bend tests/durable_check.bend -o /tmp/dc_bin && /tmp/dc_bin

def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def flag_absent(read_result: Maybe<&2, String>) -> String:
  match read_result:
    case None{}:
      flag_text("durable-absent-empty", True{})
    case Some{unexpected_text}:
      flag_text("durable-absent-empty", False{})

def flag_roundtrip(read_result: Maybe<&2, String>) -> String:
  match read_result:
    case None{}:
      flag_text("durable-roundtrip", False{})
    case Some{found_text}:
      flag_text("durable-roundtrip", String.eq(found_text, "durable-check-val"))

def report_absent_read(run_pair: Store.Handle & Maybe<&2, String>) -> IO(Unit):
  match run_pair:
    case (unused_store, read_result):
      IO.print(flag_absent(read_result))

def report_absent(opened: Result<&1, &1, U32 & String, Store.Handle>) -> IO(Unit):
  match opened:
    case Fail{open_error}:
      IO.print(flag_text("durable-absent-empty", False{}))
    case Done{store}:
      report_absent_read(Store.run_op(&2, Maybe<&2, String>, store, Store.oget("durable-check/key")))

def report_roundtrip_read(run_pair: Store.Handle & Maybe<&2, String>) -> IO(Unit):
  match run_pair:
    case (unused_store, read_result):
      IO.print(flag_roundtrip(read_result))

def report_reopened(opened: Result<&1, &1, U32 & String, Store.Handle>) -> IO(Unit):
  match opened:
    case Fail{open_error}:
      IO.print(flag_text("durable-roundtrip", False{}))
    case Done{store}:
      report_roundtrip_read(Store.run_op(&2, Maybe<&2, String>, store, Store.oget("durable-check/key")))

def reopen_and_verify() -> IO(Unit):
  do IO<Unit>:
    reopened : Result<&1, &1, U32 & String, Store.Handle> <- Store.open_durable("/tmp")
    report_reopened(reopened)

def report_written(written: Result<&1, &1, U32 & String, Store.Handle & Unit>) -> IO(Unit):
  match written:
    case Fail{write_error}:
      IO.print(flag_text("durable-roundtrip", False{}))
    case Done{store_pair}:
      match store_pair:
        case (unused_store, unused_unit):
          reopen_and_verify()

def report_write_opened(opened: Result<&1, &1, U32 & String, Store.Handle>) -> IO(Unit):
  match opened:
    case Fail{open_error}:
      IO.print(flag_text("durable-roundtrip", False{}))
    case Done{store}:
      do IO<Unit>:
        written : Result<&1, &1, U32 & String, Store.Handle & Unit> <- Store.run_op_durable(&2, Unit, store, Store.oput("durable-check/key", "durable-check-val"))
        report_written(written)

def main() -> IO(Unit):
  do IO<Unit>:
    opened_absent : Result<&1, &1, U32 & String, Store.Handle> <- Store.open_durable("/tmp/ber-durable-absent")
    absent_done : Unit <- report_absent(opened_absent)
    opened_store : Result<&1, &1, U32 & String, Store.Handle> <- Store.open_durable("/tmp")
    write_done : Unit <- report_write_opened(opened_store)
    return write_done
