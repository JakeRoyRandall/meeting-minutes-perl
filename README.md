# This Could Have Been a Regex

A bounded Perl utility for 2020-style remote meeting notes. It counts lines and words, approximates speaker airtime by speaker-labelled lines, extracts TODO/ACTION/FOLLOW-UP lines, and optionally redacts common email and phone shapes. Created September 2026 retrospectively; this is not historical 2020 work.

```sh
perl this-could-have-been-a-regex.pl --redact notes.txt
perl this-could-have-been-a-regex.pl --actions-only --speaker Ada notes.txt
printf 'Ada: TODO send notes\nBob: agreed\n' | perl this-could-have-been-a-regex.pl --json -
prove -v *.t
```

The tool uses simple text patterns. It does not identify speakers in unlabelled prose, measure actual speaking time, parse calendars, or provide a privacy guarantee. Redaction is only a convenience for common email and phone formats; review output before sharing.

Input is bounded to 1 MiB of raw bytes for both files and stdin. The reader stops after checking at most one byte beyond that limit, then validates UTF-8; direct `summarize` callers receive the same size guard.

`--actions-only` prints only extracted action lines with their original 1-based line numbers. `--speaker NAME` restricts speaker-labelled actions and speaker counts to an exact existing label; the name is decoded and trimmed as UTF-8, with a 40-character limit. Unlabelled action lines are excluded when a speaker filter is active. The same filtered action list and `action_lines` records are included in JSON, along with the normal summary fields. These filters compose with `--redact`: matching uses the original label, displayed labels/content are redacted, and JSON reports only `"[speaker filter redacted]"` instead of echoing a potentially sensitive filter name.
