#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Encode qw(decode FB_CROAK);
use JSON::PP;
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

sub run_cli {
    my ($json, $redact, $help);
    GetOptions('json' => \$json, 'redact' => \$redact, 'help' => \$help) or usage(2);
    usage(0) if $help; usage(2) if @ARGV > 1;
    my $text = ''; my $raw = '';
    if (@ARGV && $ARGV[0] ne '-') { open my $fh, '<:raw', $ARGV[0] or cli_fail("cannot read $ARGV[0]: $!"); local $/; $raw = <$fh> // ''; close $fh; }
    else { binmode STDIN, ':raw'; local $/; $raw = <STDIN> // ''; }
    eval { $text = decode('UTF-8', $raw, FB_CROAK); 1 } or cli_fail('input is not valid UTF-8');
    my $report = summarize($text, $redact);
    $json ? print(JSON::PP->new->utf8(0)->encode($report), "\n") : print_report($report);
}
run_cli() unless caller;
sub cli_fail { print STDERR "error: $_[0]\n"; exit 2; }

sub usage {
    my ($code) = @_;
    print STDERR "usage: this-could-have-been-a-regex.pl [--json] [--redact] [FILE|-]\n" if $code;
    print "usage: this-could-have-been-a-regex.pl [--json] [--redact] [FILE|-]\n" unless $code;
    exit $code;
}

sub summarize {
    my ($input, $do_redact) = @_;
    my @lines = length($input) ? split(/\n/, $input, -1) : ();
    pop @lines if @lines && $input =~ /\n\z/;
    my (%speakers, @actions); my $words = 0;
    for my $line (@lines) {
        my $shown = $line;
        $shown =~ s/\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b/[email redacted]/g if $do_redact;
        $shown =~ s/\b(?:\+?\d[\d .()-]{7,}\d)\b/[phone redacted]/g if $do_redact;
        $words += () = ($shown =~ /\S+/g);
        if ($shown =~ /^\s*([^:]{1,40}):\s*(.*)$/) {
            my ($speaker, $utterance) = ($1, $2); $speaker =~ s/^\s+|\s+$//g;
            if ($speaker =~ /^(?:TODO|ACTION|FOLLOW[- ]?UP)$/i) { push @actions, $utterance; }
            else { $speakers{$speaker}++; push @actions, $1 if $utterance =~ /^\s*(?:TODO|ACTION|FOLLOW[- ]?UP)\b\s*:?[ \t]*(.*)$/i; }
        } elsif ($shown =~ /^\s*(?:[-*]\s*)?\b(?:TODO|ACTION|FOLLOW[- ]?UP)\b\s*:?(.*)$/i) {
            push @actions, $1 =~ s/^\s+//r;
        }
    }
    return { lines => scalar(@lines), words => $words, speakers => \%speakers, actions => \@actions, redacted => $do_redact ? JSON::PP::true : JSON::PP::false };
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
