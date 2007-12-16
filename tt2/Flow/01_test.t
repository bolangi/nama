#!/usr/bin/env perl
use Text::Template::Preprocess;
use Carp;
use warnings;
use strict;

my $debug = 1;
my $write_file = 1;
my $filename = qw( Grammar.p );
my $source_generator_script = 'emit-grammar';
my $source  = $source_generator_script;
my $result = qx(perl -w emit-grammar);
print $result; 
