import Base
import mylsm-lsm-store@0.3.2.0/mylsm.bend as MyLsmStore
import mylsm-lsm-store@0.3.2.0/src/Db.bend as DbTypes
import mylsm-lsm-store@0.3.2.0/src/Wal.bend as WalTypes

# Session effects for ber-core. Op is a newtype over Db transitions and
# Handle over MyLSM Db; do-blocks desugar through Op.bind/Op.pure exactly
# like Sess. Pairs sit only in return and parameter positions (never as a
# Sess answer), so Op stays kind-polymorphic; computed pairs thread through
# helpers (match on parameters, never on computed values). Defs are ordered
# leaf-first: no def calls one written below it.
#
# Every op returns its answer with a journal of physical mutations
# (execution order). Pure run_op drops it; run_op_tracked exposes it and
# run_op_durable appends it through one WAL frame plus fsync. oput/odel
# journal exactly what they apply, so the WAL mirrors the memtable.

# Journal rope: O(1) per-bind combination (no calls, just nesting); flattened
# once at flush with an explicit work stack (constant native stack) into
# chronological order. Reads build Empty spines that flatten to Nil.
type Journal is Data:
  JEmpty{}
  JOne{mut: WalTypes.Mut}
  JMore{prior: Journal, post: Journal}

# Counts rope nodes structurally; the work loop below visits each once.
def rope_nodes(+journal: Journal) -> Nat:
  match journal:
    case JEmpty{}:
      1n
    case JOne{unlogged_mut}:
      1n
    case JMore{prior, post}:
      Nat.add(1n, Nat.add(rope_nodes(prior), rope_nodes(post)))

# Flattens a rope oldest-first with an explicit work stack; the accumulator
# holds the reversed prefix. Fuel covers nodes plus the final empty check.
def flatten_go(fuel: Nat, +work: List<&2, Journal>, +acc: List<&2, WalTypes.Mut>) -> List<&2, WalTypes.Mut>:
  match fuel:
    case 0n:
      acc
    case 1n+fuel_left:
      match work:
        case Nil{}:
          List.reverse(&2, WalTypes.Mut, acc)
        case Con{head, tail}:
          match head:
            case JEmpty{}:
              flatten_go(fuel_left, tail, acc)
            case JOne{mut}:
              flatten_go(fuel_left, tail, Con{mut, acc})
            case JMore{prior, post}:
              flatten_go(fuel_left, Con{prior, Con{post, tail}}, acc)

# Materializes a journal rope into its chronological mutation list.
def flatten_journal(+journal: Journal) -> List<&2, WalTypes.Mut>:
  flatten_go(Nat.add(rope_nodes(journal), 1n), Con{journal, Nil{}}, Nil{})

# One session step chain: a Db transition answering with its journal.
type Op<a, -A: Kind(a)> is Kind(a <&> &1):
  Op{run: DbTypes.Db -> (DbTypes.Db & A) & Journal}

# An opened store handle; affine, threaded through run_op.
type Handle is Type:
  Handle{db: DbTypes.Db}

# Unwraps the inner transition for translators like bind and run_op.
def Op.inner(b, -B: Kind(b), op: Op<b, B>) -> DbTypes.Db -> (DbTypes.Db & B) & Journal:
  match op:
    case Op{run_fn}:
      run_fn

# Lifts a pure value with an empty journal.
def Op.pure(a, -A: Kind(a), val: A) -> Op<a, A>:
  Op{st => ((st, val), JEmpty{})}

# Concatenates a prior journal before a later one, finishing the second step.
def Op.seq2(a, -B: Kind(a), +prior: Journal, second: (DbTypes.Db & B) & Journal) -> (DbTypes.Db & B) & Journal:
  match second:
    case ((db_next, answer), journal):
      ((db_next, answer), JMore{prior, journal})

# Runs the next op on the first answer, threading Db and journal.
def Op.seq(a, -A: Kind(a), -B: Kind(a), first: (DbTypes.Db & A) & Journal, fun: A -> Op<a, B>) -> (DbTypes.Db & B) & Journal:
  match first:
    case ((db_mid, answer), prior):
      Op.seq2(a, B, prior, Op.inner(a, B, fun(answer))(db_mid))

# Sequences two ops, concatenating journals in execution order.
def Op.bind(a, -A: Kind(a), -B: Kind(a), op: Op<a, A>, fun: A -> Op<a, B>) -> Op<a, B>:
  match op:
    case Op{run1}:
      Op{st => Op.seq(a, A, B, run1(st), fun)}

# Pairs a finished point write with its journaled mutation.
def pair_put(+key: String, +val: String, db_next: DbTypes.Db) -> (DbTypes.Db & Unit) & Journal:
  ((db_next, Unit{}), JOne{WalTypes.Put{key, val}})

# Writes one key and journals the mutation.
def oput(+key: String, +val: String) -> Op<&2, Unit>:
  Op{st => pair_put(key, val, MyLsmStore.put_go(st, key, val))}

# Pairs a finished point read with an empty journal.
def pair_get(finished: DbTypes.Db & Maybe<&2, String>) -> (DbTypes.Db & Maybe<&2, String>) & Journal:
  match finished:
    case (db_next, found_val):
      ((db_next, found_val), JEmpty{})

# Reads one key; missing reads as None. Reads journal nothing.
def oget(+key: String) -> Op<&2, Maybe<&2, String>>:
  Op{st => pair_get(MyLsmStore.sget_go(st, key))}

# Pairs a finished point delete with its journaled mutation.
def pair_del(+key: String, db_next: DbTypes.Db) -> (DbTypes.Db & Unit) & Journal:
  ((db_next, Unit{}), JOne{WalTypes.Del{key}})

# Deletes one key and journals the mutation.
def odel(+key: String) -> Op<&2, Unit>:
  Op{st => pair_del(key, MyLsmStore.del_go(st, key))}

# Opens a store handle over a directory label (pure; no IO touched).
def open_store(+dir: String) -> Handle:
  Handle{MyLsmStore.open(dir)}

# Default store label for CLI use (pure; no IO touched).
def open_default_store() -> Handle:
  open_store("./.ber")

# Wraps a reopened database; IO errors propagate as Fail.
def wrap_reopened(reopened: Result<&1, &1, U32 & String, DbTypes.Db>) -> Result<&1, &1, U32 & String, Handle>:
  match reopened:
    case Fail{error}:
      Fail{error}
    case Done{db}:
      Done{Handle{db}}

# Opens a durable handle, replaying wal.log when present; missing file
# answers empty. The caller ensures the directory exists.
def open_durable(+dir: String) -> IO(Result<&1, &1, U32 & String, Handle>):
  do IO<Result<&1, &1, U32 & String, Handle>>:
    reopened : Result<&1, &1, U32 & String, DbTypes.Db> <- MyLsmStore.reopen(dir)
    return wrap_reopened(reopened)

# Projects the materialized journal out of a tracked run (laws observe this).
def tracked_journal(a, -A: Kind(a), tracked: (Handle & A) & Journal) -> List<&2, WalTypes.Mut>:
  match tracked:
    case ((unused_handle, unused_answer), journal):
      flatten_journal(journal)

# Rewraps a computed runner pair into Handle form, dropping the journal.
def rewrap_pair(a, -A: Kind(a), computed: (DbTypes.Db & A) & Journal) -> Handle & A:
  match computed:
    case ((db_next, answer), unused_journal):
      (Handle{db_next}, answer)

# Executes a whole op chain against a handle (pure; journal dropped).
def run_op(a, -A: Kind(a), store: Handle, op: Op<a, A>) -> Handle & A:
  match store:
    case Handle{db}:
      rewrap_pair(a, A, Op.inner(a, A, op)(db))

# Rewraps a tracked runner pair, keeping the journal.
def rewrap_tracked(a, -A: Kind(a), computed: (DbTypes.Db & A) & Journal) -> (Handle & A) & Journal:
  match computed:
    case ((db_next, answer), journal):
      ((Handle{db_next}, answer), journal)

# Executes a whole op chain, exposing the journal for the WAL runner.
def run_op_tracked(a, -A: Kind(a), store: Handle, op: Op<a, A>) -> (Handle & A) & Journal:
  match store:
    case Handle{db}:
      rewrap_tracked(a, A, Op.inner(a, A, op)(db))

# Wraps a written database with its answer; IO errors propagate as Fail.
def wrap_written(a, -A: Kind(a), written: Result<&1, &1, U32 & String, DbTypes.Db>, answer: A) -> Result<&1, &1, U32 & String, Handle & A>:
  match written:
    case Fail{error}:
      Fail{error}
    case Done{db_next}:
      Done{(Handle{db_next}, answer)}

# Skips the WAL when the journal is empty (pure reads never fsync).
def flush_clean(a, -A: Kind(a), store_next: Handle, answer: A) -> IO(Result<&1, &1, U32 & String, Handle & A>):
  match store_next:
    case Handle{db}:
      IO.pure(Result<&1, &1, U32 & String, Handle & A>, Done{(Handle{db}, answer)})

# Flushes a nonempty journal through one WAL frame plus fsync.
def flush_dirty(a, -A: Kind(a), store_next: Handle, answer: A, +head_mut: WalTypes.Mut, +tail_muts: List<&2, WalTypes.Mut>) -> IO(Result<&1, &1, U32 & String, Handle & A>):
  match store_next:
    case Handle{db}:
      do IO<Result<&1, &1, U32 & String, Handle & A>>:
        written : Result<&1, &1, U32 & String, DbTypes.Db> <- DbTypes.db_write(db, WalTypes.Batch{Con{head_mut, tail_muts}})
        return wrap_written(a, A, written, answer)

# Dispatches on journal emptiness without matching computed values.
def flush_list(a, -A: Kind(a), store_next: Handle, answer: A, +mutations: List<&2, WalTypes.Mut>) -> IO(Result<&1, &1, U32 & String, Handle & A>):
  match mutations:
    case Nil{}:
      flush_clean(a, A, store_next, answer)
    case Con{head_mut, tail_muts}:
      flush_dirty(a, A, store_next, answer, head_mut, tail_muts)

# Splits a tracked runner pair for the flush dispatch.
def flush_tracked(a, -A: Kind(a), tracked: (Handle & A) & Journal) -> IO(Result<&1, &1, U32 & String, Handle & A>):
  match tracked:
    case ((store_next, answer), journal):
      flush_list(a, A, store_next, answer, flatten_journal(journal))

# Executes a whole op chain durably: pure run, then one WAL append plus
# fsync of exactly the journaled mutations.
def run_op_durable(a, -A: Kind(a), store: Handle, op: Op<a, A>) -> IO(Result<&1, &1, U32 & String, Handle & A>):
  flush_tracked(a, A, run_op_tracked(a, A, store, op))
