# ------------- Effect-Chain and -Profile routines --------
# Effect Chains
#
# we have two type of effect chains
# + global effect chains - usually user defined, available to all projects
# + system generated effect chains, per project


package ::EffectChain;
use Modern::Perl;
use Carp;
use Exporter qw(import);
use Storable qw(dclone);

use ::Globals qw($fx_cache %tn $this_op $debug);

our @effect_chain_data;

our $VERSION = 0.001;
no warnings qw(uninitialized);
our @ISA;
our ($n, %by_index);
use ::Object qw( 
[% qx(cat ./effect_chain_fields) %]
		);
initialize();

# for compatibility with standard effects
sub cop_id { $_[0]->{id} }  

# all bypass types are set to clobber_id
sub clobber_id { my $self = shift; $self->bypass} 

## sugar for accessing individual effect attributes

sub is_controller {
	my ($self, $id) = @_;
	$self->{ops_data}->{$id}->{belongs_to}
}
sub parent : lvalue {
	my ($self, $id) = @_;
	$self->{ops_data}->{$id}->{belongs_to}
}
sub type {
	my ($self, $id) = @_;
	$self->{ops_data}->{$id}->{type}
}
sub params {
	my ($self, $id) = @_;
	$self->{ops_data}->{$id}->{params}
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
	# ops data can either be 
	# + provided explicitly with ops_data argument, e.g.convert_effect_chains() 
	# + or taken from existing effects, e.g. $fx->{applied}
	map { 	

		if ( $vals{ops_data} )
		{ 	
			$ops_data->{$_} = $vals{ops_data}->{$_} 
		}
		else
		{
			$ops_data->{$_} 		  = dclone( ::fx(    $_) );  # copy
			$ops_data->{$_}->{params} = dclone( ::params($_) );  # copy;
			delete $ops_data->{$_}->{chain};
			delete $ops_data->{$_}->{display};
		}
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
	my ($self, $track, $successor) = @_;
	
	# Apply effect chain to track argument, if supplied;
	# otherwise use the track specified by effect chain's track_name field.
	
	$track ||= $tn{$self->track_name} if $tn{$self->track_name};
	
	local $this_op; # don't change current op
	say $track->name, qq(: adding effect chain ). $self->name 
		unless $self->system;

	$self = bless { %$self }, __PACKAGE__;
	$successor ||= $track->vol; # place before volume 
	map 
	{	
		my $args = 
		{
			chain  		=> $track->n,
			type   		=> $self->type($_),
			values 		=> $self->params($_),
			parent_id 	=> $self->parent($_),
			cop_id 		=> $_,
			clobber_id	=> $self->clobber_id,
		};

		# avoid incorrectly calling _insert_effect 
		# (and controllers are not positioned relative to other  effects)
		# 
		
		$args->{before} = $successor unless $args->{parent_id};

		my $new_id = ::add_effect($args);
		$debug and say "new id: $new_id";
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
}

	
sub find { 
	my %args = @_;
	my $unique = delete $args{unique};

	# first check for a specified index that matches
	# an existing chain
	
	return $by_index{$args{n}} if $args{n};

	# otherwise all specified fields must match
	
	my @found = grep
		{ 	my $fx_chain = $_;
			
			# check if any specified fields *don't* match
			
			my @non_matches = grep 
			{ 
				# not: arg matches field exactly

				! ($fx_chain->$_ eq $args{$_}) 

				and	

				# not:
				# + arg is 1 (true) 
				# + field is present
				# + field is other than version (which must match exactly)

				! ($_ ne 'version' and $args{$_} eq 1 and $fx_chain->$_)

			} keys %args;

			# if no non-matches, then all have matched, 
			# and we return true

			! scalar @non_matches
		
       } values %by_index;

	warn("unique chain requested by multiple chains found. Skipping.\n"),
		return if $unique and @found > 1;
	return $unique ? pop @found : sort{ $a->n cmp $b->n } @found; 
}

sub summary {
	my $self = shift;
	my @output;
	push @output, "index: ". $self->n;
	push @output, "name: ".$self->name if $self->name;
	push @output, "track name: ".$self->track_name if $self->track_name;
	push @output,	
	map{ 
		my $i = ::effect_index( $self->{ops_data}->{$_}->{type} ); 
		my $name = "    ". $fx_cache->{registry}->[$i]->{name};
	} @{$_->ops_list};
	map{ $_,"\n"} @output;
}
	
####  Effect profile routines

package ::;
sub new_effect_profile {
	$debug2 and say "&new_effect_profile";
	my ($bunch, $profile) = @_;
	my @tracks = bunch_tracks($bunch);
	say qq(effect profile "$profile" created for tracks: @tracks);
	map { 
		::EffectChain->new(
			profile 	=> $profile,
			user		=> 1,
			global		=> 1,
			track_name	=> $_,
			ops_list	=> [ $tn{$_}->fancy_ops ],
		);
	} @tracks;
}
sub delete_effect_profile { 
	$debug2 and say "&delete_effect_profile";
	my $name = shift;
	say qq(deleting effect profile: $name);
	map{ $_->destroy} ::EffectChain::find( profile => $name );
}

sub apply_effect_profile {  # overwriting current effects
	$debug2 and say "&apply_effect_profile";
	my ($profile) = @_;
	my @chains = ::EffectChain::find(profile => $profile);

	map{ say "adding track $_"; add_track($_) } 
	grep{ !$tn{$_} } 
	map{ $_->track_name } 
	@chains;	
	map{ $_->add } @chains;
}
1;
__END__
