import Base
import mylsm-lsm-store@0.3.1.0/mylsm.bend as MyLsmStore
import mylsm-lsm-store@0.3.1.0/src/Db.bend as DbTypes

# Session effects for ber-core. Op is a newtype over MyLSM Sess and Handle
# over MyLSM Db: ber-core names THESE types, and this module is the ONLY one
# naming MyLSM. do-blocks desugar through Op.bind/Op.pure exactly like Sess.
# Bend has no value projection: inner sessions unwrap via Op.inner (match on
# the parameter), never `op.run`; computed pairs thread through helpers.

# One session step chain; the answer type rides along.
type Op<a, -A: Kind(a)> is Kind(a <&> &1):
  Op{run: MyLsmStore.Sess<a, A>}

# An opened store handle; affine, threaded through run_op.
type Handle is Type:
  Handle{db: DbTypes.Db}

# Unwraps the inner session for translators like bind and run_op.
def Op.inner(b, -B: Kind(b), op: Op<b, B>) -> MyLsmStore.Sess<b, B>:
  match op:
    case Op{inner_sess}:
      inner_sess

# Lifts a pure value; what `return` desugars to inside do-blocks.
def Op.pure(a, -A: Kind(a), val: A) -> Op<a, A>:
  Op{MyLsmStore.Sess.pure(a, A, val)}

# Sequences two ops; what `<-` desugars to inside do-blocks.
def Op.bind(a, -A: Kind(a), -B: Kind(a), op: Op<a, A>, fun: A -> Op<a, B>) -> Op<a, B>:
  Op{MyLsmStore.Sess.bind(a, A, B, Op.inner(a, A, op), x => Op.inner(a, B, fun(x)))}

# Writes one key.
def oput(+key: String, +val: String) -> Op<&2, Unit>:
  Op{MyLsmStore.sput(key, val)}

# Reads one key; missing reads as None.
def oget(+key: String) -> Op<&2, Maybe<&2, String>>:
  Op{MyLsmStore.sget(key)}

# Deletes one key.
def odel(+key: String) -> Op<&2, Unit>:
  Op{MyLsmStore.sdel(key)}

# Opens a store handle over a directory label.
def open_store(+dir: String) -> Handle:
  Handle{MyLsmStore.open(dir)}

# Rewraps a computed runner pair into Handle form.
def rewrap_pair(a, -A: Kind(a), computed_pair: DbTypes.Db & A) -> Handle & A:
  match computed_pair:
    case (db_next, answer):
      (Handle{db_next}, answer)

# Executes a whole op chain against a handle.
def run_op(a, -A: Kind(a), store: Handle, op: Op<a, A>) -> Handle & A:
  match store:
    case Handle{db}:
      rewrap_pair(a, A, MyLsmStore.run_sess(a, A, db, Op.inner(a, A, op)))
