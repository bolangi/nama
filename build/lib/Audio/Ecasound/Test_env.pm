package Audio::Ecasound::Flow;
use strict;
use lib '/home/jroth/flow/build/lib';
sub c{print "hello from flow"}

package main;

&Audio::Ecasound::Flow::c;

