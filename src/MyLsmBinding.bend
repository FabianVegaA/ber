import Base
import 0x8bf6d41adbe0e67e438f6cdc25a6cb6e/mylsm.bend as MyLsmStore
import 0x8bf6d41adbe0e67e438f6cdc25a6cb6e/src/Wal.bend as WalTypes

# PINNED: mylsm v0.2.0 (probe-verified All-terms-check on Bend 2.0.27).
# ONLY this file names MyLsmStore. MyLSM is a STATE MONAD (Sess), not handles:
# ber-core composes Sess actions in do-blocks; the monad threads Db internally.
def store_value(+storage_key: String, +stored_value: String) -> MyLsmStore.Sess<&2, Unit>:
  MyLsmStore.sput(storage_key, stored_value)

def remove_value(+storage_key: String) -> MyLsmStore.Sess<&2, Unit>:
  MyLsmStore.sdel(storage_key)

def load_value(+storage_key: String) -> MyLsmStore.Sess<&2, Maybe<&2, String>>:
  MyLsmStore.sget(storage_key)

def store_batch(+mutations: List<&2, WalTypes.Mut>) -> MyLsmStore.Sess<&2, Unit>:
  MyLsmStore.sbatch(mutations)
