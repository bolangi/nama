=comment

package ::;
# unless i know the calling package name, how do I know
# what the eval should be?
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
		
		serialize	
		serial
		assign_big
		assign
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
=cut

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
#for (@var_list) { !/\$/ and print yaml_out( eval "\\$_") }
exit;
=cut



use Test::More qw(no_plan);
diag "TESTING $0\n";
use vars qw( $foo @face $name %dict);
my @var_list = qw( $foo @face $name %dict);
my $struct2 = { 
	'$foo' => 2, 
	'$name' => 'John', 
	'@face' => [1,5,7,12],
	'%dict' => {fruit => 'melon'}
};	
my $struct = { 
	foo => 2, 
	name => 'John', 
	face => [1,5,7,12],
	dict => {fruit => 'melon'}
};	
assign_big (DATA => $struct, CLASS => 'main', VARS => \@var_list);
#assign($struct, @var_list);
	#print yaml_out(\%dict); 
	#print yaml_out($struct);
	#print serial( @var_list);  # store_vars output as string
	my $serialized = serial( @var_list);  # store_vars output as string
	#$serialized > io ('test.serializing');
	#	print $serialized;

my $expected = <<WANT;
---
dict:
  fruit: melon
face:
  - 1
  - 5
  - 7
  - 12
foo: 2
name: John
...
WANT

is ($serialized, $expected, "Data serialization round trip");
is( $foo, 2, "Scalar number assignment");
is( $name, 'John', "Scalar string assignment");
my $sum;
map{ $sum += $_ } @face;
is ($sum, 25, "Array assignment");
is( $dict{fruit}, 'melon', "Hash assignment");

exit 1;

use Carp;

sub assign_big {
	
	local $debug = 1;
	$debug2 and print "&assign_big\n";
	
	my %h = @_;
	my $class;
	croak "didn't expect scalar here" if ref $h{DATA} eq 'SCALAR';
	croak "didn't expect code here" if ref $h{DATA} eq 'CODE';

	if ( ref $h{DATA} !~ /^(HASH|ARRAY|CODE|GLOB|HANDLE|FORMAT)$/){
		# we guess object
		$class = ref $h{DATA}; 
		$debug and print "I found a class: $class, I think...\n";
	} 
	$class = $h{CLASS} if $h{CLASS};
	$class or carp 
		("assign: no class found, use explicit CLASS => 'main' if needed\n"),
		return;
	my @vars = @{ $h{VARS} };
	my $ref = $h{DATA};
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
		my $full_class = $sigil{$key}."$class\::".$key;
		$debug and print "full_class: $full_class\n";;
		$debug and print "full: $full\n";;
		my ($sigil, $identifier) = ($sigil{$key}, $key);
		$eval .= $full_class;
		$eval .= q( = );

		my $val;

		if ($sigil eq '$') { # scalar assignment

			# extract value

			if ($ref->{$identifier}) { #  if we have something,

 				# take it
				
				$val = $ref->{$identifier};

				# dereference it if needed
				
				ref $val eq q(SCALAR) and $val = $$val; 
														
				# quoting for non-numerical
				
				$val = qq("$val") 
					unless  $val =~ /^[\d\.,+-e]+$/ 
					or 		ref $val;
		
			} else { $val = q(undef) }; # or set as undefined

			$eval .=  $val;  # append to assignment

		} else { # array, hash assignment

			$eval .= qq($sigil\{);
			$eval .= q($ref->{ );
			$eval .= qq("$identifier");
			$eval .= q( } );
			$eval .= q( } );
		}
		$debug and print $eval, $/, $/;
		eval($eval) or carp "failed to eval $eval: $!\n";
	} @keys;
	1;
}

sub assign{
	local $debug = 0;
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
		$debug and print "full: $full\n";;
		my ($sigil, $identifier) = ($sigil{$key}, $key);
		$eval .= $full;
		$eval .= q( = );

		my $val;

		if ($sigil eq '$') { # scalar assignment

			# extract value

			if ($ref->{$identifier}) { #  if we have something,

 				# take it
				
				$val = $ref->{$identifier};

				# dereference it if needed
				
				ref $val eq q(SCALAR) and $val = $$val; 
														
				# quoting for non-numerical
				
				$val = qq("$val") 
					unless  $val =~ /^[\d\.,+-e]+$/ 
					or 		ref $val;
		
			} else { $val = q(undef) }; # or set as undefined

			$eval .=  $val;  # append to assignment

		} else { # array, hash assignment

			$eval .= qq($sigil\{);
			$eval .= q($ref->{ );
			$eval .= qq("$identifier");
			$eval .= q( } );
			$eval .= q( } );
		}
		$debug and print $eval, $/, $/;
		eval($eval) or carp "failed to eval $eval: $!\n";
	} @keys;
	1;
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

	$source eq 'State' and -f $source 
		and $debug and print ("found Storable file: $source\n")
		and $ref = retrieve($source) # Storable

	## check for a filename

	or -f $source and $source =~ /.yaml$/ 
		and $debug and print "found a yaml file: $source\n"
		and $ref = yaml_in($source)
 	
	## check for a string

	or  $source =~ /^\s*---/s 
		and $debug and print "found yaml as text\n"
		and $ref = $yr->read($source)

	## pass a hash_ref to the assigner

	or ref $source 
		and $debug and print "found a reference\n"
		and $ref = $source;


	assign($ref, @vars);
	1;	

}

sub store_vars {
	local $debug = 1;
	# now we will only store in yaml
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
	$debug and print "attempting to eval $eval_string\n";
	eval($eval_string) or print "failed to eval $eval_string: $!\n";
	} @vars;
	# my $result1 = store \%state, $file; # old method
	my $yamlout = yaml_out(\%state);
	$yamlout > io $file;

}
sub serial {
	local $debug = 0;
	# now we will only store in yaml
	$debug2 and print "&serial\n";
	my @vars = @_;
	my %state;
	map{ my ($sigil, $identifier) = /(.)(\w+)/; 
		 my $eval_string =  q($state{)
							. $identifier
							. q(})
							. q( = )
							. ($sigil ne q($) ? q(\\) : q() ) 
							. $_;
	$debug and print "attempting to eval $eval_string\n";
	eval($eval_string) or print "failed to eval $eval_string: $!\n";
	} @vars;
	# my $result1 = store \%state, $file; # old method
	yaml_out(\%state);


}
=comment

## buggy new versions of assign (assign_sigil) and store_vars (serialize)
sub serialize { # list of vars, output as string 
	local $debug = 1;
	# now we will only store in YAML
	$debug2 and print "&store_vars\n";
	my @vars = @_;
	$debug and print "vars: @vars\n";
	my %state;
	map{ my ($sigil, $identifier) = /(.)(\w+)/; 
		 my $eval_string =  q($state{)
							. q(')
							. $_
							. q(')
							. q(} = )
							. ($sigil ne q($) ? q(\\) : q() ) 
							# backslash if not scalar
							# double backslash needed for eval
							. $_;
	$debug and print "attempting to eval $eval_string\n";
	eval($eval_string) or print "failed to eval $eval_string: $@\n";
	} @vars;
	# my $result1 = store \%state, $file; # OLD METHOD
	my $yamlout = yaml_out(\%state);
	$yamlout;

}

sub assign_sigil { ### seems to work, goes with buggy &serializer above
	local $debug = 1;
	$debug2 and print "&assign_sigil\n";
	my ($ref, @vars) = @_;
	my @keys =  keys %{ $ref };
	$debug and print join " ","found keys: ", keys %{ $ref },"\n---\n";
	map{  
		my $eval;
		my $var_name  = $_;
		my ($sigil) = $var_name =~ /^([\%\@\$])/;
		my $full = $var_name;
		print "full: $full\n";;
		$eval .= $full;
		$eval .= q( = );
		

		my $val;

		if ($sigil eq '$') { # scalar assignment

			# extract value

			if ($ref->{$_}) { #  if we have something,

 				# take it
				
				$val = $ref->{$_};

				# dereference it if needed
				
				ref $val eq q(SCALAR) and $val = $$val; 
														
				# quoting for non-numerical
				
				$val = qq("$val") 
					unless  $val =~ /^[\d\.,+-e]+$/ 
					or 		ref $val;
		
			} else { $val = q(undef) }; # or set as undefined

			$eval .=  $val;  # append to assignment

		} else { # array, hash assignment

			$eval .= qq($sigil\{);
			$eval .= q($ref->{ );
			$eval .= qq(q($full));
			$eval .= q( } );
			$eval .= q( } );
		}
		$debug and print $eval, $/, $/;
		#eval($eval) or carp "failed to eval $eval: $!\n";
	}
	 @keys
}

=cut
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
