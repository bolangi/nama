#!/usr/bin/env perl
use IO::All;
my $source = 'Flow.p';
my @lines = io($source)->slurp;
$debug and print "lines: ". scalar @lines, $/;
my $sub_re = qr/^sub\s+(\w+)/;
@subs = map{ /$sub_re/; $1 } grep {/$sub_re/} @lines;
$debug and print "subs:". scalar @subs, $/; 
print join $/, @subs;
