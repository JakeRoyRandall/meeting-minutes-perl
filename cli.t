use strict; use warnings; use Test::More;
my $out=qx{printf 'Ada: café\\n' | $^X ./this-could-have-been-a-regex.pl -}; like $out,qr/lines: 1/,'pipe CLI'; like $out,qr/Ada: 1/,'speaker CLI'; done_testing;
