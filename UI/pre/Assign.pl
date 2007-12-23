=comment
## testing never passed
my $struct = { 
	foo => 2, 
	name => 'John', 
	face => [1,5,7,12],
	dict => {fruit => 'melon'}
};	

my @var_list = qw( $foo @face $name %dict);
assign($struct, @var_list);

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
use Carp;
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


