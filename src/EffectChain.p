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
use ::Log qw(logit);

use ::Globals qw($fx_cache %tn $this_op);

our @effect_chain_data;

our $VERSION = 0.001;
no warnings qw(uninitialized);
our @ISA;
our ($n, %by_index);
use ::Object qw( 
[% qx(./strip_comments ./effect_chain_fields) %]
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
	# arguments: ops_list, ops_data, inserts_data
	# ops_list => [id1, id2, id3,...];
	my $class = shift;	
	defined $n or die "key var $n is undefined";
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "must have exactly one of 'global' or 'project' fields defined" 
		unless ($vals{global} xor $vals{project});
	# we expect some effects

	croak "expected either non-empty ops_list or insert_data" 
		unless $vals{ops_list} and scalar @{$vals{ops_list}} 
		    or $vals{inserts_data} and scalar @{$vals{inserts_data}};

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

	$vals{ops_data} = $ops_data;

	if( $vals{inserts_data})
	{

		# rewrite inserts to store what we need:
		# 1. for general-purpose effects chain use
		# 2. for track caching use
	
		
		$vals{inserts_data} = 
		[ 
			map
			{ 
				my @wet_ops = @{$tn{$_->wet_name}->ops};
				my @dry_ops = @{$tn{$_->dry_name}->ops};
				my $wet_effect_chain = ::EffectChain->new(
					project => 1,
					track_cache => 1, # if we include an insert
										# does it mean track_cache?
										# probably not
										
				#	track_name => 'brass-1-wet', # don't need this, do we?
					insert	=> 1,
					ops_list => \@wet_ops,
				);
				my $dry_effect_chain = ::EffectChain->new(
					project => 1,
					track_cache => 1,
				#	track_name => 'brass-1-dry',# don't need this, do we?
					insert => 1,
					ops_list => \@dry_ops,
				);
				my $hash = dclone($_->as_hash);

				$hash->{wet_effect_chain} = $wet_effect_chain->n;
				$hash->{dry_effect_chain} = $dry_effect_chain->n;

				map{ delete $hash->{$_} } qw(n dry_vol wet_vol track);	

				# Reasons for deleting insert attributes
				
				# n: we'll get a new index when we re-apply
				# dry_vol, wet_vol: will never be re-allocated
				#    so why not reuse them?
				#    except for general purpose we'd like to
				#    re-allocate
				# track: we already know the track from
				#    the parent effect chain

				# What is left:
				# 
				# 	class
				#	wetness
				#	send_type
				#	send_id
				#	return_type
				#	return_id
				#	wet_effect_chain => ec_index,
				#   dry_effect_chain => ec_index,
				
				$hash
			} @{$vals{inserts_data}}
		];
	}

	say ::yaml_out($vals{inserts_data}) if $vals{inserts_data};

	my $object = bless 
		{ 
			n => $n, 
			%vals,

		}, $class;
	$by_index{$n} = $object;
	logit(__LINE__,'::EffectChain','debug',sub{$object->dump});
	$object;
}

### apply effect chain to the specified track
### or the track specified by the effect chain's track_name field.

sub add_ops {
	my($self, $track, $successor) = @_;

}
sub add_inserts {
	my($self, $track, $successor) = @_;
}
sub add_all {
	my($self, $track, $successor) = @_;
}
sub clobber_ops {
	my($self, $track) = @_;
}
sub clobber_inserts {
	my($self, $track) = @_;
}
sub clobber_all {
	my($self, $track) = @_;
}

sub add {
	my ($self, $track, $successor) = @_;
	
	$track ||= $tn{$self->track_name} if $tn{$self->track_name};
	
	local $this_op; # don't change current op
	say $track->name, qq(: adding effect chain ). $self->name 
		unless $self->system;

	$self = bless { %$self }, __PACKAGE__;
	$successor ||= $track->vol; # place effects before volume 
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
		logit(__LINE__,'::EffectChain','debug',"new id: $new_id");
		my $orig_id = $_;
		if ( $new_id ne $orig_id)
		# change all controllers to belong to new id
		{
			map{ $self->parent($_) =~ s/^$orig_id$/$new_id/  } @{$self->ops_list}
		}
		
		
	} @{$self->ops_list};

	map 
	{
		say "found insert data:\n",::yaml_out($_);

		# get effect chain indices for wet/dry arms
		
		my $wet_effect_chain = delete $_->{wet_effect_chain};
		my $dry_effect_chain = delete $_->{dry_effect_chain};
		my $class 			 = delete $_->{class};

		$_->{track} = $track->name;
		my $insert = $class->new(%$_);

	} @{$self->inserts_data};

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
	logsub("&new_effect_profile");
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
	logsub("&delete_effect_profile");
	my $name = shift;
	say qq(deleting effect profile: $name);
	map{ $_->destroy} ::EffectChain::find( profile => $name );
}

sub apply_effect_profile {  # overwriting current effects
	logsub("&apply_effect_profile");
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
