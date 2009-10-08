package ::;
use Test::More qw(no_plan);
use strict;
use warnings;
no warnings qw(uninitialized);
use Cwd;

BEGIN { use_ok('::') };

diag ("TESTING $0\n");

[% qx(cat ./declarations.pl) %] 
 
[% qx(cat ./var_types.pl) %]


# defeat namarc detection to force using $default namarc

push @ARGV, qw(-f dummy);

# set text mode (don't start gui)

push @ARGV, qw(-t); 

# use cwd as project root

push @ARGV, qw(-d .); 

diag(cwd);

prepare();
diag "Check representative variable from default .namarc";
is ( $::mix_to_disk_format, "s16_le,2,44100,i", "Read mix_to_disk_format");

diag "Check static effects data read";
is ( $::e_bound{cop}{z} > 40, 1, "Verify Ecasound chain operator count");

diag "Check effect hinting and help";

my $want = q(---
code: epp
count: 1
display: scale
name: Pan
params:
  -
    begin: 0
    default: 50
    end: 100
    name: "Level %"
    resolution: 0
...
);


is( yaml_out($::effects[$::effect_i{epp}]) ,  $want , "Pan hinting");

is( $effects_help[0], 
	qq(dyn_compress_brutal,  -pn:dyn_compress_brutal:gain-%\n),
	'Preset help for dyn_compress_brutal');

is( ref $main_bus, q(Audio::Nama::Bus), 'Bus initializtion');


my $cs_got = eval_iam('cs');
my $cs_want = q(### Chain status (chainsetup 'command-line-setup') ###
Chain "default" [selected] );
is( $cs_got, $cs_want, "Evaluate Ecasound 'cs' command");
1;
__END__
	is( $foo, 2, "Scalar number assignment");
	is( $name, 'John', "Scalar string assignment");
	my $sum;
	map{ $sum += $_ } @face;
	is ($sum, 25, "Array assignment");
	is( $dict{fruit}, 'melon', "Hash assignment");
	is ($serialized, $expected, "Serialization round trip");
}
	my $nulls = { 
		foo => 2, 
		name => undef,
		face => [],
		dict => {},
	};	
	diag("scalar array: ",scalar @face, " scalar hash: ", scalar %dict); 
	assign (data => $nulls, class => 'main', vars => \@var_list);
	is( scalar @face, 0, "Null array assignment");
	is( scalar %dict, 0, "Null hash assignment");
	

1;
__END__
