#!/bin/sh
# 
# Run this script to obtain required modules if you 
# are not installing this module via CPAN
#
cpan -i\
Tk\
IO::All\
Carp\
Cwd\
Storable\
Getopt::Std\
Audio::Ecasound\
Parse::RecDescent\
Term::ReadLine\
Data::YAML\
File::Find::Rule\
File::Spec::Link
