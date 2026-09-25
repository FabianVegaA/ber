import Base
import ../src/LogicalKey.bend as LogicalKey
import ../src/ContentHash.bend as ContentHash

def report(check_name: String, condition: Bool) -> IO(Unit):
  match condition:
    case True{}:
      IO.print(check_name ++ ": PASS")
    case False{}:
      IO.print(check_name ++ ": FAIL")

def main() -> IO(Unit):
  do IO<Unit>:
    report("encode-logical-key", String.eq(LogicalKey.encode_logical_key(LogicalKey.Make{"ledger", "abc"}), "ledger/abc"))
    report("object-key", String.eq(LogicalKey.build_object_storage_key("deadbeef"), "object/deadbeef"))
    report("index-key", String.eq(LogicalKey.build_index_storage_key("ledger", "abc", "commit_first"), "index/ledger/abc/commit_first"))
    report("stage-key", String.eq(LogicalKey.build_stage_storage_key("session_first", "ledger", "abc"), "stage/session_first/ledger/abc"))
    first_digest : String = ContentHash.compute_sha256_hex("hello")
    second_digest : String = ContentHash.compute_sha256_hex("hello")
    report("hash-deterministic", String.eq(first_digest, second_digest))
    report("hash-distinct", Bool.not(String.eq(ContentHash.compute_sha256_hex("hello"), ContentHash.compute_sha256_hex("world"))))
    IO.print("abc-digest: " ++ ContentHash.compute_sha256_hex("abc"))
