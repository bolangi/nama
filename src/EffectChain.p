# ------------- Effect-Chain and -Profile routines --------

package ::EffectChain;
use Modern::Perl;
use Carp;
use Exporter qw(import);
our @EXPORT = qw(get_effect_chain);

use ::Globals qw(:all);

our $VERSION = 0.001;
no warnings qw(uninitialized);
our @ISA;
our ($n, %by_index);
use ::Object qw( 
		n	
		op_list
        op_data
		
		name
		id
		project
		global
		profile
		user
		system
		track_name
		track_version
		track_cache
		bypass
		);
sub initialize {
	$n = 0;
	%by_index = ();	
	@::global_effect_chains_data = ();  # for save/restore
    @::project_effect_chains_data = (); 
}
sub new {
	# ops_list => [id1, id2, id3,...];
	my $class = shift;	
	defined $n or die "key var $n is undefined";
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	# we expect some effects
	return unless $vals{ops_list};
	my $n = $vals{n} || ++$n;
	my $ops_data = {};
	map { 	
		$ops_data->{type}->{$_}   = $fx->{applied}->{$_}{type};
		$ops_data->{params}->{$_} = $fx->{params}->{$_};
	} @{$vals{ops_list}};

	my $object = bless { n => $n, ops_data => $ops_data, @_	}, $class;
	$by_index{$n} = $object;
	$object;

}

sub global_effect_chains { get_effect_chain(global => 1) }
sub project_effect_chains { get_effect_chain(global => 0) }

sub get_effect_chain { 
	my %args = @_;
	my $single_match = delete $args{single_match};
	# first check if index is known
	return $by_index{$args{n}} if $args{n};

	# otherwise all specified fields must match
	my @indices = grep
		{ 	my $fx_chain = $by_index{$_};
			
			# find non matches
			my @non_matches = grep { $fx_chain->$_ ne $args{$_} } keys %args;

			# boolean opposite: return true if zero non matches
			! scalar @non_matches
		
       } keys %by_index;

	return @indices unless $single_match and @indices > 1
}
	
	
1;
__END__
=comment
    n # unique id
	op_list  => [id1, id2, id3,...    ],
	op_data  => { id1 => { 
					type => type1, 
					params => [   ],
					owns   => ida,
					belongs_to => idb,
					},
				  id2 => {
					},
				},

	# searchable fields
	name  # for user defined fx chains
	id    # for bypass
	project # identifies project specific fx chain
	global  # identifies global fx chain (generally user defined)
	profile # belongs to specified profile, or *some* profile
	user    # user defined
	system  # system generated
	track_name #  applies to specified track name
	track_version # applies to specified track version
	track_cache # used for track caching
	bypass # used for bypass 
=cut
=comment

TODO: 

* initialize(): need to ensure effect chains are loaded
before calling new()

* save/restore $::EffectChain::n

* index n must be an incrementing Nama persistent global, otherwise
a user-defined chain could be assigned an index that is used
by project-specific chain in another project.

* convert_effect_chains()


DONE

* attributes should be true fields

		
global_effect_chains
project_effect_chains

my $n = get_effect_chain(%attribute_targets);
add_effect_chain($n);

=cut

sub private_effect_chain_name {
	my $name = "_$project->{name}/".$this_track->name.'_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
	@{ $this_track->effect_chain_stack }, 
		grep{/$name/} keys %{$fx->{chain}};
	$name . ++$i
}
# old bypass 
sub fx_bypass_name {
	my $id = shift;
	return "_$project->{name}/_bypass_$id";
}

sub profile_effect_chain_name {
	my ($profile, $track_name) = @_;
	"_$profile\:$track_name";
}
sub push_effect_chain {
	$debug2 and say "&push_effect_chain";
	my ($track, %vals) = @_; 

	# use supplied ops list, or default to user-applied (fancy) ops
	
	my @ops = $vals{ops} ? @{$vals{ops}} : $track->fancy_ops;
	say("no effects to store"), return unless @ops;

	# use supplied name, or default to private name that will now show 
	# in listing
	
	my $save_name   = $vals{save} || private_effect_chain_name();
	$debug and say "save name: $save_name"; 

	# create a new effect-chain definition
	
	new_effect_chain( $track, $save_name, @ops ); # current track effects

	# store effect-chain name on track effect-chain stack
	
	push @{ $track->effect_chain_stack }, $save_name;

	# operate on stored effects (remove or bypass)
	
	map { $vals{operation}->($_) } @ops;

	$save_name;
}

sub pop_effect_chain { # restore previous
	$debug2 and say "&pop_effect_chain";
	my $track = shift;
	my $previous = pop @{$track->effect_chain_stack};
	say("no previous effect chain"), return unless $previous;
	map{ remove_effect($_)} $track->fancy_ops;
	add_effect_chain($track, $previous);
	delete $fx->{chain}->{$previous};
}
sub overwrite_effect_chain {
	$debug2 and say "&overwrite_effect_chain";
	my ($track, $name) = @_;
	print("$name: unknown effect chain.\n"), return if !  $fx->{chain}->{$name};
	push_effect_chain($track, operation => \&remove_effect) if $track->fancy_ops;
	add_effect_chain($track,$name); 
}
sub bypass_effect { 
	my $id = shift; # assume legal fx name
	my $track = $ti{$fx->{applied}->{id}->{chain}};
	
	# do nothing if already bypassed
	
	say("$id: effect is already bypassed, skipping."), return 
		if $fx->{applied}->{id}->{bypass};
	
	# record that i am bypassed
	$fx->{applied}->{$id}->{bypass}++;

	# use the special "bypass" effect chain
	
	new_effect_chain(
			$track,
			ops => [ $id ], 
			save => fx_bypass_name($id),
	);

	my $before = $track->{ops}->[  nama_effect_index($id) - 1 ];
	remove_effect($id);
	::Text::t_insert_effect($before, "ea", [100]);
}

sub restore_effect {
	my $id = shift; # assume legal fx name
	
	# do nothing if already bypassed
	
	say("$id: effect is already bypassed, skipping."), return 
		if $fx->{applied}->{id}->{bypass};

	my $vals = $fx->{chain}->{fx_bypass_name($id)}->{params}->{$id};
	my $type = $fx->{chain}->{fx_bypass_name($id)}->{type}->{$id};

	my $track = $ti{$fx->{applied}->{$id}->{chain}};
	my $before = $track->{ops}->[  nama_effect_index($id) - 1 ];
	remove_effect($id);
	::Text::t_insert_effect($before, $type, $vals);

	# erase that i am bypassed
	undef $fx->{applied}->{$id}->{bypass};

	# erase my effect chain
	delete $fx->{chain}->{fx_bypass_name($id)};
}
sub restore_effects { pop_effect_chain($_[0])}

sub new_effect_chain {
	my ($track, $name, @ops) = @_;
#	say "name: $name, ops: @ops";
	@ops or @ops = $track->fancy_ops;
	say $track->name, qq(: creating effect chain "$name") unless $name =~ /^_/;
	$fx->{chain}->{$name} = { 
					ops 	=> \@ops,
					type 	=> { map{$_ => $fx->{applied}->{$_}{type} 	} @ops},
					params	=> { map{$_ => $fx->{params}->{$_} 		} @ops},
	};
	save_effect_chains();
}

sub add_effect_chain {
	my ($track, $name) = @_;
	#say "track: $track name: ",$track->name, " effect chain: $name";

	my $is_project_effect_chain = $name =~ /^_/;
	my $effect_chain = $fx->{global_effect_chains}{$name}
 						|| $fx->{project_effect_chains}{$name};

	$effect_chain or do 
		{ say("$name: effect chain does not exist") 
			unless $is_project_effect_chain;
		  return;
		};

	say $track->name, qq(: adding effect chain "$name") 
		unless $is_project_effect_chain;

	my $before = $track->vol;
	map {  $fx->{magical_cop_id} = $_ unless $fx->{applied}->{$_}; # try to reuse cop_id
		if ($before){
			::Text::t_insert_effect(
				$before, 
				$effect_chain->{type}{$_}, 
				$effect_chain->{params}{$_});
		} else { 
			::Text::t_add_effect(
				$track, 
				$effect_chain->{type}{$_}, 
				$effect_chain->{params}{$_});
		}
		$fx->{magical_cop_id} = undef;
	} @{$effect_chain->{ops}};
}	
sub list_effect_chains {
	my @frags = @_; # fragments to match against effect_chain names
    # we don't list chain_ids starting with underscore
    # except when searching for particular chains
    my @ids = grep{ @frags or ! /^_/ } keys %{$fx->{chain}};
	if (@frags){
		@ids = grep{ my $id = $_; grep{ $id =~ /$_/} @frags} @ids; 
	}
	my @results;
	map{ my $name = $_;
		push @results, join ' ', "$name:", 
		map{$fx->{chain}->{$name}{type}{$_},
			@{$fx->{chain}->{$name}{params}{$_}}
		} @{$fx->{chain}->{$name}{ops}};
		push @results, "\n";
	} @ids;
	@results;
}
1;

__END__

1;
__END__
