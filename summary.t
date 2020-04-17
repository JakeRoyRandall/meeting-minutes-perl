use strict; use warnings; use Test::More;
require './this-could-have-been-a-regex.pl';
my $r=main::summarize("Ada: hello\nBob: café\n");
is $r->{lines},2,'physical lines'; is $r->{words},4,'words'; is_deeply $r->{speakers},{Ada=>1,Bob=>1},'speakers'; is main::summarize('',0)->{lines},0,'empty'; done_testing;
