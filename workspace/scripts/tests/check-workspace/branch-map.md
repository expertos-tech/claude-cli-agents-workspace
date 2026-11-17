# Branch map of check-workspace

`rules/quality.md` "Tests": no bash tool measures branches, so `test-engineer` lists each decision and error path with its test, and `reviewer` checks the list. Rows go by function name, so they survive edits.

- Script: `scripts/check-workspace.sh`. Tests: `scripts/tests/check-workspace/test-check-workspace.sh`.
- Every test name exists as a function in that file.
- The suite also holds the `test_AC25_*` and `test_F8_*` tests, of the `tmp/` and `--path` handling of `scripts/validate.sh`. That part of `validate.sh` is not new, so they stay out of this map; its check of tracked `.env` and `local.settings.json` files has its own table below.
- `(top level)` is the code outside any function: the gate has no `main`.
- `GAP` marks a path with no test, and says why.
- `die` and `usage` have no decision of their own, so no row.

## GAP

| Path | Why there is no test |
| --- | --- |
| GAP: `json_is_one_document` and `parse_poc_file`, the `python3` lines in the Linux image | The image has no `python3`; those parts of test_AC24_settings_parser_fallback, test_AC24_empty_settings_is_invalid_with_every_parser and test_AC24_poc_files_must_parse skip there and run on macOS |

## scripts/check-workspace.sh

| Function | Decision or error path | Test |
| --- | --- | --- |
| (top level) | `--base`: value; none; empty; a tag, a sha; a blob, a range, `-x`: exit 2 | test_AC24_usage, test_AC24_base_option, test_AC24_base_as_sha_tag_and_invalid_forms |
| (top level) | `--verbose` | test_AC24_verbose_output |
| (top level) | `--help`, `-h`, also with no checkout | test_AC24_usage, test_AC24_help_needs_no_checkout |
| (top level) | `--floor`: the suites are skipped, the other checks run | test_floor_skips_the_suites |
| (top level) | unknown option: exit 2 | test_AC24_usage, test_AC24_help_needs_no_checkout |
| (top level) | no `git`: exit 2; no `mktemp`: never a pass | test_AC24_missing_tools_fail_closed |
| (top level) | not a checkout: exit 2 | test_AC24_not_a_checkout |
| (top level) | base not found: exit 2 | test_AC24_usage, test_AC24_base_as_sha_tag_and_invalid_forms |
| (top level) | no common ancestor: exit 1 | test_AC24_no_common_ancestor |
| (top level) | root is the parent of the script: any cwd, a linked worktree | test_AC24_runs_from_any_cwd, test_AC24_gate_in_a_linked_worktree |
| (top level) | under `tools/`: `parse` runs; elsewhere: it does not | test_AC24_poc_files_must_parse, test_AC24_poc_paths_are_never_lint_gated |
| (top level) | under `scripts/`: suites run; elsewhere: SKIP | test_AC24_scripts_diff_adds_shell_and_suites, test_AC24_docs_only_runs_three_checks, test_AC24_only_scripts_dir_runs_suites |
| read_changed_paths | committed, staged, edited, deleted, renamed as both paths; merge-base, not the base tip | test_AC24_changed_paths_sources, test_AC24_a_defect_outside_the_diff_does_not_fail_the_gate, test_AC24_the_list_holds_the_changed_files_still_on_disk |
| read_changed_paths | untracked; spaces, non-ASCII, a dash, a glob; names git quotes | test_AC24_changed_paths_sources, test_AC24_non_ascii_path_counts, test_AC24_odd_names_do_not_break_the_list, test_AC24_path_git_must_quote_still_counts |
| read_changed_paths | `git diff` fails; `git ls-files` fails: exit 1, never an empty list | test_AC24_a_failing_diff_never_passes_on_an_empty_list, test_AC24_an_empty_changed_list_is_said_out_loud |
| read_changed_paths | no changed path: a NOTE | test_AC24_an_empty_changed_list_is_said_out_loud |
| changed_has | found; not found; a diff larger than a pipe | test_AC24_settings_only_checked_when_changed, test_AC24_big_diff_does_not_hide_a_broken_settings |
| changed_under | found; not found; a diff larger than a pipe | test_AC24_only_scripts_dir_runs_suites, test_AC24_docs_only_runs_three_checks, test_AC24_big_diff_does_not_hide_a_scripts_change |
| step | PASS; FAIL; verbose; the last 30 lines; every check runs after a failure with `--all`, none without | test_AC24_verbose_output, test_AC24_failure_output_is_capped_at_30_lines, test_AC24_validate_failure_fails_the_gate_and_the_rest_runs, test_gate_stops_at_the_first_failure |
| decision_numbers | a glob with no match: an empty folder | test_AC24_an_empty_decisions_folder_passes |
| decision_numbers | other extension, a prefix that is no number, padding, digits that look octal, spaces in names | test_AC24_decision_number_ignores_padding_and_other_files, test_AC24_decision_numbers_more_forms |
| decision_numbers | `.MD` | test_AC24_decision_number_case_variant_fails |
| check_decisions | no folder: passes | test_AC24_decision_number_ignores_padding_and_other_files |
| check_decisions | no duplicate; one; two; renumbered; in a linked worktree | test_AC24_duplicate_decision_number_fails, test_AC24_decision_numbers_more_forms, test_AC24_gate_in_a_linked_worktree |
| check_custom_terms | no list: SKIP; an empty list: SKIP; a named list missing: fails; a term in a committed or untracked file, history files and decision records included: fails | test_custom_terms_skip_without_the_custom_layer, test_custom_terms_empty_list_passes, test_custom_terms_from_AIWP_TERMS_FILE, test_custom_terms_judge_committed_and_untracked_files, test_custom_terms_judge_the_history_whole |
| is_i18n_document | the root README; a product README at any depth; docs/ at any depth; tools/<name>/docs/; decision records, CHANGELOG and other folders: out of scope | test_i18n_passes_when_every_document_is_translated, test_i18n_fails_on_an_orphan_translation |
| check_i18n | no i18n/ at the repo root: SKIP | test_i18n_skips_without_the_folder |
| check_i18n | every translation in place: passes, untracked or committed | test_i18n_passes_when_every_document_is_translated |
| check_i18n | a translation missing for a locale, an untracked new document | test_i18n_fails_on_a_missing_translation |
| check_i18n | line 1 missing, naming another path, an empty file | test_i18n_fails_without_the_source_line |
| check_i18n | an older hash; a new hash passes | test_i18n_fails_on_an_outdated_hash |
| check_i18n | an orphan: its source gone, a decision record; another locale of a real document and a file right under i18n/: no orphan | test_i18n_fails_on_an_orphan_translation |
| json_is_one_document | valid; invalid; zero bytes, blank, two documents, with each parser | test_AC24_invalid_settings_fails, test_AC24_empty_settings_is_invalid_with_every_parser |
| json_is_one_document | `jq`; `python3`; neither: fails | test_AC24_settings_parser_fallback |
| check_settings | not changed: passes, even if invalid | test_AC24_settings_only_checked_when_changed |
| check_settings | deleted, a folder, renamed away, a dangling link: fails | test_AC24_settings_only_checked_when_changed, test_AC24_settings_odd_forms |
| parse_poc_file | `tsconfig*.json`, `jsconfig*.json`: skipped | test_AC24_poc_files_must_parse |
| parse_poc_file | `*.sh`, `*.json`, `*.py`: parse, or fail; other types: nothing | test_AC24_poc_files_must_parse |
| check_poc_parse | other paths; a file gone or a link: skipped | test_AC24_poc_files_must_parse |
| check_poc_parse | does not parse: names it, the rest go on | test_AC24_poc_files_must_parse |
| under_coverage_folder | same folder, parent, sibling, root | test_AC24_validate_list_by_path, test_AC24_coverage_needs_the_folder_with_coveragerc |
| validate_list | every row of the path table | test_AC24_validate_list_by_path, test_AC24_docs_only_runs_three_checks, test_AC24_scripts_diff_adds_shell_and_suites |
| validate_list | `tools/` adds nothing | test_AC24_poc_paths_are_never_lint_gated |
| write_judged_list | still on disk, no links, not under `tools/`, plain names | test_AC24_the_list_holds_the_changed_files_still_on_disk, test_AC24_poc_paths_are_never_lint_gated |
| write_judged_list | a newline in a name: fails, never unjudged | test_AC24_the_list_holds_the_changed_files_still_on_disk |
| check_validate | `scripts/validate.sh` missing, also deleted on the branch | test_AC24_missing_validate_script_fails, test_AC24_odd_names_do_not_break_the_list |
| check_validate | a bad judged list stops it: `validate.sh` does not run | test_AC24_the_list_holds_the_changed_files_still_on_disk |
| check_validate | `--verbose` passed on | test_AC24_verbose_output |
| check_validate | it fails: the gate fails, the rest runs | test_AC24_validate_failure_fails_the_gate_and_the_rest_runs |
| check_validate | only changed files are judged; a defect outside the diff does not fail; a diagram outside it is not rendered | test_AC24_each_lint_check_judges_only_the_changed_files, test_AC24_a_defect_outside_the_diff_does_not_fail_the_gate, test_AC24_a_diagram_outside_the_diff_is_not_rendered |
| check_suites | a suite missing: fails, the others run | test_AC24_suite_failure_and_missing_suite |
| check_suites | ok or failed: reported, the others run; the list matches the plan | test_AC24_suite_failure_and_missing_suite, test_AC24_the_suite_list_matches_the_plan, test_AC24_scripts_diff_adds_shell_and_suites |
| check_suites | a failure stops it and says how to run the suite alone; same inputs: CACHED; a failure is not recorded; `--no-cache` | test_gate_stops_at_the_first_failure, test_ledger_runs_a_suite_once_per_state |
| suite_selected | only the suites whose inputs changed run; a script with no suite runs none; `settings.json` alone | test_gate_runs_only_the_suite_of_what_changed |

## scripts/validate.sh: tracked local files of the secrets check

| Function | Decision or error path | Test |
| --- | --- | --- |
| tracked_local_files | whole target: tracked at any depth, staged or committed; untracked and lookalikes (`.env.example`): nothing | test_secrets_fail_on_a_tracked_env_file |
| tracked_local_files | `--path`: only what is inside the target, in the repo that holds it; a root scan leaves a project's repo alone | test_secrets_tracked_env_follows_the_target |
| tracked_local_files | `--files`: only the listed files inside the target, each in its own repo; a listed untracked one: nothing | test_secrets_tracked_env_with_files_judges_only_the_list |
| tracked_local_files | not a git repo; no `git`: nothing | test_secrets_tracked_env_is_skipped_outside_git |
| run_check (secrets) | a tracked file fails whatever the scan says; the scan still runs; other checks do not look | test_secrets_fail_on_a_tracked_env_file, test_gate_fails_on_a_tracked_env_file |
| check_key | `--files`: a listed file that becomes tracked is not CACHED | test_ledger_sees_a_listed_env_file_become_tracked |
