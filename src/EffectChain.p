# ------------- Effect-Chain and -Profile routines --------
# Effect Chains
#
# we have two type of effect chains
# + global effect chains - usually user defined, available to all projects
# + system generated effect chains, per project


package ::EffectChain;
use Modern::Perl;
use Data::Dumper::Concise;
use Carp;
use Exporter qw(import);
use Storable qw(dclone);
use ::Log qw(logpkg logsub);
use ::Assign qw(json_out);
use ::Effects qw(fx);

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

## sugar for accessing individual effect attributes
## similar sugar is used for effects. 

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
	$vals{inserts_data} ||= [];
	$vals{ops_list} 	||= [];
	$vals{ops_data} 	||= {};
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "must have exactly one of 'global' or 'project' fields defined" 
		unless ($vals{global} xor $vals{project});
	# we expect some effects

	logpkg('debug','constructor arguments ', sub{ json_out(\%vals) });

	logpkg('debug',"Nether ops_list or nor insert_data is present") 
 		if ! scalar @{$vals{ops_list}} and ! scalar @{$vals{inserts_data}};

	my $n = $vals{n} || ++$n;

	my $ops_data = {};
	# ops data can either be 
	# + provided explicitly with ops_data argument, e.g.convert_effect_chains() 
	# + or taken from existing effects, e.g. $fx->{applied}
	#
	# in either case, we want to clone the data structures
	# to ensure we don't damage objects in the original
	# structure.
	
	map { 	

		if ( $vals{ops_data}->{$_} )
										
		{ 	
			$ops_data->{$_} 		  = dclone($vals{ops_data}->{$_});
		}
		else
		{
			$ops_data->{$_} 		  = dclone( ::fx(    $_) );  # copy
			$ops_data->{$_}->{params} = dclone( ::params($_) );  # copy;
			# our op IDs are ALL CAPS, so will not conflict
			# with params when accessing via key
			#
			# however this would be wrong:
			#
			# map{ show_effect($_) }   keys %{$ops_data}
			#
			# because keys includes 'params'

			
			# we don't need these attributes
			# chain will likely change
			# when applied
			delete $ops_data->{$_}->{chain};
			delete $ops_data->{$_}->{display};

			# the 'display' attribute was only used control 
			# the GUI layout.
		}

	} @{$vals{ops_list}};

	$vals{ops_data} = $ops_data;

	if( scalar @{$vals{inserts_data}})
	{

		# rewrite inserts to store what we need:
		# 1. for general-purpose effects chain use
		# 2. for track caching use
	
		
		$vals{inserts_data} = 
		[ 
			map
			{ 
				logpkg('debug',"insert: ", sub{Dumper $_});
				my @wet_ops = @{$tn{$_->wet_name}->ops};
				my @dry_ops = @{$tn{$_->dry_name}->ops};
				my $wet_effect_chain = ::EffectChain->new(
					project => 1,
					insert	=> 1,
					ops_list => \@wet_ops,
				);
				my $dry_effect_chain = ::EffectChain->new(
					project => 1,
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

	#say ::yaml_out($vals{inserts_data}) if $vals{inserts_data};

	my $object = bless 
		{ 
			n => $n, 
			%vals,

		}, $class;
	$by_index{$n} = $object;
	logpkg('debug',sub{$object->dump});
	$object;
}

### apply effect chain to the specified track


sub add_ops {
	my($self, $track, $successor) = @_;
	
	# Higher priority: track argument 
	# Lower priority:  effect chain's own track name attribute
	$track ||= $tn{$self->track_name} if $tn{$self->track_name};
	
	local $this_op; # restore to present value on exiting subroutine
					# i.e. avoid save/restore using $old_this_op 

	logpkg('debug',$track->name,
			qq(: adding effect chain ), $self->name, Dumper $self
		 
		);

	$successor ||= $track->vol; # place effects before volume 
	map 
	{	
		my $args = 
		{
			chain  		=> $track->n,
			type   		=> $self->type($_),
			values 		=> $self->params($_),
			parent_id 	=> $self->parent($_),
		};

		$args->{cop_id} = $_ unless fx($_);

		logpkg('debug',"args ", json_out($args));
		# avoid incorrectly calling _insert_effect 
		# (and controllers are not positioned relative to other  effects)
		# 
		
		$args->{before} = $successor unless $args->{parent_id};


		my $new_id = ::add_effect($args);
		
		# the effect ID may be new, or it may be previously 
		# assigned ID, 
		# whatever value is supplied is guaranteed
		# to be unique; not to collide with any other effect
		
		logpkg('debug',"new id: $new_id");
		my $orig_id = $_;
		if ( $new_id ne $orig_id)
		# re-write all controllers to belong to new id
		{
			map{ $self->parent($_) =~ s/^$orig_id$/$new_id/  } @{$self->ops_list}
		}
		
		
	} @{$self->ops_list};


}
sub add_inserts {
	my ($self, $track) = @_;
	map 
	{
		my $insert_data = dclone($_); # copy so safe to modify 
		#say "found insert data:\n",::yaml_out($insert_data);

		# get effect chain indices for wet/dry arms
		
		my $wet_effect_chain = delete $insert_data->{wet_effect_chain};
		my $dry_effect_chain = delete $insert_data->{dry_effect_chain};
		my $class 			 = delete $insert_data->{class};

		$insert_data->{track} = $track->name;
		my $insert = $class->new(%$insert_data);
		#$::by_index{$wet_effect_chain}->add($insert->wet_name, $tn{$insert->wet_name}->vol)
		#$::by_index{$dry_effect_chain}->add($insert->dry_name, $tn{$insert->dry_name}->vol)
	} @{$self->inserts_data};
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
	$self->add_ops($track, $successor);
	$self->add_inserts($track);

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
	push @output, "  name: ".$self->name if $self->name;
	push @output, "  track name: ".$self->track_name if $self->track_name;
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
	::pager( qq(effect profile "$profile" created for tracks: @tracks) );
	map { 
		::EffectChain->new(
			profile 	=> $profile,
			user		=> 1,
			global		=> 1,
			track_name	=> $_,
			ops_list	=> [ $tn{$_}->fancy_ops ],
			inserts_data => $tn{$_}->inserts,
		);
	} @tracks;
}
sub delete_effect_profile { 
	logsub("&delete_effect_profile");
	my $name = shift;
	::pager( qq(deleting effect profile: $name) );
	map{ $_->destroy} ::EffectChain::find( profile => $name );
}

sub apply_effect_profile {  # overwriting current effects
	logsub("&apply_effect_profile");
	my ($profile) = @_;
	my @chains = ::EffectChain::find(profile => $profile);

	map{ ::pager( "adding track $_" ); add_track($_) } 
	grep{ !$tn{$_} } 
	map{ $_->track_name } 
	@chains;	
	map{ $_->add } @chains;
}
1;
__END__
