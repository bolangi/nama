#!/usr/bin/env perl
package Audio::Ecasound::Flow;
use strict;
use lib '/home/jroth/ecmd-dev';
use Audio::Ecasound::Flow;

### Option Processing ###
use vars qw(%opts $session_name $debug);
getopts('mceg', \%opts); 
$session_name = shift;
$debug and print "session name: $session_name\n";
&prepare;
&loopg;


