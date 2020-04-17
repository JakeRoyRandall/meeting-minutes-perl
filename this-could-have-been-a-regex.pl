#!/usr/bin/env perl
use strict;
use warnings;
use Encode qw(decode FB_CROAK);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
sub usage {
    print "usage: this-could-have-been-a-regex.pl [FILE|-]\n";
    exit $_[0];
}
sub cli_fail { print STDERR "error: $_[0]\n"; exit 2; }
sub summarize {
    my ($input) = @_;
    my @lines = length($input) ? split(/\n/, $input, -1) : ();
    pop @lines if @lines && $input =~ /\n\z/;
    my (%speakers, $words);
    $words = 0;
    for my $line (@lines) {
        $words += () = ($line =~ /\S+/g);
        if ($line =~ /^\s*([^:]{1,40}):/) {
            my $speaker = $1;
            $speaker =~ s/^\s+|\s+$//g;
            $speakers{$speaker}++;
        }
    }
    return {lines => scalar(@lines), words => $words, speakers => \%speakers};
}
sub run {
    usage(0) if @ARGV && $ARGV[0] eq '--help';
    usage(2) if @ARGV > 1 || (@ARGV && $ARGV[0] =~ /^-/ && $ARGV[0] ne '-');
    my $raw = '';
    if (@ARGV && $ARGV[0] ne '-') {
        open my $file, '<:raw', $ARGV[0] or cli_fail("cannot read $ARGV[0]: $!");
        local $/;
        $raw = <$file> // '';
        close $file;
    } else {
        binmode STDIN, ':raw';
        local $/;
        $raw = <STDIN> // '';
    }
    my $text;
    eval { $text = decode('UTF-8', $raw, FB_CROAK); 1 } or cli_fail('input is not valid UTF-8');
    my $report = summarize($text);
    print "This Could Have Been a Regex\nlines: $report->{lines}\nwords: $report->{words}\nspeaker airtime approximation (lines):\n";
    print "  $_: $report->{speakers}{$_}\n" for sort keys %{$report->{speakers}};
    print "Counts are literal; labelled lines are not elapsed speaking time.\n";
}
run() unless caller;
1;
