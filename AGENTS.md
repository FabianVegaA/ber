When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible

Proof-driven development (NOT TDD):
- Laws first: state the property in LAWS.bend before or alongside the code;
  PROOF.bend proves it in the same change. Code lands proven, not tested-in.
- Tests (`tests/*_check.bend`) cover ONLY what proofs cannot check: IO/Sess
  wiring (persist/load shells, store effects, run plumbing). Never duplicate
  a proven property in a test.
- When a test assert becomes provable (pure core, no Sess), promote it to a
  law and shrink or delete the test.
- Gate: `bend PROOF.bend` green before every commit; `bolt` 0 errors.
- Workflow per behavior: claim (LAWS) -> code + proof (PROOF) -> IO check
  only when Sess/effects are involved.
