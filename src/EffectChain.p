# ------------- Effect-Chain and -Profile routines --------

package ::EffectChain;
use Modern::Perl;
use Carp;
use Exporter qw(import);

use ::Globals qw($fx $this_op);

our $VERSION = 0.001;
no warnings qw(uninitialized);
our @ISA;
our ($n, %by_index);
use ::Object qw( 
		n	
		ops_list
        ops_data
		
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

initialize();

sub initialize {
	$n = 1;
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
	croak "must have exactly one of 'global' or 'project' fields defined" 
		unless ($vals{global} xor $vals{project});
	# we expect some effects
	croak "expected non-empty ops_list" unless scalar @{$vals{ops_list}};
	my $n = $vals{n} || ++$n;
	my $ops_data = {};
	map { 	
		$ops_data->{$_}           = $fx->{applied}->{$_};
		$ops_data->{$_}->{params} = $fx->{params}->{$_};
		delete $ops_data->{$_}->{chain};
		delete $ops_data->{$_}->{display};

	} @{$vals{ops_list}};

	my $object = bless 
		{ 
			n => $n, 
			ops_data => $ops_data, 
			@_	

		}, $class;
	$by_index{$n} = $object;
	$object->dumpp;
	$object;
}
=comment
sub add {
	my $self = shift;
	my $track = shift;
	local $this_op; # don't change current op
	say $track->name, qq(: adding effect chain ). $self->name 
		unless $self->system;

	#@$p{qw( chain type parent_id cop_id parameter values)};
	my $before = $track->vol;
	map {  

		my $p = {};
	
		$p->{

		# controller case
		if (my $parent = $self->ops_data->{$_}->{belongs_to})
		{
		
			l(
				$parent,
				$self->ops_data->{$_}->{type}, 
				$self->ops_data->{$_}->{params},
			);


			);
				
				
				
		}
		else 
		{
			if ($before)
			{
				::Text::t_insert_effect(
					$before, 
					$self->ops_data->{$_}->{type}, 
					$self->ops_data->{$_}->{params}
				);
			}
			else 
			{ 
					::Text::t_add_effect(
					$track, 
					$self->ops_data->{$_}->{type}, 
					$self->ops_data->{$_}->{params}
				);
			}
		}
		undef $fx->{magical_cop_id};
	} @{$self->ops_list};
}
}	
=cut
sub destroy {
	my $self = shift;
	delete $by_index{$self->n};
	save_effect_chains();
}
	
sub find { 
	my %args = @_;
	my $unique = delete $args{unique};
	# first check if index is known
	return $by_index{$args{n}} if $args{n};

	# otherwise all specified fields must match
	my @found = grep
		{ 	my $fx_chain = $_;
			
			# find non matches
			my @non_matches = grep { $fx_chain->$_ ne $args{$_} } keys %args;

			# boolean opposite: return true if zero non matches
			! scalar @non_matches
		
       } values %by_index;

	warn("unique chain requested by multiple chains found. Skipping.\n"),
		return if $unique and @found > 1;
	return @found
}
	
	
1;
__END__
