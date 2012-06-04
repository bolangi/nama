# ------ Effect Routines -------

package ::Effects; # share namespace with Nama.pm and several others
use Modern::Perl;
use List::MoreUtils qw(insert_after_string);
use ::Assign qw(yaml_out json_out);
no warnings 'uninitialized';
use Carp;
use ::Log qw(logsub logpkg);
use ::Globals qw(
					$fx 
					$fx_cache 
					$ui 
					%ti 
					%tn 
					%bn 
					$config 
					$setup 
					$this_op 
					$this_track);

sub import_engine_subs {

	*valid_engine_setup = \&::valid_engine_setup;
	*engine_running		= \&::engine_running;
	*eval_iam			= \&::eval_iam;
	*ecasound_select_chain = \&::ecasound_select_chain;
	*sleeper			= \&::sleeper;
	*command_process    = \&::command_process;
}

use Exporter qw(import);
our %EXPORT_TAGS = ( 'all' => [ qw(

					parent
					chain
					type
					bypassed
					owns
					fx
					params
					is_controller
					
					fxindex
					effect_index
					ecasound_effect_index
					full_effect_code
					name

					catch_null_id
					effect_entry_is_bad
					check_fx_consistency

					cop_add
					add_effect
					remove_effect
					modify_effect
					modify_multiple_effects

					effect_update
					effect_update_copp_set
					sync_effect_parameters
					find_op_offsets
					apply_ops
					expanded_ops_list
				
					is_read_only
					bypass_effects
					preallocate_cop_id

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();

sub parent : lvalue { 
	my $id = shift; 
	catch_null_id($id);
	$fx->{applied}->{$id}->{belongs_to} 
}
sub chain  : lvalue { 
	my $id = shift; 
	catch_null_id($id);
	$fx->{applied}->{$id}->{chain}      
}
sub type   : lvalue { 
	my $id = shift; 
	catch_null_id($id);
	$fx->{applied}->{$id}->{type}       
}
sub bypassed : lvalue{ 
	my $id = shift; 
	catch_null_id($id);
	$fx->{applied}->{$id}->{bypassed}   
}

# ensure owns field is initialized as anonymous array 
# bah!!

sub owns   : lvalue { 
	my $id = shift; 
	catch_null_id($id);
	$fx->{applied}->{$id}->{owns}
} 
sub fx     : lvalue { 
	my $id = shift; 
	catch_null_id($id);
	$fx->{applied}->{$id}                
}
sub params : lvalue { 
	my $id = shift; 
	catch_null_id($id);
	$fx->{params}->{$id}
}

# get information from registry
sub fxindex {
	my $id = shift;
	catch_null_id($id);
	$fx_cache->{full_label_to_index}->{ type($id) };
}
sub name {
	my $id = shift;
	catch_null_id($id);
	$fx_cache->{registry}->[fxindex($id)]->{name}
}
 
sub catch_null_id {
	return 0;
	my $id = shift;
	confess "null effect id"   unless $id;
	confess "$id: effect id does not exist"  
		unless $fx->{applied}->{$id} and $fx-{params}->{$id}
}
sub effect_entry_is_bad {
		my $id = shift;
		! $id  									# undef key ''
		or ! $fx->{params}->{$id}				# missing params entry 
		or ! ref $fx->{applied}->{$id} 			# applied entry is not ref 
		or keys %{$fx->{applied}->{$id}} < 3	# not enough key/val pairs
}

# access routines
# the lvalue routines can be on the left side of an assignment

sub is_controller 	{ my $id = shift; parent($id) }
sub has_read_only_param {
	my $op_id = shift;
	my $entry = $fx_cache->{registry}->[fxindex($op_id)];
	logpkg('logcluck',"undefined or unregistered effect id: $op_id"), 
		return unless $op_id and $entry;
		for(0..scalar @{$entry->{params}} - 1)
		{
			return 1 if $entry->{params}->[$_]->{dir} eq 'output' 
		}
}
sub is_read_only {
    my ($op_id, $param) = @_;
    my $entry = $fx_cache->{registry}->[fxindex($op_id)];
	logpkg('logcluck',"undefined or unregistered effect id: $op_id"), 
		return unless $op_id and $entry;
	$entry->{params}->[$param]->{dir} eq 'output'
}          

# make sure the chain number (track index) is set

sub set_chain_value {
		
	my $p = shift;

	return if $p->{chain}; # return if already set
	
	# set chain from track if known
	
	if( $p->{track} )
	{ 
		$p->{chain} = $p->{track}->n;
	  	delete $p->{track}
	}

	# set chain from parent effect if known (add controller)
	
	elsif( $p->{parent_id})
	{ 
		$p->{chain} = chain($p->{parent_id})
	}
	# set chain from insert target if known (insert effect)
	
	elsif( $p->{before} )
	{
		$p->{chain} = chain($p->{before});
	}
	#logpkg('debug',(yaml_out($p));

}


sub add_effect {
	my $p = shift;
	logsub("&add_effect");
	#logpkg('debug',sub{ "add effect arguments - 0:\n".yaml_out($p)});
	
	set_chain_value($p);

	logpkg('debug',sub{ "add effect arguments - 1:\n".yaml_out($p)});

	# either insert or add, depending on 'before' setting
	
	my $id = $p->{before} ?  _insert_effect($p) : _add_effect($p);
	
	# return effect ID
	$id
}


sub _add_effect { 
	my $p = shift;
	my (    $n,   $before, $code,$parent_id,$id, $values) =
	@$p{qw( chain before    type parent_id  cop_id values)};
	! $p->{chain} and
		carp("effect id: $code is missing track number, skipping\n"), return ;

	$id = cop_add($p); 
	
	$ui->add_effect_gui($p) unless $ti{$n}->hide;
	if( valid_engine_setup() )
	{
		if (engine_running())
		{ 
			$ti{$n}->mute;
			::stop_do_start( sub{ apply_op($id) }, 0.05);
			$ti{$n}->unmute;
		}
		else { apply_op($id) }
	}
	$id;

}
sub _insert_effect {  # call only from add_effect
	my $p = shift;
	local $config->{category} = 'ECI_FX';
	my ($before, $code, $values) = @$p{qw(before type values)};
	say("$code: unknown effect. Skipping.\n"), return if !  full_effect_code($code);
	$code = full_effect_code( $code );	
	my $running = engine_running();
	print("Cannot insert effect while engine is recording.\n"), return 
		if $running and ::ChainSetup::really_recording();
	print("Cannot insert effect before controller.\n"), return 
		if is_controller($before);

	if ($running){
		$ui->stop_heartbeat;
		::mute();
		::stop_command();
		sleeper( 0.05); 
	}
	my $n = chain($before) or 
		print(qq[Insertion point "$before" does not exist.  Skipping.\n]), 
		return;
	
	my $track = $ti{$n};
	#logpkg('debug', $track->name, $/;
	#logpkg('debug', "@{$track->ops}")

	# find offset 
	
	my $offset = 0;
	for my $id ( @{$track->ops} ){
		last if $id eq $before;
		$offset++;
	}

	# remove ops after insertion point if engine is connected

	my @ops = @{$track->ops}[$offset..$#{$track->ops}];
	logpkg('debug',"ops to remove and re-apply: @ops");
	my $connected = eval_iam('cs-connected');
	if ( $connected ){  
		map{ remove_op($_)} reverse @ops; # reverse order for correct index
	}

	_add_effect($p);

	logpkg('debug',"@{$track->ops}");

	# the new op_id is added to the end of the $track->ops list
	# so we need to move it to specified insertion point

	my $op = pop @{$track->ops}; 

	# the above acts directly on $track, because ->ops returns 
	# a reference to the array

	# insert the effect id 
	splice 	@{$track->ops}, $offset, 0, $op;

	logpkg('debug',sub{"@{$track->ops}"});

	# replace the ops that had been removed
	if ($connected ){  
		map{ apply_op($_, $n) } @ops;
	}
		
	if ($running){
		eval_iam('start');	
		sleeper(0.3);
		::unmute();
		$ui->start_heartbeat;
	}
	$op
}
sub modify_effect {
	my ($op_id, $parameter, $sign, $value) = @_;
		# $parameter: zero based
	my $cop = fx($op_id)
		or print("$op_id: non-existing effect id. Skipping.\n"), return; 
	my $code = type($op_id);
	my $i = effect_index($code);
	defined $i or croak "undefined effect code for $op_id: ",yaml_out($cop);
	my $parameter_count = scalar @{ $fx_cache->{registry}->[$i]->{params} };

	print("$op_id: effect does not exist, skipping\n"), return 
		unless fx($op_id);
	print("$op_id: parameter (", $parameter + 1, ") out of range, skipping.\n"), return 
		unless ($parameter >= 0 and $parameter < $parameter_count);
	print("$op_id: parameter $parameter is read-only, skipping\n"), return 
		if is_read_only($op_id, $parameter);
		my $new_value = $value; # unless $sign
		if ($sign) {
			$new_value = 
 			eval (join " ",
 				$fx->{params}->{$op_id}->[$parameter], 
 				$sign,
 				$value);
		};
	$this_op = $op_id;
	logpkg('debug', "id $op_id p: $parameter, sign: $sign value: $value");
	effect_update_copp_set( 
		$op_id, 
		$parameter, 
		$new_value);
	1
}
sub modify_multiple_effects {
	my ($op_ids, $parameters, $sign, $value) = @_;
	map{ my $op_id = $_;
		map{ 	my $parameter = $_;
				$parameter--; # convert to zero-base
				modify_effect($op_id, $parameter, $sign, $value);
		} @$parameters;
		$this_op = $op_id; # set current effect
	} @$op_ids;
}

sub remove_effect { 
	logsub("&remove_effect");
	my $id = shift;
	if( ! $id or ! fx($id) ){
		logpkg('logcarp',"$id: does not exist, skipping...\n");
		return;
	}
	my $n 		= chain($id);
	$n or die ::json_out(fx($id));
	my $parent 	= parent($id);
	my $owns	= owns($id);
	logpkg('debug', "id: $id, parent: $parent");

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

		my $parent_owns = owns($parent);
		logpkg('debug',"parent $parent owns: ". join ",", @$parent_owns);

		@$parent_owns = (grep {$_ ne $id} @$parent_owns);
		logpkg('debug',"parent $parent new owns list: ". join ",", @$parent_owns);

	}
	$ti{$n}->remove_effect_from_track( $id ) if $ti{$n};
	# remove entries for chain operator attributes and parameters
 	delete $fx->{applied}->{$id}; # remove entry from chain operator list
    delete $fx->{params }->{$id}; # remove entry from chain operator parameters likk
	$this_op = undef;
}

sub position_effect {
	my($op, $pos) = @_;

	# we cannot handle controllers
	
	print("$op or $pos: controller not allowed, skipping.\n"), return 
		if grep{ is_controller($_) } $op, $pos;
	
	# first, modify track data structure
	
	print("$op: effect does not exist, skipping.\n"), return unless fx($op);
	my $track = $ti{chain($op)};
	my $op_index = nama_effect_index($op);
	my @new_op_list = @{$track->ops};
	# remove op
	splice @new_op_list, $op_index, 1;
	my $new_op_index;
	if ( $pos eq 'ZZZ'){
		# put it at the end
		push @new_op_list, $op;
	}
	else { 
		my $track2 = $ti{chain($pos)};
		print("$pos: position belongs to a different track, skipping.\n"), return
			unless $track eq $track2;
		$new_op_index = nama_effect_index($pos); 
		# insert op
		splice @new_op_list, $new_op_index, 0, $op;
	}
	# reconfigure the entire engine (inefficient, but easy to do)
	#say join " - ",@new_op_list;
	@{$track->ops} = @new_op_list;
	$setup->{changed}++;
	reconfigure_engine();
	$this_track = $track;
	command_process('show_track');
}

## array indices for Nama and Ecasound effects and controllers

sub nama_effect_index { # returns nama chain operator index
						# does not distinguish op/ctrl
	my $id = shift;
	my $n = chain($id);
	my $arr = $ti{$n}->ops;
	logpkg('debug', "id: $id n: $n");
	logpkg('debug', "@{$ti{$n}->ops}" );
		for my $pos ( 0.. scalar @{ $ti{$n}->ops } - 1  ) {
			return $pos if $arr->[$pos] eq $id; 
		};
}
sub ecasound_effect_index { 
	my $id = shift;
	my $n = chain($id);
	my $opcount;  # one-based
	logpkg('debug', "id: $id, n: $n, ops: @{ $ti{$n}->ops }" );
	for my $op (@{ $ti{$n}->ops }) { 
			# increment only for ops, not controllers
			next if is_controller($op);
			++$opcount;
			last if $op eq $id
	} 
	$fx->{offset}->{$n} + $opcount;
}

sub ctrl_index { 
	my $id = shift;
	nama_effect_index($id) - nama_effect_index(root_parent($id));

}

sub ecasound_operator_index { # does not include offset
	my $id = shift;
	$id or croak "missing effect id";
	my $chain = chain($id);
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $controller_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$controller_count++ if is_controller($ops[$i]);
	}
	$position -= $controller_count; # skip controllers 
	++$position; # translates 0th to chain-position 1
}
	
	
sub ecasound_controller_index {
	my $id = shift;
	my $chain = chain($id);
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $operator_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$operator_count++ if ! is_controller($ops[$i]);
	}
	$position -= $operator_count; # skip operators
	++$position; # translates 0th to chain-position 1
}
sub full_effect_code {
	# get text effect code from user input, which could be
	# - LADSPA Unique ID (number)
	# - LADSPA Label (el:something)
	# - abbreviated LADSPA label (something)
	# - Ecasound operator (something)
	# - abbreviated Ecasound preset (something)
	# - Ecasound preset (pn:something)
	
	# there is no interference in these labels at present,
	# so we offer the convenience of using them without
	# el: and pn: prefixes.
	
	my $input = shift;
	my $code;
    if ($input !~ /\D/) # i.e. $input is all digits
	{
		$code = $fx_cache->{ladspa_id_to_label}->{$input};
		defined $code or carp("$input: LADSPA plugin not found.  Aborting.\n"),
			return;
	}
	elsif ( $fx_cache->{full_label_to_index}->{$input} )
	{
		$code = $input 
	}
	else 
	{ 
		$code = $fx_cache->{partial_label_to_full}->{$input} 
	}
	defined $code or ($config->{opts}->{E} or
		warn("$input: effect code not found.  Skipping.\n")),
		return unless 	$code;
}


# get integer effect index for Nama effect registry
sub effect_index {
	my $code = shift;
	my $i = $fx_cache->{full_label_to_index}->{full_effect_code($code)};
	defined $i or $config->{opts}->{E} or warn("$code: effect index not found\n");
	$i
}

## Ecasound engine -- apply/remove chain operators

sub apply_ops {  # in addition to operators in .ecs file
	
	logsub("&apply_ops");
	for my $n ( map{ $_->n } ::Track::all() ) {
	logpkg('debug', "chain: $n, offset: $fx->{offset}->{$n}");
 		next unless ::ChainSetup::is_ecasound_chain($n);

	# controllers will follow ops, so safe to apply all in order
		for my $id ( @{ $ti{$n}->ops } ) {
		apply_op($id);
		}
	}
	ecasound_select_chain($this_track->n) if defined $this_track;
}

sub apply_op {
	logsub("&apply_op");
	local $config->{category} = 'ECI_FX';
	my ($id, $selected_chain) = @_;
	logpkg('debug', "id: $id");
	logpkg('logcluck', "$id: expected effect entry not found!"), return
		if effect_entry_is_bad($id);
	my $code = type($id);
	my $dad = parent($id);
	my $chain = chain($id);
	logpkg('debug', "chain: ".chain($id)." type: $code");
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ params($id) };
	logpkg('debug', "values: @vals");

	# we start to build iam command

	my $add_cmd = $dad ? "ctrl-add " : "cop-add "; 
	
	$add_cmd .= $code . join ",", @vals;

	# append the -kx  operator for a controller-controller
	$add_cmd .= " -kx" if $dad and is_controller($dad);

	logpkg('debug', "command: $add_cmd");

	eval_iam("c-select $chain") if $selected_chain != $chain;
	eval_iam("cop-select " . ecasound_effect_index($dad)) if $dad;
	eval_iam($add_cmd);

	my $ref = ref owns($id) ;
	$ref =~ /ARRAY/ or croak "expected array";
	my @owns = @{ owns($id) }; 
	logpkg('debug',"children found: ". join ",", @{owns($id)});

}
sub remove_op {
	# remove chain operator from Ecasound engine

	logsub("&remove_op");
	local $config->{category} = 'ECI_FX';

	# only if engine is configured
	return unless valid_engine_setup();

	my $id = shift;
	my $n = chain($id);

	# select chain
	
	return unless ecasound_select_chain($n);

	# deal separately with controllers and chain operators
	
	my $index;

	if ( ! is_controller($id) ){ # chain operator
		logpkg('debug', "no parent, assuming chain operator");
	
		$index = ecasound_effect_index( $id );
		logpkg('debug', "ops list for chain $n: @{$ti{$n}->ops}");
		logpkg('debug', "operator id to remove: $id");
		logpkg('debug', "ready to remove from chain $n, operator id $id, index $index");
		logpkg('debug',sub{eval_iam("cs")});
		eval_iam("cop-select ". ecasound_effect_index($id) );
		logpkg('debug',sub{"selected operator: ". eval_iam("cop-selected")});
		eval_iam("cop-remove");
		logpkg('debug',sub{eval_iam("cs")});

	} else { # controller

		logpkg('debug', "has parent, assuming controller");

		my $ctrl_index = ctrl_index($id);
		logpkg('debug', eval_iam("cs"));
		eval_iam("cop-select ".  ecasound_effect_index(root_parent($id)));
		logpkg('debug', "selected operator: ". eval_iam("cop-selected"));
		eval_iam("ctrl-select $ctrl_index");
		eval_iam("ctrl-remove");
		logpkg('debug', eval_iam("cs"));
	}
}


# Track sax effects: A B C GG HH II D E F
# GG HH and II are controllers applied to chain operator C
# 
# to remove controller HH:
#
# for Ecasound, chain op index = 3, 
#               ctrl index     = 2
#                              = nama_effect_index HH - nama_effect_index C 
#               
#
# for Nama, chain op array index 2, 
#           ctrl arrray index = chain op array index + ctrl_index
#                             = effect index - 1 + ctrl_index 
#
#

sub root_parent { 
	my $id = shift;
	my $parent = parent($id);
	carp("$id: has no parent, skipping...\n"),return unless $parent;
	parent($parent) || $parent
}

## Nama effects are represented by entries in $fx->{applied}
## and by the ops array in each track, $track->ops

sub preallocate_cop_id { $fx->{id_counter}++ } # return value, then increment

sub cop_add {
	logsub("&cop_add");
	my $p = shift;
	logpkg('debug',sub{yaml_out($p)});

	my ($n,  $type, $id, $parent_id)  = 
	@$p{qw( 
	    chain type cop_id parent_id)};

	# return existing op_id if effect already exists
	# unless effect chain asks us to get a new id
	#
	logpkg('debug',"$id: returning existing id") if $id and fx($id);
	return $id if $id and fx($id);

	my 	$allocated = "recycled";
	if ( ! $id ){ 
		$id = $p->{cop_id} = $fx->{id_counter};
		$allocated = "issued";
	}

	logpkg('debug',"$id: cop id $allocated");

	my $i = effect_index($type);

	logpkg('debug',"Issuing a cop_id for track $n: $id");
	
	# make entry in $fx->{applied} with chain, code, display-type, children

	$fx->{applied}->{$id} = 
	{
		chain 	=> $n, 
		type 	=> $type,
		display => $fx_cache->{registry}->[$i]->{display}, # XX do we need this???
		owns 	=> [],
	}; 

	# set defaults for effects only (not controllers)
	
	if (! $parent_id and ! $p->{values}){
		my @vals;
		logpkg('debug', "no settings found, loading defaults if present");
		
		# if the effect is a controller (has a parent), we don't 
		# initialize the first parameter (the control target)
		
		for my $j (0..$fx_cache->{registry}->[$i]->{count} - 1) {
		
			push @vals, $fx_cache->{registry}->[$i]->{params}->[$j]->{default};
		}
		logpkg('debug', "copid: $id defaults: @vals");
		$p->{values} = \@vals;
	}
	
	params($id) = $p->{values};

	if ($parent_id) {
		logpkg('debug', "parent found: $parent_id");

		# store relationship

		push @{ owns($parent_id) }, $id;
		logpkg('debug',"parent owns @{owns($parent_id)}");

		logpkg('debug',sub{join " ", "my attributes:", yaml_out(fx($id))});
		parent($id) = $parent_id;
		logpkg('debug',sub{join " ", "my attributes again:", yaml_out(fx($id))});
		#logpkg('debug', "parameter: $parameter");

		# set fx-param to the parameter number, which one
		# above the zero-based array offset that $parameter represents
		
		#$fx->{params}->{$id}->[0] = $parameter + 1;  # XXX
			# only GUI sets $parameter XXXX
		
 		# find position of parent in the track ops array 
 		# and insert child immediately afterwards
 		#
 		# to keep controller order constant for RCS
 		# controllers must be reverse in order 
 		# they are stored on effect chain when applied
 		
		# what if controller has two controllers?
		# effect chain apply should reverse them, too

		insert_after_string($parent_id, $id, @{$ti{$n}->ops}), 

	}
	else { push @{$ti{$n}->ops }, $id; } 


	# make sure the counter $fx->{id_counter} will not occupy an
	# already used value
	while( fx( $fx->{id_counter} )){$fx->{id_counter}++};

	$id;
}

## synchronize Ecasound chain operator parameters 
#  with Nama effect parameter

sub effect_update {
	local $config->{category} = 'ECI_FX';

	# update the parameters of the Ecasound chain operator
	# referred to by a Nama operator_id
	
	#logsub("&effect_update");

	return unless valid_engine_setup();
	#my $es = eval_iam("engine-status");
	#logpkg('debug', "engine is $es");
	#return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	$param++; # so the value at $p[0] is applied to parameter 1
	carp("$id: effect not found. skipping...\n"), return unless fx($id);
	my $chain = chain($id);
	return unless ::ChainSetup::is_ecasound_chain($chain);

	logpkg('debug', "chain $chain id $id param $param value $val");

	# $param is zero-based. 
	# %{$fx->{params}} is  zero-based.

	my $old_chain = eval_iam('c-selected') if valid_engine_setup();
	ecasound_select_chain($chain);

	# update Ecasound's copy of the parameter
	if( is_controller($id)){
		my $i = ecasound_controller_index($id);
		logpkg('debug', "controller $id: track: $chain, index: $i param: $param, value: $val");
		eval_iam("ctrl-select $i");
		eval_iam("ctrlp-select $param");
		eval_iam("ctrlp-set $val");
	}
	else { # is operator
		my $i = ecasound_operator_index($id);
		logpkg('debug', "operator $id: track $chain, index: $i, offset: ".
		$fx->{offset}->{$chain}. " param $param, value $val");
		eval_iam("cop-select ". ($fx->{offset}->{$chain} + $i));
		eval_iam("copp-select $param");
		eval_iam("copp-set $val");
	}
	ecasound_select_chain($old_chain);
}

# set both Nama effect and Ecasound chain operator
# parameters

sub effect_update_copp_set {
	my ($id, $param, $val) = @_;
	effect_update( @_ );
	# params($id)->[$param] = $val; # equivalent but confusing
	$fx->{params}->{$id}->[$param] = $val;
}

sub sync_effect_parameters {
	local $config->{category} = 'ECI_FX';
	# when a controller changes an effect parameter
	# the effect state can differ from the state in
	# %{$fx->{params}}, Nama's effect parameter store
	#
	# this routine syncs them in prep for save_state()
	
 	return unless valid_engine_setup();
	my $old_chain = eval_iam('c-selected');
	map{ sync_one_effect($_) } ops_with_controller(), ops_with_read_only_params();
	eval_iam("c-select $old_chain");
}

sub sync_one_effect {
		my $id = shift;
		my $chain = chain($id);
		eval_iam("c-select $chain");
		eval_iam("cop-select " . ( $fx->{offset}->{$chain} + ecasound_operator_index($id)));
		params($id) = get_cop_params( scalar @{$fx->{params}->{$id}} );
}

	

sub get_cop_params {
	local $config->{category} = 'ECI_FX';
	my $count = shift;
	my @params;
	for (1..$count){
		eval_iam("copp-select $_");
		push @params, eval_iam("copp-get");
	}
	\@params
}
		
sub ops_with_controller {
	grep{ ! is_controller($_) }
	grep{ scalar @{owns($_)} }
	map{ @{ $_->ops } } 
	::ChainSetup::engine_tracks();
}
sub ops_with_read_only_params {
	grep{ has_read_only_param($_) }
	map{ @{ $_->ops } } 
	::ChainSetup::engine_tracks();
}


sub find_op_offsets {

	local $config->{category} = 'ECI_FX';
	logsub("&find_op_offsets");
	my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
	logpkg('debug', join "\n\n",@op_offsets);
	for my $output (@op_offsets){
		my $chain_id;
		($chain_id) = $output =~ m/Chain "(\w*\d+)"/;
		# print "chain_id: $chain_id\n";
		next if $chain_id =~ m/\D/; # skip id's containing non-digits
									# i.e. M1
		my $quotes = $output =~ tr/"//;
		logpkg('debug', "offset: $quotes in $output");
		$fx->{offset}->{$chain_id} = $quotes/2 - 1;  
	}
}

sub expanded_ops_list { # including controllers
						# we assume existing ops
	my @ops_list = @_;
	return () unless @_;
	my @expanded = ();
	map 
	{ push @expanded, 
		$_, 
		expanded_ops_list( reverse @{owns($_)} );

		# we reverse controllers listing so 
		# the first controller is applied last
		# the insert operation places it adjacent to 
		# its parent controller
		# as a result, the controllers end up
		# in the same order as the original
		#
		# which is convenient for RCS
		
 	} @ops_list;

	my %seen;
	@expanded = grep { ! $seen{$_}++ } @expanded;
}

sub intersect_with_track_ops_list {
	my ($track, @effects)  = @_;
	my %ops;
	map{ $ops{$_}++} @{$track->ops};
	my @intersection = grep { $ops{$_} } @effects;
	my @outersection = grep { !$ops{$_} } @effects;
	carp "@outersection: effects don't belong to track: ", $track->name, 
			". skipping." if @outersection;
	@intersection
}


	

sub ops_data {
	my @ops_list = expanded_ops_list(@_);
	my $ops_data = {};

	# keep parameters with other fx data
	map { 	
		$ops_data->{$_}            = fx($_);
		$ops_data->{$_}->{params}  = params($_);
	} @ops_list;
	
	# we don't need chain (track) number or display type
	
	map { 
		delete $ops_data->{$_}{chain};
		delete $ops_data->{$_}{display};
	} @ops_list;
	$ops_data;
}



sub bypass_effects {
	my($track, @ops) = @_;
	_bypass_effects($track, 'on', @ops);
}
sub restore_effects {
	my($track, @ops) = @_;
	_bypass_effects($track, 'off', @ops);
}

sub _bypass_effects {
	
	local $config->{category} = 'ECI_FX';
	my($track, $off_or_on, @ops) = @_;

	# only process ops that belong to this track
	@ops = intersect_with_track_ops_list($track,@ops);

	$track->mute;
	eval_iam("c-select ".$track->n);

	foreach my $op ( @ops)
	{ 
		my $i = ecasound_effect_index($op);
		eval_iam("cop-select $i");
		eval_iam("cop-bypass $off_or_on");
		bypassed($op) = ($off_or_on eq 'on') ? 1 : 0;
	}
	$track->unmute;
}
sub check_fx_consistency {

	my $result = {};
	my %seen_ids;
	my $is_error;
	map
	{     
		my $track = $_;
		my $name = $track->name;
		my @ops = @{ $track->{ops} };
		my $is_track_error;

		# check for missing special-purpose ops

		my $no_vol_op 		= ! $track->vol;
		my $no_pan_op 		= ! $track->pan;
		my $no_latency_op 	= ! $track->latency_op;

		# check for orphan special-purpose op entries

		$is_track_error++, $result->{track}->{$name}->{orphan_vol} = $track->vol 
			if $track->vol and !  grep { $track->vol eq $_ } @ops;
		$is_track_error++,$result->{track}->{$name}->{orphan_pan} = $track->pan 
			if $track->pan and !  grep { $track->pan eq $_ } @ops;

		# we don't check for orphan latency ops as this is
		# allowed in order to keep constant $op_id over
		# time (slower incrementing of fx counter)
		
		#$is_track_error++,$result->{track}->{$name}->{orphan_latency_op} = $track->latency_op 
		#	if $track->latency_op and !  grep { $track->latency_op eq $_ } @ops;

		# check for undefined op ids 
		
		my @track_undef_op_pos;

		my $i = 0;
		map { defined $_ or push @track_undef_op_pos, $i; $i++ } @ops;
		$is_track_error++,$result->{track}->{$name}->{undef_op_pos}
			= \@track_undef_op_pos if @track_undef_op_pos;

		# remove undefined op ids from list
		
		@ops = grep{ $_ } @ops;

		# check for op ids without corresponding entry in $fx->{applied}

		my @uninstantiated_op_ids;
		map { fx($_) or push @uninstantiated_op_ids, $_ } @ops;

		$is_track_error++, $result->{track}->{$name}->{uninstantiated_op_ids} 
			= \@uninstantiated_op_ids if @uninstantiated_op_ids;

		$result->{track}->{$name}->{is_error}++ if $is_track_error;
		$result->{is_error}++ if $is_track_error;
	} ::Track::all();

	# check entries in $fx->{applied}
	
	# check for null op_id
	

	$result->{applied}->{is_undef_entry}++ if $fx->{applied}->{undef};

	# check for incomplete entries in $fx->{applied}
	
	my @incomplete_entries = 
		grep { ! params($_) or ! type($_) or ! chain($_) } 
		grep { $_ } keys %{$fx->{applied}};

	if(@incomplete_entries)
	{
		$result->{applied}->{incomplete_entries} = \@incomplete_entries;
		$result->{is_error}++
	}
	$result;
}
1;
__END__
