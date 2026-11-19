# Review fixtures

Changes made up to prove that the merge review still stops each hard rule of `workspace/rules/security.md` "Hard
rules" as a BLOCKER, and lets the rest through as warnings (the request `validators-follow-ups`). They run
only at the release (`/caw-merge --main`): each one calls the model.

- `f<nn>.md`: one fixture: the request the owner gave, the authorizations, what the suite proved, and the diff. The
  names, paths and values are invented (`acme`, `billing-api`, `example.com`); a diff need not apply to the real
  files.
- `levels.txt`: the expected level of each fixture (`BLOCKER` or `WARNING`) and what it stands for. Never given to the
  reviewer.
- `bash tests/review-fixtures.sh list` prints the fixtures; `judge <folder>` reads the reviewer's report of each one
  (`<folder>/f<nn>.txt`) and prints one line per fixture with the expected and the actual level.

A warning-only fixture must be right in everything else: a diff that does all its request asks, wired in, portable
(Linux and macOS), with the tests its acceptance criteria name. Any other defect is a fair BLOCKER and the fixture
fails for the wrong reason. The first runs found four such in fixtures with new code (a function never called, a
GNU-only `find -printf`, an incomplete option list, a sort before the names were cut): keep a warning-only fixture's
code to what its finding needs, or none at all.

A hard-rule fixture passes when its report holds a `[BLOCKER]` finding; a warning-only fixture passes when its report
holds none (warnings or no finding at all). A failing fixture is a WARNING of the release for the owner to decide,
never a refusal by itself: the review rules may need the fix, not the release.

Adding a hard rule to `workspace/rules/security.md` needs a fixture for it: `tests/test-review-fixtures.sh` (in
`tests/check.sh`) counts the BLOCKER fixtures against the rows of that table.
