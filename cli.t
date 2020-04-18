use strict; use warnings; use utf8; use Test::More; use File::Temp qw(tempfile); use JSON::PP;
my ($fh, $path) = tempfile(); binmode $fh, ':encoding(UTF-8)'; print $fh "Zoë: TODO café\n"; close $fh;
my $script = './this-could-have-been-a-regex.pl';
my $file = qx{$^X $script --json $path}; my $pipe = qx{printf 'Zoë: TODO café\\n' | $^X $script --json -};
my $a = decode_json($file); my $b = decode_json($pipe);
is_deeply $a, $b, 'UTF-8 file and stdin JSON agree';
is $a->{speakers}{'Zoë'}, 1, 'Unicode speaker survives CLI';
is_deeply $a->{actions}, ['café'], 'Unicode action survives CLI';
unlink $path; done_testing;
