# This Could Have Been a Regex

A bounded Perl utility for 2020-style remote meeting notes. It counts lines and words, approximates speaker airtime by speaker-labelled lines, extracts TODO/ACTION/FOLLOW-UP lines, and optionally redacts common email and phone shapes. Created September 2026 retrospectively; this is not historical 2020 work.

```sh
perl this-could-have-been-a-regex.pl --redact notes.txt
perl this-could-have-been-a-regex.pl --actions-only --speaker Ada notes.txt
perl this-could-have-been-a-regex.pl --markdown notes.txt
perl this-could-have-been-a-regex.pl --json --dedupe-actions notes.txt
perl this-could-have-been-a-regex.pl --contains "launch" notes.txt
perl this-could-have-been-a-regex.pl --count-only --contains "launch" notes.txt
perl this-could-have-been-a-regex.pl --csv --dedupe-actions notes.txt
perl this-could-have-been-a-regex.pl --actions-only --lines 20:40 notes.txt
printf 'Ada: TODO send notes\nBob: agreed\n' | perl this-could-have-been-a-regex.pl --json -
(cd app && prove -v t)
```

The tool uses simple text patterns. It does not identify speakers in unlabelled prose, measure actual speaking time, parse calendars, or provide a privacy guarantee. Redaction is only a convenience for common email and phone formats; review output before sharing.

Input is bounded to 1 MiB of raw bytes for both files and stdin. The reader stops after checking at most one byte beyond that limit, then validates UTF-8; direct `summarize` callers receive the same size guard.

`--actions-only` prints only extracted action lines with their original 1-based line numbers. `--speaker NAME` restricts speaker-labelled actions and speaker counts to an exact existing label; the name is decoded and trimmed as UTF-8, with a 40-character limit. Unlabelled action lines are excluded when a speaker filter is active. The same filtered action list and `action_lines` records are included in JSON, along with the normal summary fields. These filters compose with `--redact`: matching uses the original label, displayed labels/content are redacted, and JSON reports only `"[speaker filter redacted]"` instead of echoing a potentially sensitive filter name.

`--markdown` renders a printable handoff with summary counts, an escaped speaker table, and an action checklist annotated with original line numbers. It composes with `--speaker` and `--redact`; with `--actions-only`, it emits only the checklist. `--json` and `--markdown` cannot be used together. Pipes, brackets, backticks, emphasis markers, entities, and line breaks in names or actions are escaped or normalized so they cannot change the report structure.

`--dedupe-actions` is opt-in. It collapses exact action text repeated by the same displayed speaker while preserving the first line, an array of every occurrence line in `action_lines`, and a `count`; unlabelled actions remain separate. Filtering and redaction happen before this comparison. Text and Markdown reports identify repeated line numbers, while the default output remains unchanged.

`--contains TEXT` is an optional case-insensitive literal filter for visible action content. The value is decoded as UTF-8, trimmed, and limited to 200 characters; it is never treated as a regular expression. It runs after redaction and speaker filtering but before deduplication, so JSON records preserve source line numbers and report the visible search text. With `--redact`, JSON reports `"[search filter redacted]"` instead of echoing the filter value.

`--csv` exports actions with fixed `line,speaker,text,count,lines` columns using RFC 4180 quoting and CRLF records. It uses the active speaker/contains/redaction/dedupe filters; without deduplication, `count` and `lines` are both the first line only. `--actions-only` is accepted but redundant. CSV cannot be combined with `--json` or `--markdown`.

`--lines START:END` restricts action extraction to an inclusive positive source-line interval (each endpoint is at most 1,000,000). Endpoints beyond the input are allowed and can produce an empty action list; malformed or reversed intervals are rejected. Counts and speaker summaries still describe the full input. The window is applied before `--contains` and deduplication, and composes with all output modes.

`--count-only` prints only `actions: N`, where `N` is the action-record count after `--speaker`, `--lines`, `--contains`, and optional `--dedupe-actions` processing. It cannot be combined with JSON, Markdown, or CSV.
