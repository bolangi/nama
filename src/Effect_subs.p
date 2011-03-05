# ------ Effect Routines -------

package ::;
use Modern::Perl;
our (
	%tn,
	%ti,
	$this_track,
	$this_op,
	%cops,
	%copp,
	$g,	
	$debug,
	$debug2,
	%is_ecasound_chain,
	$ui,
	%effect_i,
	@effects,
	$regenerate_setup,
	$cop_id,
	$magical_cop_id,
	%offset,
);


## effect functions

sub add_effect {
	
	$debug2 and print "&add_effect\n";
	
	my %p 			= %{shift()};
	my ($n,$code,$parent_id,$id,$parameter,$values) =
		@p{qw( chain type parent_id cop_id parameter values)};
	my $i = $effect_i{$code};

	# don't create an existing vol or pan effect
	
	return if $id and ($id eq $ti{$n}->vol 
				or $id eq $ti{$n}->pan);   

	$id = cop_add(\%p); 
	%p = ( %p, cop_id => $id); # replace chainop id
	$ui->add_effect_gui(\%p) unless $ti{$n}->hide;
	if( valid_engine_setup() ){
		my $er = engine_running();
		$ti{$n}->mute if $er;
		apply_op($id);
		$ti{$n}->unmute if $er;
	}
	$this_op = $id;
	$id;

}
sub modify_effect {
	my ($op_id, $parameter, $sign, $value) = @_;
		# $parameter: zero based
	my $cop = $cops{$op_id} 
		or print("$op_id: non-existing effect id. Skipping\n"), return; 
	my $code = $cop->{type};
	my $i = effect_index($code);
	defined $i or croak "undefined effect code for $op_id: ",yaml_out($cop);
	my $parameter_count = scalar @{ $effects[$i]->{params} };
	#print "op_id: $op_id, code: ",$cops{$op_id}->{type}," parameter count: $parameter_count\n";

	print("$op_id: effect does not exist, skipping\n"), return 
		unless $cops{$op_id};
	print("$op_id: parameter (", $parameter + 1, ") out of range, skipping.\n"), return 
		unless ($parameter >= 0 and $parameter < $parameter_count);
		my $new_value = $value; 
		if ($sign) {
			$new_value = 
 			eval (join " ",
 				$copp{$op_id}->[$parameter], 
 				$sign,
 				$value);
		};
	$this_op = $op_id;
	$debug and print "id $op_id p: $parameter, sign: $sign value: $value\n";
	effect_update_copp_set( 
		$op_id, 
		$parameter, 
		$new_value);
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
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect\n";
	my $id = shift;
	carp("$id: does not exist, skipping...\n"), return unless $cops{$id};
	my $n = $cops{$id}->{chain};
		
	my $parent = $cops{$id}->{belongs_to} ;
	$debug and print "id: $id, parent: $parent\n";

	my $object = $parent ? q(controller) : q(chain operator); 
	$debug and print qq(ready to remove $object "$id" from track "$n"\n);

	$ui->remove_effect_gui($id);

		# recursively remove children
		$debug and print "children found: ", join "|",@{$cops{$id}->{owns}},"\n";
		map{remove_effect($_)}@{ $cops{$id}->{owns} } 
			if defined $cops{$id}->{owns};
;

	if ( ! $parent ) { # i am a chain operator, have no parent
		remove_op($id);

	} else {  # i am a controller

	# remove the controller
 			
 		remove_op($id);

	# i remove ownership of deleted controller

		$debug and print "parent $parent owns list: ", join " ",
			@{ $cops{$parent}->{owns} }, "\n";

		@{ $cops{$parent}->{owns} }  =  grep{ $_ ne $id}
			@{ $cops{$parent}->{owns} } ; 
		$cops{$id}->{belongs_to} = undef;
		$debug and print "parent $parent new owns list: ", join " ",
			@{ $cops{$parent}->{owns} } ,$/;

	}
	# remove id from track object

	$ti{$n}->remove_effect( $id ); 
	delete $cops{$id}; # remove entry from chain operator list
	delete $copp{$id}; # remove entry from chain operator parameters list
	$this_op = undef;
}

sub position_effect {
	my($op, $pos) = @_;

	# we cannot handle controllers
	
	print("$op or $pos: controller not allowed, skipping.\n"), return 
		if grep{ $cops{$_}->{belongs_to} } $op, $pos;
	
	# first, modify track data structure
	
	print("$op: effect does not exist, skipping.\n"), return unless $cops{$op};
	my $track = $ti{$cops{$op}->{chain}};
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
		my $track2 = $ti{$cops{$pos}->{chain}};
		print("$pos: position belongs to a different track, skipping.\n"), return
			unless $track eq $track2;
		$new_op_index = nama_effect_index($pos); 
		# insert op
		splice @new_op_list, $new_op_index, 0, $op;
	}
	# reconfigure the entire engine (inefficient, but easy to do)
	#say join " - ",@new_op_list;
	@{$track->ops} = @new_op_list;
	$regenerate_setup++;
	reconfigure_engine();
	$this_track = $track;
	command_process('show_track');
}

sub nama_effect_index { # returns nama chain operator index
						# does not distinguish op/ctrl
	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $arr = $ti{$n}->ops;
	$debug and print "id: $id n: $n \n";
	$debug and print join $/,@{ $ti{$n}->ops }, $/;
		for my $pos ( 0.. scalar @{ $ti{$n}->ops } - 1  ) {
			return $pos if $arr->[$pos] eq $id; 
		};
}
sub ecasound_effect_index { 
	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $opcount;  # one-based
	$debug and print "id: $id n: $n \n",join $/,@{ $ti{$n}->ops }, $/;
	for my $op (@{ $ti{$n}->ops }) { 
			# increment only for ops, not controllers
			next if $cops{$op}->{belongs_to};
			++$opcount;
			last if $op eq $id
	} 
	$offset{$n} + $opcount;
}



sub remove_op {
	# remove chain operator from Ecasound engine

	$debug2 and print "&remove_op\n";

	# only if engine is configured
	return unless eval_iam('cs-connected') and eval_iam('cs-is-valid');

	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $index;
	my $parent = $cops{$id}->{belongs_to}; 

	# select chain
	
	return unless ecasound_select_chain($n);

	# deal separately with controllers and chain operators

	if ( !  $parent ){ # chain operator
		$debug and print "no parent, assuming chain operator\n";
	
		$index = ecasound_effect_index( $id );
		$debug and print "ops list for chain $n: @{$ti{$n}->ops}\n";
		$debug and print "operator id to remove: $id\n";
		$debug and print "ready to remove from chain $n, operator id $id, index $index\n";
		$debug and eval_iam("cs");
		eval_iam("cop-select ". ecasound_effect_index($id) );
		$debug and print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("cop-remove");
		$debug and eval_iam("cs");

	} else { # controller

		$debug and print "has parent, assuming controller\n";

		my $ctrl_index = ctrl_index($id);
		$debug and print eval_iam("cs");
		eval_iam("cop-select ".  ecasound_effect_index(root_parent($id)));
		$debug and print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("ctrl-select $ctrl_index");
		eval_iam("ctrl-remove");
		$debug and print eval_iam("cs");
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
	my $parent = $cops{$id}->{belongs_to};
	carp("$id: has no parent, skipping...\n"),return unless $parent;
	my $root_parent = $cops{$parent}->{belongs_to};
	$parent = $root_parent || $parent;
	$debug and print "$id: is a controller-controller, root parent: $parent\n";
	$parent;
}

sub ctrl_index { 
	my $id = shift;
	nama_effect_index($id) - nama_effect_index(root_parent($id));

}
sub cop_add {
	$debug2 and print "&cop_add\n";
	my $p = shift;
	my %p = %$p;
	$debug and say yaml_out($p);

	# return an existing id 
	return $p{cop_id} if $p{cop_id};
	

	# use an externally provided (magical) id or the
	# incrementing counter
	
	my $id = $magical_cop_id || $cop_id;

	# make entry in %cops with chain, code, display-type, children

	my ($n, $type, $parent_id, $parameter)  = 
		@p{qw(chain type parent_id parameter)};
	my $i = $effect_i{$type};


	$debug and print "Issuing a cop_id for track $n: $id\n";

	$cops{$id} = {chain => $n, 
					  type => $type,
					  display => $effects[$i]->{display},
					  owns => [] }; 

	$p->{cop_id} = $id;

	# set defaults
	
	if (! $p{values}){
		my @vals;
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$id}->{type} };
		
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		
		for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		$debug and print "copid: $id defaults: @vals \n";
		$copp{$id} = \@vals;
	}

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship
		$debug and print "parent owns" , join " ",@{ $cops{$parent_id}->{owns}}, "\n";

		push @{ $cops{$parent_id}->{owns}}, $id;
		$debug and print join " ", "my attributes:", (keys %{ $cops{$id} }), "\n";
		$cops{$id}->{belongs_to} = $parent_id;
		$debug and print join " ", "my attributes again:", (keys %{ $cops{$id} }), "\n";
		$debug and print "parameter: $parameter\n";

		# set fx-param to the parameter number, which one
		# above the zero-based array offset that $parameter represents
		
		$copp{$id}->[0] = $parameter + 1; 
		
 		# find position of parent and insert child immediately afterwards

 		my $end = scalar @{ $ti{$n}->ops } - 1 ; 
 		for my $i (0..$end){
 			splice ( @{$ti{$n}->ops}, $i+1, 0, $id ), last
 				if $ti{$n}->ops->[$i] eq $parent_id
 		}
	}
	else { push @{$ti{$n}->ops }, $id; } 

	# set values if present
	
	# ugly! The passed values ref may be used for multiple
	# instances, so we copy it here [ @$values ]
	
	$copp{$id} = [ @{$p{values}} ] if $p{values};

	# make sure the counter $cop_id will not occupy an
	# already used value
	
	while( $cops{$cop_id}){$cop_id++};

	$id;
}

sub effect_update_copp_set {
	my ($id, $param, $val) = @_;
	effect_update( @_ );
	$copp{$id}->[$param] = $val;
}
	

sub effect_update {

	# update the parameters of the Ecasound chain operator
	# referred to by a Nama operator_id
	
	#$debug2 and print "&effect_update\n";

	return unless valid_engine_setup();
	#my $es = eval_iam("engine-status");
	#$debug and print "engine is $es\n";
	#return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	$param++; # so the value at $p[0] is applied to parameter 1
	carp("$id: effect not found. skipping...\n"), return unless $cops{$id};
	my $chain = $cops{$id}{chain};
	return unless $is_ecasound_chain{$chain};

	$debug and print "chain $chain id $id param $param value $val\n";

	# $param is zero-based. 
	# %copp is  zero-based.

 	$debug and print join " ", @_, "\n";	

	my $old_chain = eval_iam('c-selected') if valid_engine_setup();
	ecasound_select_chain($chain);

	# update Ecasound's copy of the parameter
	if( is_controller($id)){
		my $i = ecasound_controller_index($id);
		$debug and print 
		"controller $id: track: $chain, index: $i param: $param, value: $val\n";
		eval_iam("ctrl-select $i");
		eval_iam("ctrlp-select $param");
		eval_iam("ctrlp-set $val");
	}
	else { # is operator
		my $i = ecasound_operator_index($id);
		$debug and print 
		"operator $id: track $chain, index: $i, offset: ",
		$offset{$chain}, " param $param, value $val\n";
		eval_iam("cop-select ". ($offset{$chain} + $i));
		eval_iam("copp-select $param");
		eval_iam("copp-set $val");
	}
	ecasound_select_chain($old_chain);
}

sub sync_effect_parameters {
	# when a controller changes an effect parameter
	# the effect state can differ from the state in
	# %copp, Nama's effect parameter store
	#
	# this routine syncs them in prep for save_state()
	
 	return unless valid_engine_setup();
	my $old_chain = eval_iam('c-selected');
	map{ sync_one_effect($_) } ops_with_controller();
	eval_iam("c-select $old_chain");
}

sub sync_one_effect {
		my $id = shift;
		my $chain = $cops{$id}{chain};
		eval_iam("c-select $chain");
		eval_iam("cop-select " . ( $offset{$chain} + ecasound_operator_index($id)));
		$copp{$id} = get_cop_params( scalar @{$copp{$id}} );
}

sub get_cop_params {
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
	grep{ scalar @{$cops{$_}{owns}} }
	map{ @{ $_->ops } } 
	map{ $tn{$_} } 
	grep{ $tn{$_} } 
	$g->vertices;
}

sub is_controller { my $id = shift; $cops{$id}{belongs_to} }

sub ecasound_operator_index { # does not include offset
	my $id = shift;
	my $chain = $cops{$id}{chain};
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $controller_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$controller_count++ if $cops{$ops[$i]}{belongs_to};
	}
	$position -= $controller_count; # skip controllers 
	++$position; # translates 0th to chain-position 1
}
	
	
sub ecasound_controller_index {
	my $id = shift;
	my $chain = $cops{$id}{chain};
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $operator_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$operator_count++ if ! $cops{$ops[$i]}{belongs_to};
	}
	$position -= $operator_count; # skip operators
	++$position; # translates 0th to chain-position 1
}

1;
__END__
