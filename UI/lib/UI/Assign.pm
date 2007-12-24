package UI::Assign;

use 5.008;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Assign ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(

		assign_vars
		store_vars
		yaml_out
		yaml_in
		create_dir
		join_path
		wav_off
		strip_all
		strip_blank_lines
		strip_comments
		remove_spaces

	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

use Carp;
use Data::YAML::Reader;
use Data::YAML::Writer;
use vars qw($debug $debug2);
my $yw = Data::YAML::Writer->new;
my $yr = Data::YAML::Reader->new;
$debug = 1;
$debug2 = 1;
=comment
my $text = <<HERE;
a line # with a comment



blank lines above # another comment 
yaml_out: what i never expected
HERE
#print &strip_comments($text);
#print &strip_blank_lines($text);
#print &strip_all($text);
use vars qw( $foo @face $name %dict);
my $struct = { 
	foo => 2, 
	name => 'John', 
	face => [1,5,7,12],
	dict => {fruit => 'melon'}
};	

my @var_list = qw( $foo @face $name %dict);

assign($struct, @var_list);
print yaml_out(\%dict);
#for (@var_list) { !/\$/ and print yaml_out( eval "\\$_") }
exit;

## testing never passed

use Test::More qw(no_plan);
is( $foo, 2, "Scalar number assignment");
is( $name, 'John', "Scalar string assignment");
my $sum;
map{ $sum += $_ } @{ $face };
is ($sum, 25, "Array assignment");
is( $dict->{fruit}, 'melon', "Hash assignment");
----
my @files = qw(
/media/sessions/.ecmd/State
/media/sessions/.ecmd/atsuko-d/State
/media/sessions/.ecmd/atsuko-e/State
/media/sessions/.ecmd/malone/State
/media/sessions/.ecmd/paul_a/State
/media/sessions/.ecmd/paul_brocante/State
/media/sessions/.ecmd/ryan_taisho_b/State
/media/sessions/.ecmd/self-test/State
);
map{ my $r = retrieve($_) ;
	print "found: ", ref $r, $/;
	assign( $r, @persistent_vars);
	#print join $/, keys %{$r->{state_c}};
	#print join $/, keys %state_c;
	#
	print yaml_out(\%state_c);
	exit;
	} @files;
----
=cut




sub assign{
	local $debug = 1;
	$debug2 and print "&assign\n";
	my ($ref, @vars) = @_;
	my %sigil;
	map{ 
		my ($s, $identifier) = /(.)(\w+)/;
		$sigil{$identifier} = $s;
	} @vars;
	#print yaml_out(\%sigil); exit;
	#print join " ", "Variables:\n", @vars, $/ ;
	croak "expected hash" if ref $ref !~ /HASH/;
	my @keys =  keys %{ $ref };
	$debug and print join " ","found keys: ", keys %{ $ref },"\n---\n";
	map{  
		my $eval;
		my $key = $_;
		$sigil{$key} or croak 
			"didn't find a match for $key in ", join " ", @vars, $/;
		my $full = $sigil{$key}.$key;
		print "full: $full\n";;
		my ($sigil, $identifier) = ($sigil{$key}, $key);
		$eval .= $full;
		$eval .= q( = );
		my $val;
		if ($sigil eq '$') { # scalar assignment

			if ($ref->{$identifier}) {
				$val = $ref->{$identifier};
				$val =~ /^[\.\d]+$/ or $val = qq("$val");
				ref $val and croak "didn't expect reference: ",ref $val, $/;
			} 
			else { $val = q(undef) };

			$eval .=  $val;

		} else { # array, hash assignment
			$eval .= qq($sigil\{);
			$eval .= q($ref->{ );
			$eval .= qq("$identifier");
			$eval .= q( } );
			$eval .= q( } );
		}
		$debug and print $eval, $/, $/;
		eval $eval or $val and carp "failed to eval $eval: $!\n";
	} @keys
}

sub assign_vars {
	my ($source, @vars) = @_;
	$debug2 and print "&assign_vars\n";
	local $debug = 1;
	# assigns vars in @var_list to values from $source
	# $source can be a :
	#      - filename or
	#      - string containing YAML data
	#      - reference to a hash array containing assignments
	#
	# returns a $ref containing the retrieved data structure
	$debug and print "file: $source\n";
	$debug and print "variable list: @vars\n";
	my $ref;

### figure out what to do with input

	-f $source and $source eq 'State' 
		and $debug and print ("found Storable file: $source\n")
		and $ref = retrieve($source) # Storable

	## check for a filename

	or -f $source and $source =~ /.yaml$/ 
		and $debug and print "found a yaml file: $source\n"
		and $ref = yaml_in($source)
 	
	## check for a string

	or  $source =~ /^\s*---/s 
		and $debug and print "found yaml as text\n"
		and $ref = $yr->($source)

	## pass a hash_ref to the assigner

	or ref $source 
		and $debug and print "found a reference\n"
		and $ref = $source;


	assign($ref, @vars);

}


sub store_vars {
	local $debug = 1;
	# now we will only store in YAML
	$debug2 and print "&store_vars\n";
	my ($file, @vars) = @_;
	$file .= '.yaml' unless $file =~ /\.yaml$/;
	$debug and print "vars: @vars\n";
	$debug and print "file: $file\n";
	my %state;
	map{ my ($sigil, $identifier) = /(.)(\w+)/; 
		 my $eval_string =  q($state{)
							. $identifier
							. q(} = \\) # double backslash needed
							. $_;
	$debug and print "attempted to eval $eval_string\n";
	eval($eval_string) or print "failed to eval $eval_string: $!\n";
	} @vars;
	# my $result1 = store \%state, $file; # OLD METHOD
	my $yamlout = yaml_out(\%state);
	$yamlout > io $file;

}
sub yaml_out {
	$debug2 and print "&yaml_out\n";
	my ($data_ref) = shift; 
	my $type = ref $data_ref;
	$debug and print "data ref type: $type\n "; 
	carp "can't yaml-out a Scalar!!\n" if ref $data_ref eq 'SCALAR';
	croak "attempting to code wrong data type: $type"
		if $type !~ /HASH|ARRAY/;
	my $output;
    $yw->write( $data_ref, \$output ); 
	$output;
}
sub yaml_in {
	my $file = shift;
	my $yaml = io($file)->all;
	$yr->read( $yaml ); # returns ref
}
## support functions

sub create_dir {
	my $dir = shift;
	-e $dir and 
		(carp "create_dir: '$dir' already exists, skipping...\n"), 
		return;
	mkdir $dir
	or carp qq(failed to create directory "$dir": $!\n);
}

sub join_path {
	no warnings;
	my @parts = @_;
	my $path = join '/', @parts;
	$path =~ s(/{2,})(/)g;
	$debug and print "path: $path\n";
	$path;
	use warnings;
}

sub wav_off {
	my $wav = shift;
	$wav =~ s/\.wav\s*$//i;
	$wav;
}

sub strip_all{ strip_blank_lines( strip_comments(@_) ) }

sub strip_blank_lines {
	map{ s/\n(\s*\n)+/\n/sg } @_;
	@_;
	 
}

sub strip_comments { #  
	map{ s/#.*$//mg; } @_;
	@_
} 

sub remove_spaces {                                                             
        my $entry = shift;                                                      
        # remove leading and trailing spaces                                    
                                                                                
        $entry =~ s/^\s*//;                                                     
        $entry =~ s/\s*$//;                                                     
                                                                                
        # convert other spaces to underscores                                   
                                                                                
        $entry =~ s/\s+/_/g;                                                    
        $entry;                                                                 
}                                                                               
1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Assign - Perl extensions for persistent variables and utility functions

=head1 SYNOPSIS

		assign_vars( $hash_ref, @variable_list)
		store_vars( $hash_ref, $file)??
		yaml_out( $hash_ref )
		yaml_in( $string )
		create_dir( $path )
		join_path( $dir1, $subdir, $subsubdir)
		wav_off( "sax_3.wav")
		strip_all
		strip_blank_lines
		strip_comments
		remove_spaces


  use Assign;

=head1 ABSTRACT

=head1 DESCRIPTION

=head2 EXPORT

None by default.

=head1 SEE ALSO

=head1 AUTHOR

Joel Roth, E<lt>jroth@pobox.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Joel Roth

=cut
