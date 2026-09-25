import Base
import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/crypto/sha/sha256.bend as ProvenSha
import bend-codec-lib@0.2.0.0/utf8.bend as Utf8Lib
import bend-codec-lib@0.2.0.0/bytes.bend as ByteLib

# TRUSTED (do not re-prove): ProvenSha.sha256/hex — list-based core instantiated
# over the FIPS 180-4 constants with a core refinement theorem upstream;
# Utf8Lib.encode/decode — closed roundtrips proved upstream.
# All imports check on Bend 2.0.27 (probe 2026-09-25).
# OWNED glue: byte-list plumbing only (no array packing, no re-encoding) —
# the UTF-8 byte list feeds the hash core directly.
# Covered by differential test vs python hashlib (vendor task), incl. 55/56/64
# byte padding boundaries and multi-byte UTF-8 payloads.
def bytes_data(byte_box: ByteLib.Bytes) -> List<&2, U32>:
  match byte_box:
    case ByteLib.Bytes{raw_data}:
      raw_data

def digest_from_encode_result(encode_result: Result<&2, &2, Utf8Lib.Utf8.Error, ByteLib.Bytes>) -> String:
  match encode_result:
    case Fail{encode_error}:
      "INVALID_UTF8_INPUT"
    case Done{byte_box}:
      ProvenSha.hex(ProvenSha.sha256(bytes_data(byte_box)))

def compute_sha256_hex(input_text: String) -> String:
  digest_from_encode_result(Utf8Lib.Utf8.encode(input_text))
