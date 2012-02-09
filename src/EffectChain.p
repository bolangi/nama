# ------------- Effect-Chain and -Profile routines --------

package ::EffectChain;
use Modern::Perl;
use Carp;
use Exporter qw(import);

use ::Globals qw($fx $this_op $debug);

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

## sugar for accessing individual effect attributes

sub is_controller {
	my ($self, $id) = @_;
	$self->{ops_data}->{$_}->{belongs_to}
}
sub parent : lvalue {
	my ($self, $id) = @_;
	$self->{ops_data}->{$_}->{belongs_to}
}
sub type {
	my ($self, $id) = @_;
	$self->{ops_data}->{$_}->{type}
}
sub params {
	my ($self, $id) = @_;
	$self->{ops_data}->{$_}->{params}
}

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
		$ops_data->{$_}           = { %{ ::fx($_)    } };  # copy
		$ops_data->{$_}->{params} = [ @{ ::params($_)} ];  # copy;
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
	$debug and say $object->dump;
	$object;
}

sub add {
	my $self = shift;
	my $track = shift;
	local $this_op; # don't change current op
	say $track->name, qq(: adding effect chain ). $self->name 
		unless $self->system;

	#@$p{qw( chain type parent_id cop_id parameter values)};

	
	# make a copy of object that we can alter
	# 
	# we need to alter the op_ids that show
	# relationship between effects and controllers
	#
	# we do this using Data::Rmap to recursively
	# change the values
	
	# this is for the case that the project has
	# already used he op_ids we've recorded.
	#
	# for example:
	#
	# $self->{ops_data}->{EF}->{belongs_to}->{AB}
	#
	# but op_id AB is taken, AC is allocated
	# so we need to convert s/AB/AC/
	#
	# (an alternative implementation would be to 
	# store the relationships in a graph)
	
	$self = bless { %$self }, __PACKAGE__;

	
	my $before = $track->vol;
	map 
	{	my $new_id = ::add_effect({
			before		=> $before, # for effect, not controller
			chain  		=> $track->n,
			type   		=> $self->type($_),
			values 		=> $self->params($_),
			parent_id 	=> $self->parent($_),
			cop_id 		=> $_,
			rename_id	=> 1,
		});
		my $orig_id = $_;
		if ( $new_id ne $orig_id)
		# change all controllers to belong to new id
		{
			map{ $self->parent($_) =~ s/^$orig_id$/$new_id/  } @{$self->ops_list}
		}
		
	} @{$self->ops_list};
}
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
	return $unique ? pop @found : @found; 
}
	
	
1;
__END__
