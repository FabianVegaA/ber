import Base
import mylsm-lsm-store@0.3.2.0/src/hub_sha/sha256.bend as ProvenSha
import bend-codec-lib@0.2.0.0/utf8.bend as Utf8Lib
import bend-codec-lib@0.2.0.0/bytes.bend as ByteLib

# SHA-256 hex of UTF-8 text. ProvenSha/Utf8 cores are trusted upstream
# (FIPS 180-4 machine-checked; closed roundtrips proved); this module owns
# only the byte-list plumbing between them, covered by the differential
# check vs Python hashlib at the 55/56/64-byte padding boundaries.
# Unwraps the byte box into the word list the hash core consumes.
def bytes_data(byte_box: ByteLib.Bytes) -> List<&2, U32>:
  match byte_box:
    case ByteLib.Bytes{raw_data}:
      raw_data

# Hashes valid encodings; unencodable input yields a fixed sentinel string.
def digest_from_encode_result(encode_result: Result<&2, &2, Utf8Lib.Utf8.Error, ByteLib.Bytes>) -> String:
  match encode_result:
    case Fail{encode_error}:
      "INVALID_UTF8_INPUT"
    case Done{byte_box}:
      ProvenSha.hex(ProvenSha.sha256(bytes_data(byte_box)))

# "INVALID_UTF8_INPUT" on unencodable text; never fails on valid input.
def compute_sha256_hex(input_text: String) -> String:
  digest_from_encode_result(Utf8Lib.Utf8.encode(input_text))
