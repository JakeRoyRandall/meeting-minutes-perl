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
    my ($json, $redact, $actions_only, $markdown, $speaker_filter, $help);
    GetOptions('json' => \$json, 'redact' => \$redact, 'actions-only' => \$actions_only, 'markdown' => \$markdown, 'speaker=s' => \$speaker_filter, 'help' => \$help) or usage(2);
    cli_fail('--json and --markdown cannot be combined') if $json && $markdown;
    if (defined $speaker_filter) { eval { $speaker_filter = decode('UTF-8', $speaker_filter, FB_CROAK); 1 } or cli_fail('--speaker is not valid UTF-8'); $speaker_filter =~ s/^\s+|\s+$//g; cli_fail('--speaker needs a nonempty name') if $speaker_filter eq ''; cli_fail('--speaker is limited to 40 characters') if length($speaker_filter) > 40; }
    usage(0) if $help; usage(2) if @ARGV > 1;
    my $text = ''; my $raw = '';
    if (@ARGV && $ARGV[0] ne '-') { open my $fh, '<:raw', $ARGV[0] or cli_fail("cannot read $ARGV[0]: $!"); $raw = read_bounded($fh, $ARGV[0]); close $fh or cli_fail("cannot close $ARGV[0]: $!"); }
    else { binmode STDIN, ':raw'; $raw = read_bounded(\*STDIN, 'stdin'); }
    eval { $text = decode('UTF-8', $raw, FB_CROAK); 1 } or cli_fail('input is not valid UTF-8');
    my $report = summarize($text, $redact, $speaker_filter);
    $report->{actions_only} = $actions_only ? JSON::PP::true : JSON::PP::false;
    $report->{speaker_filter} = $redact ? '[speaker filter redacted]' : $speaker_filter if defined $speaker_filter;
    $json ? print(JSON::PP->new->utf8(0)->encode($report), "\n") : ($markdown ? print_markdown($report) : ($actions_only ? print_actions_only($report) : print_report($report)));
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
    print STDERR "usage: this-could-have-been-a-regex.pl [--json] [--redact] [--actions-only] [--markdown] [--speaker NAME] [FILE|-]\n" if $code;
    print "usage: this-could-have-been-a-regex.pl [--json] [--redact] [--actions-only] [--markdown] [--speaker NAME] [FILE|-]\n" unless $code;
    exit $code;
}

sub summarize {
    my ($input, $do_redact, $speaker_filter) = @_;
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
    return { lines => scalar(@lines), words => $words, speakers => \%speakers, actions => \@actions, action_lines => \@action_lines, redacted => $do_redact ? JSON::PP::true : JSON::PP::false };
}

sub print_actions_only {
    my ($r) = @_;
    print "This Could Have Been a Regex · actions only\n";
    print "line $_->{line}: - $_->{text}\n" for @{$r->{action_lines}};
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
    print "- [ ] ", markdown_escape($_->{text}), " _(line $_->{line})_\n" for @{$r->{action_lines}};
    print "\n_No compiler, sentiment model, or privacy guarantee involved._\n";
}

sub print_report {
    my ($r) = @_;
    print "This Could Have Been a Regex\nlines: $r->{lines}\nwords: $r->{words}\n";
    print "speaker airtime approximation (lines):\n";
    print "  $_: $r->{speakers}{$_}\n" for sort keys %{$r->{speakers}};
    print "actions / TODOs:\n";
    print "  - $_\n" for @{$r->{actions}};
    print "(No compiler, sentiment model, or privacy guarantee involved.)\n";
}

1;
