#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Getopt::Long qw(GetOptions);
use Encode qw(decode encode FB_CROAK);
use JSON::PP;
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
our $MAX_INPUT_BYTES = 1_048_576;

sub run_cli {
    my ($json, $redact, $actions_only, $markdown, $csv, $count_only, $dedupe_actions, $speaker_filter, $contains, $lines_filter, $help);
    GetOptions('json' => \$json, 'redact' => \$redact, 'actions-only' => \$actions_only, 'markdown' => \$markdown, 'csv' => \$csv, 'count-only' => \$count_only, 'dedupe-actions' => \$dedupe_actions, 'speaker=s' => \$speaker_filter, 'contains=s' => \$contains, 'lines=s' => \$lines_filter, 'help' => \$help) or usage(2);
    cli_fail('--json, --markdown, and --csv are mutually exclusive') if scalar(grep { $_ } ($json, $markdown, $csv)) > 1;
    cli_fail('--count-only cannot be combined with --json, --markdown, or --csv') if $count_only && ($json || $markdown || $csv);
    if (defined $speaker_filter) { eval { $speaker_filter = decode('UTF-8', $speaker_filter, FB_CROAK); 1 } or cli_fail('--speaker is not valid UTF-8'); $speaker_filter =~ s/^\s+|\s+$//g; cli_fail('--speaker needs a nonempty name') if $speaker_filter eq ''; cli_fail('--speaker is limited to 40 characters') if length($speaker_filter) > 40; }
    if (defined $contains) { eval { $contains = decode('UTF-8', $contains, FB_CROAK); 1 } or cli_fail('--contains is not valid UTF-8'); $contains =~ s/^\s+|\s+$//g; cli_fail('--contains needs a nonempty value') if $contains eq ''; cli_fail('--contains is limited to 200 characters') if length($contains) > 200; }
    my $line_window;
    if (defined $lines_filter) { cli_fail('--lines must be START:END with positive integers') unless $lines_filter =~ /\A([1-9]\d{0,6}):([1-9]\d{0,6})\z/; my ($start, $end) = ($1, $2); cli_fail('--lines endpoints are limited to 1,000,000') if $start > 1_000_000 || $end > 1_000_000; cli_fail('--lines START must not exceed END') if $start > $end; $line_window = [$start, $end]; }
    usage(0) if $help; usage(2) if @ARGV > 1;
    my $text = ''; my $raw = '';
    if (@ARGV && $ARGV[0] ne '-') { open my $fh, '<:raw', $ARGV[0] or cli_fail("cannot read $ARGV[0]: $!"); $raw = read_bounded($fh, $ARGV[0]); close $fh or cli_fail("cannot close $ARGV[0]: $!"); }
    else { binmode STDIN, ':raw'; $raw = read_bounded(\*STDIN, 'stdin'); }
    eval { $text = decode('UTF-8', $raw, FB_CROAK); 1 } or cli_fail('input is not valid UTF-8');
    my $report = summarize($text, $redact, $speaker_filter, $dedupe_actions, $contains, $line_window);
    $report->{actions_only} = $actions_only ? JSON::PP::true : JSON::PP::false;
    $report->{dedupe_actions} = $dedupe_actions ? JSON::PP::true : JSON::PP::false;
    $report->{contains} = $redact ? '[search filter redacted]' : $contains if defined $contains;
    $report->{lines_filter} = $lines_filter if defined $lines_filter;
    $report->{speaker_filter} = $redact ? '[speaker filter redacted]' : $speaker_filter if defined $speaker_filter;
    $json ? print(JSON::PP->new->utf8(0)->encode($report), "\n") : ($count_only ? print "actions: " . scalar(@{$report->{action_lines}}) . "\n" : ($csv ? print_csv($report) : ($markdown ? print_markdown($report) : ($actions_only ? print_actions_only($report) : print_report($report)))));
}
run_cli() unless caller;
sub cli_fail { print STDERR "error: $_[0]\n"; exit 2; }

sub read_bounded {
    my ($fh, $source) = @_;
    my $raw = ''; my $chunk = '';
    while (length($raw) <= $MAX_INPUT_BYTES) {
        my $remaining = $MAX_INPUT_BYTES + 1 - length($raw); my $want = $remaining < 65_536 ? $remaining : 65_536;
        my $read = read($fh, $chunk, $want);
        cli_fail("cannot read $source: $!") unless defined $read;
        last if $read == 0;
        $raw .= substr($chunk, 0, $read);
    }
    cli_fail("input exceeds $MAX_INPUT_BYTES bytes: $source") if length($raw) > $MAX_INPUT_BYTES;
    return $raw;
}

sub usage {
    my ($code) = @_;
    print STDERR "usage: this-could-have-been-a-regex.pl [--json] [--redact] [--actions-only] [--markdown] [--csv] [--count-only] [--dedupe-actions] [--speaker NAME] [--contains TEXT] [--lines START:END] [FILE|-]\n" if $code;
    print "usage: this-could-have-been-a-regex.pl [--json] [--redact] [--actions-only] [--markdown] [--csv] [--count-only] [--dedupe-actions] [--speaker NAME] [--contains TEXT] [--lines START:END] [FILE|-]\n" unless $code;
    exit $code;
}

sub summarize {
    my ($input, $do_redact, $speaker_filter, $dedupe_actions, $contains, $line_window) = @_;
    die "input exceeds $MAX_INPUT_BYTES bytes" if length(encode('UTF-8', $input)) > $MAX_INPUT_BYTES;
    my @lines = length($input) ? split(/\n/, $input, -1) : ();
    pop @lines if @lines && $input =~ /\n\z/;
    my (%speakers, @actions, @action_lines); my $words = 0;
    for my $line_index (0 .. $#lines) {
        my $line = $lines[$line_index]; my $line_number = $line_index + 1;
        my $original_speaker;
        if ($line =~ /^\s*([^:]{1,40}):/) { $original_speaker = $1; $original_speaker =~ s/^\s+|\s+$//g; }
        my $shown = $line;
        $shown =~ s/\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b/[email redacted]/g if $do_redact;
        $shown =~ s/\b(?:\+?\d[\d .()-]{7,}\d)\b/[phone redacted]/g if $do_redact;
        $words += () = ($shown =~ /\S+/g);
        if ($shown =~ /^\s*([^:]{1,40}):\s*(.*)$/) {
            my ($speaker, $utterance) = ($1, $2); $speaker =~ s/^\s+|\s+$//g;
            if ($speaker =~ /^(?:TODO|ACTION|FOLLOW[- ]?UP)$/i) {
                if (!defined $speaker_filter) { push @actions, $utterance; push @action_lines, { line => $line_number, text => $utterance }; }
            } else {
                my $speaker_matches = !defined($speaker_filter) || (defined($original_speaker) && $original_speaker eq $speaker_filter);
                $speakers{$speaker}++ if $speaker_matches;
                if ($utterance =~ /^\s*(?:TODO|ACTION|FOLLOW[- ]?UP)\b\s*:?[ \t]*(.*)$/i && $speaker_matches) {
                    push @actions, $1; push @action_lines, { line => $line_number, text => $1, speaker => $speaker };
                }
            }
        } elsif ($shown =~ /^\s*(?:[-*]\s*)?\b(?:TODO|ACTION|FOLLOW[- ]?UP)\b\s*:?(.*)$/i) {
            my $action = $1 =~ s/^\s+//r;
            if (!defined $speaker_filter) { push @actions, $action; push @action_lines, { line => $line_number, text => $action }; }
        }
    }
    if (defined $line_window) {
        @action_lines = grep { $_->{line} >= $line_window->[0] && $_->{line} <= $line_window->[1] } @action_lines;
        @actions = map { $_->{text} } @action_lines;
    }
    if (defined $contains) {
        my $needle = lc $contains;
        @action_lines = grep { index(lc($_->{text}), $needle) >= 0 } @action_lines;
        @actions = map { $_->{text} } @action_lines;
    }
    if ($dedupe_actions) {
        my $deduped = dedupe_action_records(\@action_lines);
        @action_lines = @$deduped;
        @actions = map { $_->{text} } @action_lines;
    }
    return { lines => scalar(@lines), words => $words, speakers => \%speakers, actions => \@actions, action_lines => \@action_lines, redacted => $do_redact ? JSON::PP::true : JSON::PP::false };
}

sub dedupe_action_records {
    my ($records) = @_;
    my (@out, %first_for_speaker);
    for my $record (@$records) {
        my $bucket = exists $record->{speaker} ? ($first_for_speaker{$record->{speaker}} ||= {}) : undef;
        if (defined($bucket) && exists $bucket->{$record->{text}}) {
            my $existing = $out[$bucket->{$record->{text}}];
            push @{$existing->{lines}}, $record->{line};
            $existing->{count}++;
        } else {
            my $copy = { %$record, lines => [ $record->{line} ], count => 1 };
            push @out, $copy;
            $bucket->{$record->{text}} = $#out if defined $bucket;
        }
    }
    return \@out;
}

sub print_actions_only {
    my ($r) = @_;
    print "This Could Have Been a Regex · actions only\n";
    for my $action (@{$r->{action_lines}}) {
        my $occurrences = $r->{dedupe_actions} && $action->{count} > 1 ? " (repeated on lines " . join(', ', @{$action->{lines}}[1 .. $#{$action->{lines}}]) . "; $action->{count} occurrences)" : '';
        print "line $action->{line}: - $action->{text}$occurrences\n";
    }
}

sub csv_field {
    my ($value) = @_;
    $value //= '';
    $value =~ s/"/""/g;
    return '"' . $value . '"';
}

sub print_csv {
    my ($r) = @_;
    print "line,speaker,text,count,lines\r\n";
    for my $action (@{$r->{action_lines}}) {
        my $count = $r->{dedupe_actions} ? $action->{count} : 1;
        my $lines = $r->{dedupe_actions} ? join(';', @{$action->{lines}}) : $action->{line};
        print join(',', map { csv_field($_) } ($action->{line}, $action->{speaker} // '', $action->{text}, $count, $lines)), "\r\n";
    }
}

sub markdown_escape {
    my ($value) = @_;
    $value =~ s/([\\`|*_{}\[\]()#+.!<>~&-])/\\$1/g;
    $value =~ s/[\r\n]+/ /g;
    return $value;
}

sub print_markdown {
    my ($r) = @_;
    print "# Meeting handoff\n\n";
    if (!$r->{actions_only}) {
        print "- **Lines:** $r->{lines}\n- **Words:** $r->{words}\n\n";
    }
    if (!$r->{actions_only}) {
        print "## Speakers\n\n| Speaker | Labelled lines |\n| --- | ---: |\n";
        print '| ', markdown_escape($_), ' | ', $r->{speakers}{$_}, " |\n" for sort keys %{$r->{speakers}};
        print "\n";
    }
    print "## Action checklist\n\n";
    for my $action (@{$r->{action_lines}}) {
        my $line_note = "line $action->{line}";
        $line_note .= "; repeated on lines " . join(', ', @{$action->{lines}}[1 .. $#{$action->{lines}}]) . "; $action->{count} occurrences" if $r->{dedupe_actions} && $action->{count} > 1;
        print "- [ ] ", markdown_escape($action->{text}), " _($line_note)_\n";
    }
    print "\n_No compiler, sentiment model, or privacy guarantee involved._\n";
}

sub print_report {
    my ($r) = @_;
    print "This Could Have Been a Regex\nlines: $r->{lines}\nwords: $r->{words}\n";
    print "speaker airtime approximation (lines):\n";
    print "  $_: $r->{speakers}{$_}\n" for sort keys %{$r->{speakers}};
    print "actions / TODOs:\n";
    for my $action (@{$r->{action_lines}}) {
        my $occurrences = $r->{dedupe_actions} && $action->{count} > 1 ? " (repeated on lines " . join(', ', @{$action->{lines}}[1 .. $#{$action->{lines}}]) . "; $action->{count} occurrences)" : '';
        print "  - $action->{text}$occurrences\n";
    }
    print "(No compiler, sentiment model, or privacy guarantee involved.)\n";
}

1;
