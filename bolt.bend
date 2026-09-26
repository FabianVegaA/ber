# bolt linter config. correctness findings gate the build (error); style,
# suspicious and laws findings stay advisory (warn) — LAWS.bend long lines
# (S002) and IO-shell law coverage (L001) are accepted by design, see spec §7.
def correctness() -> String:
  "error"
def suspicious() -> String:
  "warn"
def style() -> String:
  "warn"
def laws() -> String:
  "warn"
