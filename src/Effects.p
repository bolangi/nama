# ------ Effect Routines -------

package ::;
use Modern::Perl;
use List::MoreUtils qw(insert_after_string);
no warnings 'uninitialized';
use Carp;
our $logger = get_logger("::Effects");

# access routines
# the lvalue routines can be on the left side of an assignment

sub is_controller 	{ my $id = shift; $fx->{applied}->{$id}->{belongs_to} }
sub has_read_only_param {
	my $id = shift;
	my $entry = $fx_cache->{registry}->[fxindex($id)];
		for(0..scalar @{$entry->{params}} - 1)
		{
			return 1 if $entry->{params}->[$_]->{dir} eq 'output' 
		}
}
sub is_read_only {
    my ($op_id, $param) = @_;
    my $entry = $fx_cache->{registry}->[fxindex($op_id)];
	$entry->{params}->[$param]->{dir} eq 'output'
}          

sub parent : lvalue { my $id = shift; $fx->{applied}->{$id}->{belongs_to} }
sub chain  : lvalue { my $id = shift; $fx->{applied}->{$id}->{chain}      }
sub type   : lvalue { my $id = shift; $fx->{applied}->{$id}->{type}       }
sub bypassed: lvalue{ my $id = shift; $fx->{applied}->{$id}->{bypassed}   }

# ensure owns field is initialized as anonymous array

sub owns   : lvalue { my $id = shift; $fx->{applied}->{$id}->{owns} ||= [] } 
sub fx     : lvalue { my $id = shift; $fx->{applied}->{$id}                }
sub params : lvalue { my $id = shift; $fx->{params}->{$id}                 }


# get information from registry
sub fxindex {
	my $op_id = shift;
	$fx_cache->{full_label_to_index}->{ type($op_id) };
}
sub name {
	my $op_id = shift;
	$fx_cache->{registry}->[fxindex($op_id)]->{name}
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
	#$logger->debug((yaml_out($p));

}


sub add_effect {
	my $p = shift;
	logit('SUB','debug', "&add_effect");
	#logit('FX','debug',sub{ "add effect arguments - 0:\n".yaml_out($p)});
	
	set_chain_value($p);

	logit('FX','debug',sub{ "add effect arguments - 1:\n".yaml_out($p)});

	# either insert or add, depending on 'before' setting
	
	my $id = $p->{before} ?  _insert_effect($p) : _add_effect($p);
	
	# return effect ID
	$id
}


sub _add_effect { 
	my $p = shift;
	my (    $n,   $before, $code,$parent_id,$id, $clobber_id, $values) =
	@$p{qw( chain before    type parent_id  cop_id clobber_id values)};
	! $p->{chain} and
		carp("effect id: $code is missing track number, skipping\n"), return ;

	$id = cop_add($p); 
	
	$ui->add_effect_gui($p) unless $ti{$n}->hide;
	if( valid_engine_setup() )
	{
		if (engine_running())
		{ 
			$ti{$n}->mute;
			stop_do_start( sub{ apply_op($id) }, 0.05);
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
		mute();
		eval_iam('stop-sync');
		sleeper( 0.05); 
	}
	my $n = chain($before) or 
		print(qq[Insertion point "$before" does not exist.  Skipping.\n]), 
		return;
	
	my $track = $ti{$n};
	#$logger->debug( $track->name, $/;
	#$logger->debug( "@{$track->ops}")

	# find offset 
	
	my $offset = 0;
	for my $id ( @{$track->ops} ){
		last if $id eq $before;
		$offset++;
	}

	# remove ops after insertion point if engine is connected

	my @ops = @{$track->ops}[$offset..$#{$track->ops}];
	$logger->debug("ops to remove and re-apply: @ops");
	my $connected = eval_iam('cs-connected');
	if ( $connected ){  
		map{ remove_op($_)} reverse @ops; # reverse order for correct index
	}

	_add_effect($p);

	$logger->debug("@{$track->ops}");

	# the new op_id is added to the end of the $track->ops list
	# so we need to move it to specified insertion point

	my $op = pop @{$track->ops}; 

	# the above acts directly on $track, because ->ops returns 
	# a reference to the array

	# insert the effect id 
	splice 	@{$track->ops}, $offset, 0, $op;

	$logger->debug(sub{"@{$track->ops}"});

	# replace the ops that had been removed
	if ($connected ){  
		map{ apply_op($_, $n) } @ops;
	}
		
	if ($running){
		eval_iam('start');	
		sleeper(0.3);
		unmute();
		$ui->start_heartbeat;
	}
	$op
}
sub modify_effect {
	my ($op_id, $parameter, $sign, $value) = @_;
		# $parameter: zero based
	my $cop = $fx->{applied}->{$op_id} 
		or print("$op_id: non-existing effect id. Skipping.\n"), return; 
	my $code = $cop->{type};
	my $i = effect_index($code);
	defined $i or croak "undefined effect code for $op_id: ",yaml_out($cop);
	my $parameter_count = scalar @{ $fx_cache->{registry}->[$i]->{params} };

	print("$op_id: effect does not exist, skipping\n"), return 
		unless fx($op_id);
	print("$op_id: parameter (", $parameter + 1, ") out of range, skipping.\n"), return 
		unless ($parameter >= 0 and $parameter < $parameter_count);
	print("$op_id: parameter $parameter is read-only, skipping\n"), return 
		if is_read_only($op_id, $parameter);
		my $new_value = $value; 
		if ($sign) {
			$new_value = 
 			eval (join " ",
 				$fx->{params}->{$op_id}->[$parameter], 
 				$sign,
 				$value);
		};
	$this_op = $op_id;
	$logger->debug( "id $op_id p: $parameter, sign: $sign value: $value");
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
	logit('SUB','debug', "&remove_effect");
	my $id = shift;
	if( ! fx($id) ){
		$logger->logcarp("$id: does not exist, skipping...\n");
		return;
	}
	my $n 		= chain($id);
	my $parent 	= parent($id);
	my $owns	= owns($id);
	$logger->debug( "id: $id, parent: $parent");

	my $object = $parent ? q(controller) : q(chain operator); 
	$logger->debug( qq(ready to remove $object "$id" from track "$n"));

	$ui->remove_effect_gui($id);

	# recursively remove children
	$logger->debug("children found: ". join ",",@$owns) if defined $owns;
	map{ remove_effect($_) } @$owns if defined $owns;
;

	# remove chain operator
	
	if ( ! $parent ) { remove_op($id) } 

	# remove controller
	
	else { 
 			
 		remove_op($id);

		# remove parent ownership of deleted controller

		my $parent_owns = owns($parent);
		$logger->debug("parent $parent owns: ". join ",", @$parent_owns);

		@$parent_owns = (grep {$_ ne $id} @$parent_owns);
		$logger->debug("parent $parent new owns list: ". join ",", @$parent_owns);

	}
	$ti{$n}->remove_effect_from_track( $id ); 
	delete $fx->{applied}->{$id}; # remove entry from chain operator list
	delete $fx->{params }->{$id}; # remove entry from chain operator parameters list
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
	$logger->debug( "id: $id n: $n");
	$logger->debug( "@{$ti{$n}->ops}" );
		for my $pos ( 0.. scalar @{ $ti{$n}->ops } - 1  ) {
			return $pos if $arr->[$pos] eq $id; 
		};
}
sub ecasound_effect_index { 
	my $id = shift;
	my $n = chain($id);
	my $opcount;  # one-based
	$logger->debug( "id: $id, n: $n, ops: @{ $ti{$n}->ops }" );
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
	defined $code or warn("$input: effect code not found.  Skipping.\n");
	$code;
}


# get integer effect index for Nama effect registry
sub effect_index {
	my $code = shift;
	my $i = $fx_cache->{full_label_to_index}->{full_effect_code($code)};
	defined $i or warn "$code: effect index not found\n";
	$i
}

## Ecasound engine -- apply/remove chain operators

sub apply_ops {  # in addition to operators in .ecs file
	
	logit('SUB','debug', "&apply_ops");
	for my $n ( map{ $_->n } ::Track::all() ) {
	$logger->debug( "chain: $n, offset: $fx->{offset}->{$n}");
 		next unless ::ChainSetup::is_ecasound_chain($n);

	# controllers will follow ops, so safe to apply all in order
		for my $id ( @{ $ti{$n}->ops } ) {
		apply_op($id);
		}
	}
	ecasound_select_chain($this_track->n) if defined $this_track;
}

sub apply_op {
	logit('SUB','debug', "&apply_op");
	local $config->{category} = 'ECI_FX';
	my $id = shift;
	! $id and carp "null id, skipping";
	return unless $id;
	my $selected = shift;
	$logger->debug( "id: $id");
	my $code = type($id);
	my $dad = parent($id);
	my $chain = chain($id);
	$logger->debug( "chain: ".chain($id)." type: $code");
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ params($id) };
	$logger->debug( "values: @vals");

	# we start to build iam command

	my $add_cmd = $dad ? "ctrl-add " : "cop-add "; 
	
	$add_cmd .= $code . join ",", @vals;

	# append the -kx  operator for a controller-controller
	$add_cmd .= " -kx" if is_controller($dad);

	$logger->debug( "command: $add_cmd");

	eval_iam("c-select $chain") if $selected != $chain;
	eval_iam("cop-select " . ecasound_effect_index($dad)) if $dad;
	eval_iam($add_cmd);

	my $ref = ref owns($id) ;
	$ref =~ /ARRAY/ or croak "expected array";
	my @owns = @{ owns($id) }; 
	$logger->debug("children found: ". join ",", @{owns($id)});

}
sub remove_op {
	# remove chain operator from Ecasound engine

	logit('SUB','debug', "&remove_op");
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
		$logger->debug( "no parent, assuming chain operator");
	
		$index = ecasound_effect_index( $id );
		$logger->debug( "ops list for chain $n: @{$ti{$n}->ops}");
		$logger->debug( "operator id to remove: $id");
		$logger->debug( "ready to remove from chain $n, operator id $id, index $index");
		$logger->debug(sub{eval_iam("cs")});
		eval_iam("cop-select ". ecasound_effect_index($id) );
		$logger->debug(sub{"selected operator: ". eval_iam("cop-selected")});
		eval_iam("cop-remove");
		$logger->debug(sub{eval_iam("cs")});

	} else { # controller

		$logger->debug( "has parent, assuming controller");

		my $ctrl_index = ctrl_index($id);
		$logger->debug( eval_iam("cs"));
		eval_iam("cop-select ".  ecasound_effect_index(root_parent($id)));
		$logger->debug( "selected operator: ". eval_iam("cop-selected"));
		eval_iam("ctrl-select $ctrl_index");
		eval_iam("ctrl-remove");
		$logger->debug( eval_iam("cs"));
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

sub cop_add {
	logit('SUB','debug', "&cop_add");
	my $p = shift;
	$logger->debug(sub{yaml_out($p)});

	my ($n,  $type, $id, $parent_id, $clobber_id)  = 
	@$p{qw( 
	    chain type cop_id parent_id   clobber_id)};

	# return existing op_id if effect already exists
	# unless effect chain asks us to get a new id
	#
	$logger->debug("$id: returning existing id") if $id and fx($id) and ! $clobber_id;
	return $id if $id and fx($id) and ! $clobber_id;
	
	if (  ! $clobber_id )
	{ 
		$id = $p->{cop_id} = $fx->{id_counter}  ;
      	$logger->debug("$id: new id issued");
	}
	else 
	{ 
		$logger->debug(sub{ ::fx($id) ? "$id: clobbering existing effect" 
				         : "$id: re-using effect id" });
	}


	my $i = effect_index($type);

	$logger->debug("Issuing a cop_id for track $n: $id");
	
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
		$logger->debug( "no settings found, loading defaults if present");
		
		# if the effect is a controller (has a parent), we don't 
		# initialize the first parameter (the control target)
		
		for my $j (0..$fx_cache->{registry}->[$i]->{count} - 1) {
		
			push @vals, $fx_cache->{registry}->[$i]->{params}->[$j]->{default};
		}
		$logger->debug( "copid: $id defaults: @vals");
		$p->{values} = \@vals;
	}
	
	params($id) = $p->{values};

	if ($parent_id) {
		$logger->debug( "parent found: $parent_id");

		# store relationship

		push @{ owns($parent_id) }, $id;
		$logger->debug("parent owns @{owns($parent_id)}");

		$logger->debug(sub{join " ", "my attributes:", yaml_out(fx($id))});
		parent($id) = $parent_id;
		$logger->debug(sub{join " ", "my attributes again:", yaml_out(fx($id))});
		#$logger->debug( "parameter: $parameter");

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


	# don't touch counter if we are clobbering
	
	if ( ! $clobber_id )
	{
		# make sure the counter $fx->{id_counter} will not occupy an
		# already used value
		while( fx( $fx->{id_counter} )){$fx->{id_counter}++};
	}

	$id;
}

## synchronize Ecasound chain operator parameters 
#  with Nama effect parameter

sub effect_update {
	local $config->{category} = 'ECI_FX';

	# update the parameters of the Ecasound chain operator
	# referred to by a Nama operator_id
	
	#logit('SUB','debug', "&effect_update");

	return unless valid_engine_setup();
	#my $es = eval_iam("engine-status");
	#$logger->debug( "engine is $es");
	#return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	$param++; # so the value at $p[0] is applied to parameter 1
	carp("$id: effect not found. skipping...\n"), return unless fx($id);
	my $chain = chain($id);
	return unless ::ChainSetup::is_ecasound_chain($chain);

	$logger->debug( "chain $chain id $id param $param value $val");

	# $param is zero-based. 
	# %{$fx->{params}} is  zero-based.

	my $old_chain = eval_iam('c-selected') if valid_engine_setup();
	ecasound_select_chain($chain);

	# update Ecasound's copy of the parameter
	if( is_controller($id)){
		my $i = ecasound_controller_index($id);
		$logger->debug( "controller $id: track: $chain, index: $i param: $param, value: $val");
		eval_iam("ctrl-select $i");
		eval_iam("ctrlp-select $param");
		eval_iam("ctrlp-set $val");
	}
	else { # is operator
		my $i = ecasound_operator_index($id);
		$logger->debug( "operator $id: track $chain, index: $i, offset: ".
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
	logit('SUB','debug', "&find_op_offsets");
	my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
	$logger->debug( join "\n\n",@op_offsets);
	for my $output (@op_offsets){
		my $chain_id;
		($chain_id) = $output =~ m/Chain "(\w*\d+)"/;
		# print "chain_id: $chain_id\n";
		next if $chain_id =~ m/\D/; # skip id's containing non-digits
									# i.e. M1
		my $quotes = $output =~ tr/"//;
		$logger->debug( "offset: $quotes in $output");
		$fx->{offset}->{$chain_id} = $quotes/2 - 1;  
	}
}

sub expanded_ops_list { # including controllers
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


sub automix {

	# get working track set
	
	my @tracks = grep{
					$tn{$_}->rec_status eq 'MON' or
					$bn{$_} and $tn{$_}->rec_status eq 'REC'
				 } $bn{Main}->tracks;

	say "tracks: @tracks";

	## we do not allow automix if inserts are present	

	say("Cannot perform automix if inserts are present. Skipping."), return
		if grep{$tn{$_}->prefader_insert || $tn{$_}->postfader_insert} @tracks;

	#use Smart::Comments '###';
	# add -ev to summed signal
	my $ev = add_effect( { chain => $tn{Master}->n, type => 'ev' } );
	### ev id: $ev

	# turn off audio output
	
	$tn{Master}->set(rw => 'OFF');

	### Status before mixdown:

	command_process('show');

	
	### reduce track volume levels  to 10%

	## accommodate ea and eadb volume controls

	my $vol_operator = type($tn{$tracks[0]}->vol);

	my $reduce_vol_command  = $vol_operator eq 'ea' ? 'vol / 10' : 'vol - 10';
	my $restore_vol_command = $vol_operator eq 'ea' ? 'vol * 10' : 'vol + 10';

	### reduce vol command: $reduce_vol_command

	for (@tracks){ command_process("$_  $reduce_vol_command") }

	command_process('show');

	generate_setup('automix') # pass a bit of magic
		or say("automix: generate_setup failed!"), return;
	connect_transport();
	
	# start_transport() does a rec_cleanup() on transport stop
	
	eval_iam('start'); # don't use heartbeat
	sleep 2; # time for engine to stabilize
	while( eval_iam('engine-status') ne 'finished'){ 
		print q(.); sleep 1; update_clock_display()}; 
	print " Done\n";

	# parse cop status
	my $cs = eval_iam('cop-status');
	### cs: $cs
	my $cs_re = qr/Chain "1".+?result-max-multiplier ([\.\d]+)/s;
	my ($multiplier) = $cs =~ /$cs_re/;

	### multiplier: $multiplier

	remove_effect($ev);

	# deal with all silence case, where multiplier is 0.00000
	
	if ( $multiplier < 0.00001 ){

		say "Signal appears to be silence. Skipping.";
		for (@tracks){ command_process("$_  $restore_vol_command") }
		$tn{Master}->set(rw => 'MON');
		return;
	}

	### apply multiplier to individual tracks

	for (@tracks){ command_process( "$_ vol*$multiplier" ) }

	### mixdown
	command_process('mixdown; arm; start');

	### turn on audio output

	# command_process('mixplay'); # rec_cleanup does this automatically

	#no Smart::Comments;
	
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
1;
__END__
