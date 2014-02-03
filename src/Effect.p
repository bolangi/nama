{ 
package ::Effect;
use Modern::Perl;
use ::Globals qw($this_track $ui $fx $fx_cache %tn %ti);
use ::Effects qw(effect_init fxn effect_update_copp_set remove_op);
use ::Log qw(logsub logpkg);
use Carp qw(confess);
our @keys = qw( 	
[% qx( cat ./effect_fields ) %]
);


our $AUTOLOAD;
*this_op			= \&::this_op;
*this_param			= \&::this_param;
*this_stepsize		= \&::this_stepsize;

my %is_field = map{ $_ => 1} qw(id owns bypassed parent type chain params);

sub new { 
	my ($class, $p) = @_;
	my $id = ::effect_init($p); 
	::fxn($id)
}

sub id 			{ my $self = shift; $self->{id} }
sub owns 		{ my $self = shift; $fx->{applied}->{$self->{id}}->{owns}		}
sub bypassed 	{ my $self = shift; 
				  $fx->{applied}->{$self->{id}}->{bypassed} ? 'bypassed' : undef}
sub parent 		{ my $self = shift; 
					my $parent_id = $fx->{applied}->{$self->{id}}->{parent};
					::fxn($parent_id)}
sub type 		{ my $self = shift; $fx->{applied}->{$self->{id}}->{type} 		}
sub chain 		{ my $self = shift; $fx->{applied}->{$self->{id}}->{chain} 		}
sub display 	{ my $self = shift; $fx->{applied}->{$self->{id}}->{display} 	}
sub fx	 		{ my $self = shift; $fx->{applied}->{$self->{id}}		 		}
sub params		{ my $self = shift; $fx->{params }->{$self->{id}}               }
sub is_read_only {
    my ($self, $param) = @_;
	no warnings 'uninitialized';
	$self->about->{params}->[$param]->{dir} eq 'output'
}          
sub name        { my $self = shift; $fx->{applied}->{$self->{id}}->{name}     	}
sub remove_name { my $self = shift; delete $fx->{applied}->{$self->{id}}->{name}}
sub surname		{ my $self = shift; $fx->{applied}->{$self->{id}}->{surname}    }
sub set_name    { my $self = shift; $fx->{applied}->{$self->{id}}->{name} = shift}
sub set_surname { my $self = shift; $fx->{applied}->{$self->{id}}->{surname} = shift}
sub set_names    { 
	my $self = shift; 
}
sub is_controller { my $self = shift; $self->parent } 

sub has_read_only_param {
	my $self = shift;
	no warnings 'uninitialized';
	my $entry = $self->about;
		for(0..scalar @{$entry->{params}} - 1)
		{
			return 1 if $entry->{params}->[$_]->{dir} eq 'output' 
		}
}

sub registry_index {
	my $self = shift;
	$fx_cache->{full_label_to_index}->{ $self->type };
}
sub ecasound_controller_index {
	my $self = shift;
	my $id = $self->id;
	my $chain = $self->chain;
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $operator_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$operator_count++ if ! ::fxn($ops[$i])->is_controller;
	}
	$position -= $operator_count; # skip operators
	++$position; # translates 0th to chain-position 1
}
sub ecasound_operator_index { # does not include offset
	my $self = shift;
	my $id = $self->id;
	my $chain = $self->chain;
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $controller_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$controller_count++ if ::fxn($ops[$i])->is_controller;
	}
	$position -= $controller_count; # skip controllers 
	++$position; # translates 0th to chain-position 1
}
sub ecasound_effect_index { 
	my $self = shift;
	my $n = $self->chain;
	my $id = $self->id;
	my $opcount = 0;
	logpkg('debug', "id: $id, n: $n, ops: @{ $ti{$n}->ops }" );
	for my $op (@{ $ti{$n}->ops }) { 
			# increment only for ops, not controllers
			next if $self->is_controller;
			++$opcount;   # first index is 1
			last if $op eq $id
	} 
	no warnings 'uninitialized';
	$self->offset + $opcount;
}
sub track_effect_index { # the position of the ID in the track's op array
	my $self = shift;
	my $id = $self->id;
	my $n = $self->chain;
	my $arr = $ti{$n}->ops;
	logpkg('debug', "id: $id n: $n");
	logpkg('debug', "@{$ti{$n}->ops}" );
		for my $pos ( 0.. scalar @{ $ti{$n}->ops } - 1  ) {
			return $pos if $arr->[$pos] eq $id; 
		};
}
# TODO
sub set	{ 
	my $self = shift; my %args = @_;
	while(my ($key, $value) = each %args){ 
		#say "effect id $self->{id}: setting $key = $value";
		$is_field{$key} or die "illegal key: $key for effect id $self->{id}";
		if ($key eq 'params'){ $fx->{params}->{$self->{id}} = $value } 
		else { $fx->{applied}->{$self->{id}}->{$key} = $value }
	}
}
sub sync_one_effect {
		my $self= shift;
		my $chain = $self->chain;
		::eval_iam("c-select $chain");
		::eval_iam("cop-select " .( $self->offset + $self->ecasound_operator_index ) );
		$self->set(params => get_ecasound_cop_params( scalar @{$self->params} ));
}
sub offset {
	my $self = shift;
	$fx->{offset}->{$self->chain}
}
sub root_parent { 
	my $self = shift;
	return $self if ! $self->parent;
	$self->parent->root_parent
}
sub about {
	my $self = shift;
	$fx_cache->{registry}->[$self->registry_index]
}
sub track { $ti{$_[0]->chain} }
sub trackname { $_[0]->track->name }

sub AUTOLOAD {
	my $self = shift;
	say "got self: $self", ::Dumper $self;
	# get tail of method call
	my ($call) = $AUTOLOAD =~ /([^:]+)$/;
	# see if this can be satisfied by a field from
	# the corresponding effects registry entry
	$call = 'name' if $call eq 'fxname';
	$self->about->{$call}
}
sub DESTROY {}
sub as_hash {
	my $self = shift;
	my $hash = {};
	for (@keys){ $hash->{$_} = $self->$_ }
	$hash
}
sub ladspa_id {
	my $self = shift;
	$::fx_cache->{ladspa_label_to_unique_id}->{$self->type} 
}
sub nameline {
	my $self = shift;
	my @attr_keys = qw( name surname fxname type ladspa_id bypassed trackname);
	my $nameline = $self->id. ": ". join q(, ), grep{$_} map{$self->$_} @attr_keys;
	$nameline .= "\n";
	$nameline
}
sub effect_index { 
	my $self = shift;
	::effect_index($self->type)
}
sub modify_effect {
	my ($self, $parameter, $sign, $value) = @_;
	my $op_id = $self->id;

	$parameter--; # convert to zero-based
	my $code = $self->type;
	my $i = $self->effect_index;
	defined $i or confess "undefined effect code for $op_id: ",::Dumper $self;
	my $parameter_count = scalar @{ $self->about->{params} };
	::pager("$op_id: parameter (", $parameter + 1, ") out of range, skipping.\n"), return 
		unless ($parameter >= 0 and $parameter < $parameter_count);
	::pager("$op_id: parameter $parameter is read-only, skipping\n"), return 
		if $self->is_read_only($parameter);
		my $new_value = $value; # unless $sign
		if ($sign) {
			$new_value = 
 			eval (join " ",
 				$self->params->[$parameter], 
 				$sign,
 				$value);
		};
	logpkg('debug', "id $op_id p: $parameter, sign: $sign value: $value");
	effect_update_copp_set( 
		$op_id, 
		$parameter,
		$new_value);
	1
}
sub remove_effect { 
	logsub("&remove_effect");
	my $self = shift;
	my $id = $self->id;
	my $n 		= $self->chain;
	my $parent 	= $self->parent;
	my $owns	= $self->owns;
	logpkg('debug', "id: $id", ($parent ? ". parent: ".$parent->id : '' ));

	my $object = $parent ? q(controller) : q(chain operator); 
	logpkg('debug', qq(ready to remove $object "$id" from track "$n"));

	$ui->remove_effect_gui($id);

	# recursively remove children
	logpkg('debug',"children found: ". join ",",@$owns) if defined $owns;
	map{ remove_effect($_) } @$owns if defined $owns;
;
	# remove chain operator
	
	if ( ! $parent ) { remove_op($id) } 

	# remove controller
	
	else { 
 			
 		remove_op($id);

		# remove parent ownership of deleted controller

		my $parent_owns = $parent->owns;
		logpkg('debug',"parent $parent owns: ". join ",", @$parent_owns);

		@$parent_owns = (grep {$_ ne $id} @$parent_owns);
		logpkg('debug',"parent $parent new owns list: ". join ",", @$parent_owns);

	}
	# remove effect ID from track
	if( my $track = $ti{$n} ){
		my @ops_list = @{$track->ops};
		say "ops_list: @ops_list";
		my $perl_version = $^V;
		my ($minor_version) = $perl_version =~ /^v5\.(\d+)/;
		my @new_list = grep  { $_ ne $id  } @ops_list;
		say "new_list: @new_list";
		if ($minor_version <= 14) 
		     {    $track->{ops}   = [ @new_list  ] }
		else { @{ $track->{ops} } =   @new_list    }
	}
	# remove entries for chain operator attributes and parameters
 	delete $fx->{applied}->{$id}; # remove entry from chain operator list
    delete $fx->{params }->{$id}; # remove entry from chain operator parameters likk
	set_current_op($this_track->ops->[0]);
	set_current_param(1);
}
sub position_effect {
	my($self, $pos) = @_;

	my $op = $self->id;
	# we cannot handle controllers
	
	::pager("$op or $pos: controller not allowed, skipping.\n"), return 
		if grep{ fxn($_)->is_controller } $op, $pos;
	
	# first, modify track data structure
	
	my $POS = fxn($pos);
	my $track = $ti{$self->chain};

	my $op_index = $self->track_effect_index;
	my @new_op_list = @{$track->ops};
	# remove op
	splice @new_op_list, $op_index, 1;
	my $new_op_index;
	if ( $pos eq 'ZZZ'){
		# put it at the end
		push @new_op_list, $op;
	}
	else { 
		my $track2 = $ti{$POS->chain};
		::pager("$pos: position belongs to a different track, skipping.\n"), return
			unless $track eq $track2;
		$new_op_index = $POS->track_effect_index; 
		# insert op
		splice @new_op_list, $new_op_index, 0, $op;
	}
	# reconfigure the entire engine (inefficient, but easy to do)
	#say join " - ",@new_op_list;
	@{$track->ops} = @new_op_list;
	::request_setup();
	$this_track = $track;
	process_command('show_track');
}
} # end package
{ 
package ::FX;
use Modern::Perl;
our @ISA = '::Effect';
our %by_id;
sub new {
	my ($class, %args) = @_;
	my $self = bless \%args, $class;
	$by_id{ $self->id } = $self;
	$self
}
use ::Object qw(  
[% qx( cat ./effect_fields ) %]
				);
} # end package
1
