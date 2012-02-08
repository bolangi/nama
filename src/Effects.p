# ------ Effect Routines -------

package ::;
use Modern::Perl;
use List::MoreUtils qw(insert_after_string);
use Carp;
use ::Util qw(round);
no warnings 'uninitialized';

sub is_controller 	{ my $id = shift; $fx->{applied}->{$id}->{belongs_to} }
sub father : lvalue { my $id = shift; $fx->{applied}->{$id}->{belongs_to} }
sub chain  : lvalue { my $id = shift; $fx->{applied}->{$id}->{chain}      }
sub type   : lvalue { my $id = shift; $fx->{applied}->{$id}->{type}       }
sub owns   : lvalue { my $id = shift; $fx->{applied}->{$id}->{owns}       }
sub fx     : lvalue { my $id = shift; $fx->{applied}->{$id}               }
sub params : lvalue { my $id = shift; $fx->{params}->{$id}
}

sub set_chain_value {
	my $p = shift;

	return if $p->{chain}; # don't do it twice
	
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
	$debug and print(yaml_out($p));
}

sub add_effect { 
	my $p = shift;
	
	set_chain_value($p);

	my ($n,$code,$parent_id,$id,$suggested_id, $parameter,$values) =
		@$p{qw( chain type parent_id cop_id suggested_id parameter values)};
	! $p->{chain} and
		carp("effect id: $code is missing track number, skipping\n"), return ;

	$id = cop_add($p); 
	
	$ui->add_effect_gui($p) unless $ti{$n}->hide;
	if( valid_engine_setup() )
	{
		if (engine_running())
		{ 
			$ti{$n}->mute;
			apply_op($id);
			$ti{$n}->unmute;
		}
		else { apply_op($id) }
	}
	$id;

}
sub insert_effect {
	my ($before, $code, $values) = @_;
	say("$code: unknown effect. Skipping.\n"), return if ! effect_code($code);
	$code = effect_code( $code );	
	my $running = engine_running();
	print("Cannot insert effect while engine is recording.\n"), return 
		if $running and ::ChainSetup::really_recording();
	print("Cannot insert effect before controller.\n"), return 
		if is_controller($before);

	if ($running){
		$ui->stop_heartbeat;
		mute();
		eval_iam('stop');
		sleeper( 0.05);
	}
	my $n = chain($before) or 
		print(qq[Insertion point "$before" does not exist.  Skipping.\n]), 
		return;
	
	my $track = $ti{$n};
	$debug and print $track->name, $/;
	#$debug and print join " ",@{$track->ops}, $/; 

	# find offset 
	
	my $offset = 0;
	for my $id ( @{$track->ops} ){
		last if $id eq $before;
		$offset++;
	}

	# remove ops after insertion point if engine is connected
	# note that this will _not_ change the $track->ops list 

	my @ops = @{$track->ops}[$offset..$#{$track->ops}];
	$debug and print "ops to remove and re-apply: @ops\n";
	my $connected = eval_iam('cs-connected');
	if ( $connected ){  
		map{ remove_op($_)} reverse @ops; # reverse order for correct index
	}

	add_effect({track => $track, type => $code, values => $values} );

	$debug and print join " ",@{$track->ops}, $/; 

	# the new op_id is added to the end of the $track->ops list
	# so we need to move it to specified insertion point

	my $op = pop @{$track->ops}; 

	# the above acts directly on $track, because ->ops returns 
	# a reference to the array

	# insert the effect id 
	splice 	@{$track->ops}, $offset, 0, $op;

	$debug and print join " ",@{$track->ops}, $/; 

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
		or print("$op_id: non-existing effect id. Skipping\n"), return; 
	my $code = $cop->{type};
	my $i = effect_index($code);
	defined $i or croak "undefined effect code for $op_id: ",yaml_out($cop);
	my $parameter_count = scalar @{ $fx_cache->{registry}->[$i]->{params} };

	print("$op_id: effect does not exist, skipping\n"), return 
		unless fx($op_id);
	print("$op_id: parameter (", $parameter + 1, ") out of range, skipping.\n"), return 
		unless ($parameter >= 0 and $parameter < $parameter_count);
		my $new_value = $value; 
		if ($sign) {
			$new_value = 
 			eval (join " ",
 				$fx->{params}->{$op_id}->[$parameter], 
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
	$debug2 and print "&remove_effect\n";
	my $id = shift;
	carp("$id: does not exist, skipping...\n"), return unless $fx->{applied}->{$id};
	my $n 		= chain($id);
	my $parent 	= father($id);
	my $owns	= owns($id);
	$debug and print "id: $id, parent: $parent\n";

	my $object = $parent ? q(controller) : q(chain operator); 
	$debug and print qq(ready to remove $object "$id" from track "$n"\n);

	$ui->remove_effect_gui($id);

	# recursively remove children
	$debug and say "children found: ", join ",",@$owns if defined $owns;
	map{ remove_effect($_) } @$owns if defined $owns;
;

	# remove chain operator
	
	if ( ! $parent ) { remove_op($id) } 

	# remove controller
	
	else { 
 			
 		remove_op($id);

		# remove parent ownership of deleted controller

		my $parent_owns = owns($parent);
		$debug and say "parent $parent owns: ", join ",", @$parent_owns;

		@$parent_owns = (grep {$_ ne $id} @$parent_owns);
		$debug and say "parent $parent new owns list: ", join ",", @$parent_owns;

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
	$debug and print "id: $id n: $n \n";
	$debug and print join $/,@{ $ti{$n}->ops }, $/;
		for my $pos ( 0.. scalar @{ $ti{$n}->ops } - 1  ) {
			return $pos if $arr->[$pos] eq $id; 
		};
}
sub ecasound_effect_index { 
	my $id = shift;
	my $n = chain($id);
	my $opcount;  # one-based
	$debug and print "id: $id n: $n \n",join $/,@{ $ti{$n}->ops }, $/;
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
sub effect_code {
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

sub effect_index {
	my $code = shift;
	my $i = $fx_cache->{full_label_to_index}->{effect_code($code)};
	defined $i or warn "$code: effect index not found\n";
	$i
}

## Ecasound engine -- apply/remove chain operators

sub apply_ops {  # in addition to operators in .ecs file
	
	$debug2 and print "&apply_ops\n";
	for my $n ( map{ $_->n } ::Track::all() ) {
	$debug and print "chain: $n, offset: ", $fx->{offset}->{$n}, "\n";
 		next unless ::ChainSetup::is_ecasound_chain($n);

	# controllers will follow ops, so safe to apply all in order
		for my $id ( @{ $ti{$n}->ops } ) {
		apply_op($id);
		}
	}
	ecasound_select_chain($this_track->n) if defined $this_track;
}

sub apply_op {
	$debug2 and print "&apply_op\n";
	my $id = shift;
	! $id and carp "null id, skipping";
	return unless $id;
	my $selected = shift;
	$debug and print "id: $id\n";
	my $code = type($id);
	my $dad = father($id);
	my $chain = chain($id);
	$debug and print "chain: ",chain($id),"type: $code\n";
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ $fx->{params}->{$id} };
	$debug and print "values: @vals\n";

	# we start to build iam command

	my $add_cmd = $dad ? "ctrl-add " : "cop-add "; 
	
	$add_cmd .= $code . join ",", @vals;

	# append the -kx  operator for a controller-controller
	$add_cmd .= " -kx" if is_controller($dad);

	$debug and print "command:  ", $add_cmd, "\n";

	eval_iam("c-select $chain") if $selected != $chain;
	eval_iam("cop-select " . ecasound_effect_index($dad)) if $dad;
	eval_iam($add_cmd);

	my $ref = ref owns($id) ;
	$ref =~ /ARRAY/ or croak "expected array";
	my @owns = @{ owns($id) }; 
	$debug and say "children found: ", join ",", @{owns($id)};

}
sub remove_op {
	# remove chain operator from Ecasound engine

	$debug2 and print "&remove_op\n";

	# only if engine is configured
	return unless eval_iam('cs-connected') and eval_iam('cs-is-valid');

	my $id = shift;
	my $n = chain($id);

	# select chain
	
	return unless ecasound_select_chain($n);

	# deal separately with controllers and chain operators
	
	my $index;

	if ( ! is_controller($id) ){ # chain operator
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
	my $parent = father($id);
	carp("$id: has no parent, skipping...\n"),return unless $parent;
	father($parent) || $parent
}

## Nama effects are represented by entries in $fx->{applied}
## and by the ops array in each track, $track->ops

sub cop_add {
	$debug2 and print "&cop_add\n";
	my $p = shift;
	$debug and say yaml_out($p);

	# parameter is used only by GUI XXX
	my ($n, $type, $id, $parent_id, $parameter)  = 
		@$p{qw(chain type cop_id parent_id parameter)};

	# return existing op_id if effect already exists
	return $id if $id and fx($id);
	
	$id = $p->{cop_id} = $fx->{id_counter};

	my $i = effect_index($type);

	$debug and print "Issuing a cop_id for track $n: $id\n";
	
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
		$debug and print "no settings found, loading defaults if present\n";
		
		# if the effect is a controller (has a parent), we don't 
		# initialize the first parameter (the control target)
		
		for my $j (0..$fx_cache->{registry}->[$i]->{count} - 1) {
		
			push @vals, $fx_cache->{registry}->[$i]->{params}->[$j]->{default};
		}
		$debug and print "copid: $id defaults: @vals \n";
		$p->{values} = \@vals;
	}
	
	$fx->{params}->{$id} = $p->{values};

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship

		push @{ owns($parent_id) }, $id;
		$debug and say "parent owns" , join " ",@{owns($parent_id)};

		$debug and say join " ", "my attributes:", yaml_out(fx($id));
		father($id) = $parent_id;
		$debug and say join " ", "my attributes again:", yaml_out(fx($id));
		$debug and print "parameter: $parameter\n";

		# set fx-param to the parameter number, which one
		# above the zero-based array offset that $parameter represents
		
		#$fx->{params}->{$id}->[0] = $parameter + 1;  # XXX
			# only GUI sets $parameter XXXX
		
 		# find position of parent in the track ops array 
 		# and insert child immediately afterwards

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

	# update the parameters of the Ecasound chain operator
	# referred to by a Nama operator_id
	
	#$debug2 and print "&effect_update\n";

	return unless valid_engine_setup();
	#my $es = eval_iam("engine-status");
	#$debug and print "engine is $es\n";
	#return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	$param++; # so the value at $p[0] is applied to parameter 1
	carp("$id: effect not found. skipping...\n"), return unless fx($id);
	my $chain = chain($id);
	return unless ::ChainSetup::is_ecasound_chain($chain);

	$debug and print "chain $chain id $id param $param value $val\n";

	# $param is zero-based. 
	# %{$fx->{params}} is  zero-based.

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
		$fx->{offset}->{$chain}, " param $param, value $val\n";
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
	$fx->{params}->{$id}->[$param] = $val;
}

sub sync_effect_parameters {
	# when a controller changes an effect parameter
	# the effect state can differ from the state in
	# %{$fx->{params}}, Nama's effect parameter store
	#
	# this routine syncs them in prep for save_state()
	
 	return unless valid_engine_setup();
	my $old_chain = eval_iam('c-selected');
	map{ sync_one_effect($_) } ops_with_controller();
	eval_iam("c-select $old_chain");
}

sub sync_one_effect {
		my $id = shift;
		my $chain = chain($id);
		eval_iam("c-select $chain");
		eval_iam("cop-select " . ( $fx->{offset}->{$chain} + ecasound_operator_index($id)));
		$fx->{params}->{$id} = get_cop_params( scalar @{$fx->{params}->{$id}} );
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
	grep{ scalar @{owns($_)} }
	map{ @{ $_->ops } } 
	::ChainSetup::engine_tracks();
}


*parent = \&is_controller;

sub find_op_offsets {

	$debug2 and print "&find_op_offsets\n";
	my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
	$debug and print join "\n\n",@op_offsets; 
	for my $output (@op_offsets){
		my $chain_id;
		($chain_id) = $output =~ m/Chain "(\w*\d+)"/;
		# print "chain_id: $chain_id\n";
		next if $chain_id =~ m/\D/; # skip id's containing non-digits
									# i.e. M1
		my $quotes = $output =~ tr/"//;
		$debug and print "offset: $quotes in $output\n"; 
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
		expanded_ops_list( @{owns($_)} );
 	} @ops_list;
	@expanded
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


## register data about LADSPA plugins, and Ecasound effects and
#  presets (names, ids, parameters, hints) 

sub effects_cache {
	state $registry_format = 'json';
	join_path(&project_root, $file->{effects_cache} .  ".$registry_format");
}
sub prepare_static_effects_data{
	
	$debug2 and print "&prepare_static_effects_data\n";

	my $effects_cache = effects_cache();

	$debug and say join "\n", "newplugins:", new_plugins();
	if ($config->{opts}->{r} or new_plugins()){ 

		eval { unlink $effects_cache};
		print "Regenerating effects data cache\n";
	}

	if (-f $effects_cache and ! $config->{opts}->{C}){  
		$debug and print "found effects cache: $effects_cache\n";
		my $source = read_file($effects_cache); # scalar assign
		assign(
			data => decode($source, 'json'),
			vars => [qw($fx_cache)],
			class => '::'
		);
			
	} else {
		
		$debug and print "reading in effects data, please wait...\n";
		read_in_effects_data();  
		# cop-register, preset-register, ctrl-register, ladspa-register
		get_ladspa_hints();     
		integrate_ladspa_hints();
		integrate_cop_hints();
		sort_ladspa_effects();
		prepare_effects_help();
		serialize (
			file => $effects_cache, 
			vars => [qw($fx_cache)],
			class => '::',
			format => 'json');
	}

	prepare_effect_index();
}

sub ladspa_plugin_list {
	my @plugins;
	my %seen;
	for my $dir ( split ':', ladspa_path()){
		next unless -d $dir;
		opendir my ($dirh), $dir;
		push @plugins,  
			map{"$dir/$_"} 						# full path
			grep{ ! $seen{$_} and ++$seen{$_}}  # skip seen plugins
			grep{ /\.so$/} readdir $dirh;			# get .so files
		closedir $dirh;
	}
	@plugins
}

sub new_plugins {
	my $effects_cache = effects_cache();
	my @filenames = ladspa_plugin_list();	
	push @filenames, '/usr/local/share/ecasound/effect_presets',
                 '/usr/share/ecasound/effect_presets',
                 "$ENV{HOME}/.ecasound/effect_presets";
	my $effects_cache_stamp = modified_stamp($effects_cache);
	my $latest;
	map{ my $mod = modified_stamp($_);
		 $latest = $mod if $mod > $latest } @filenames;

	$latest > $effects_cache_stamp;
}

sub modified_stamp {
	# timestamp that file was modified
	my $filename = shift;
	#print "file: $filename\n";
	my @s = stat $filename;
	$s[9];
}
sub prepare_effect_index {
	$debug2 and print "&prepare_effect_index\n";
	%{$fx_cache->{partial_label_to_full}} = ();
	map{ 
		my $code = $_;
		my ($short) = $code =~ /:([-\w]+)/;
		if ( $short ) { 
			if ($fx_cache->{partial_label_to_full}->{$short}) { warn "name collision: $_\n" }
			else { $fx_cache->{partial_label_to_full}->{$short} = $code }
		}else{ $fx_cache->{partial_label_to_full}->{$code} = $code };
	} keys %{$fx_cache->{full_label_to_index}};
	#print yaml_out $fx_cache->{partial_label_to_full};
}
sub extract_effects_data {
	$debug2 and print "&extract_effects_data\n";
	my ($lower, $upper, $regex, $separator, @lines) = @_;
	carp ("incorrect number of lines ", join ' ',$upper-$lower,scalar @lines)
		if $lower + @lines - 1 != $upper;
	$debug and print"lower: $lower upper: $upper  separator: $separator\n";
	#$debug and print "lines: ". join "\n",@lines, "\n";
	$debug and print "regex: $regex\n";
	
	for (my $j = $lower; $j <= $upper; $j++) {
		my $line = shift @lines;
	
		$line =~ /$regex/ or carp("bad effect data line: $line\n"),next;
		my ($no, $name, $id, $rest) = ($1, $2, $3, $4);
		$debug and print "Number: $no Name: $name Code: $id Rest: $rest\n";
		my @p_names = split $separator,$rest; 
		map{s/'//g}@p_names; # remove leading and trailing q(') in ladspa strings
		$debug and print "Parameter names: @p_names\n";
		$fx_cache->{registry}->[$j]={};
		$fx_cache->{registry}->[$j]->{number} = $no;
		$fx_cache->{registry}->[$j]->{code} = $id;
		$fx_cache->{registry}->[$j]->{name} = $name;
		$fx_cache->{registry}->[$j]->{count} = scalar @p_names;
		$fx_cache->{registry}->[$j]->{params} = [];
		$fx_cache->{registry}->[$j]->{display} = qq(field);
		map{ push @{$fx_cache->{registry}->[$j]->{params}}, {name => $_} } @p_names
			if @p_names;
;
	}
}
sub sort_ladspa_effects {
	$debug2 and print "&sort_ladspa_effects\n";
#	print yaml_out($fx_cache->{split}); 
	my $aa = $fx_cache->{split}->{ladspa}{a};
	my $zz = $fx_cache->{split}->{ladspa}{z};
#	print "start: $aa end $zz\n";
	map{push @{$fx_cache->{ladspa_sorted}}, 0} ( 1 .. $aa ); # fills array slice [0..$aa-1]
	splice @{$fx_cache->{ladspa_sorted}}, $aa, 0,
		 sort { $fx_cache->{registry}->[$a]->{name} cmp $fx_cache->{registry}->[$b]->{name} } ($aa .. $zz) ;
	$debug and print "sorted array length: ". scalar @{$fx_cache->{ladspa_sorted}}, "\n";
}		
sub read_in_effects_data {
	
	$debug2 and print "&read_in_effects_data\n";

	my $lr = eval_iam("ladspa-register");

	#print $lr; 
	
	my @ladspa =  split "\n", $lr;
	
	# join the two lines of each entry
	my @lad = map { join " ", splice(@ladspa,0,2) } 1..@ladspa/2; 

	my @preset = grep {! /^\w*$/ } split "\n", eval_iam("preset-register");
	my @ctrl  = grep {! /^\w*$/ } split "\n", eval_iam("ctrl-register");
	my @cop = grep {! /^\w*$/ } split "\n", eval_iam("cop-register");

	$debug and print "found ", scalar @cop, " Ecasound chain operators\n";
	$debug and print "found ", scalar @preset, " Ecasound presets\n";
	$debug and print "found ", scalar @ctrl, " Ecasound controllers\n";
	$debug and print "found ", scalar @lad, " LADSPA effects\n";

	# index boundaries we need to make effects list and menus
	$fx_cache->{split}->{cop}{a}   = 1;
	$fx_cache->{split}->{cop}{z}   = @cop; # scalar
	$fx_cache->{split}->{ladspa}{a} = $fx_cache->{split}->{cop}{z} + 1;
	$fx_cache->{split}->{ladspa}{b} = $fx_cache->{split}->{cop}{z} + int(@lad/4);
	$fx_cache->{split}->{ladspa}{c} = $fx_cache->{split}->{cop}{z} + 2*int(@lad/4);
	$fx_cache->{split}->{ladspa}{d} = $fx_cache->{split}->{cop}{z} + 3*int(@lad/4);
	$fx_cache->{split}->{ladspa}{z} = $fx_cache->{split}->{cop}{z} + @lad;
	$fx_cache->{split}->{preset}{a} = $fx_cache->{split}->{ladspa}{z} + 1;
	$fx_cache->{split}->{preset}{b} = $fx_cache->{split}->{ladspa}{z} + int(@preset/2);
	$fx_cache->{split}->{preset}{z} = $fx_cache->{split}->{ladspa}{z} + @preset;
	$fx_cache->{split}->{ctrl}{a}   = $fx_cache->{split}->{preset}{z} + 1;
	$fx_cache->{split}->{ctrl}{z}   = $fx_cache->{split}->{preset}{z} + @ctrl;

	my $cop_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w.+?) # name, starting with word-char,  non-greedy
		# (\w+) # name
		,\s*  # comma spaces* 
		-(\w+)    # cop_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $preset_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w+) # name
		,\s*  # comma spaces* 
		-(pn:\w+)    # preset_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $ladspa_re = qr/
		^(\d+) # number
		\.    # dot
		\s+  # spaces
		(.+?) # name, starting with word-char,  non-greedy
		\s+     # spaces
		-(el:[-\w]+),? # ladspa_id maybe followed by comma
		(.*$)        # rest
	/x;

	my $ctrl_re = qr/
		^(\d+) # number
		\.     # dot
		\s+    # spaces
		(\w.+?) # name, starting with word-char,  non-greedy
		,\s*    # comma, zero or more spaces
		-(k\w+):?    # ktrl_id maybe followed by colon
		(.*$)        # rest
	/x;

	extract_effects_data(
		$fx_cache->{split}->{cop}{a},
		$fx_cache->{split}->{cop}{z},
		$cop_re,
		q(','),
		@cop,
	);


	extract_effects_data(
		$fx_cache->{split}->{ladspa}{a},
		$fx_cache->{split}->{ladspa}{z},
		$ladspa_re,
		q(','),
		@lad,
	);

	extract_effects_data(
		$fx_cache->{split}->{preset}{a},
		$fx_cache->{split}->{preset}{z},
		$preset_re,
		q(,),
		@preset,
	);
	extract_effects_data(
		$fx_cache->{split}->{ctrl}{a},
		$fx_cache->{split}->{ctrl}{z},
		$ctrl_re,
		q(,),
		@ctrl,
	);



	for my $i (0..$#{$fx_cache->{registry}}){
		 $fx_cache->{full_label_to_index}->{ $fx_cache->{registry}->[$i]->{code} } = $i; 
		 $debug and print "i: $i code: $fx_cache->{registry}->[$i]->{code} display: $fx_cache->{registry}->[$i]->{display}\n";
	}

	$debug and print "$fx_cache->{registry}\n======\n", yaml_out($fx_cache->{registry}); ; 
}

sub integrate_cop_hints {

	my @cop_hints =  @{ yaml_in( get_data_section('chain_op_hints_yml')) };
	for my $hashref ( @cop_hints ){
		#print "cop hints ref type is: ",ref $hashref, $/;
		my $code = $hashref->{code};
		$fx_cache->{registry}->[ $fx_cache->{full_label_to_index}->{ $code } ] = $hashref;
	}
}
sub ladspa_path {
	$ENV{LADSPA_PATH} || q(/usr/lib/ladspa);
}
sub get_ladspa_hints{
	$debug2 and print "&get_ladspa_hints\n";
	my @dirs =  split ':', ladspa_path();
	my $data = '';
	my %seen = ();
	my @plugins = ladspa_plugin_list();
	#pager join $/, @plugins;

	# use these regexes to snarf data
	
	my $pluginre = qr/
	Plugin\ Name:       \s+ "([^"]+)" \s+
	Plugin\ Label:      \s+ "([^"]+)" \s+
	Plugin\ Unique\ ID: \s+ (\d+)     \s+
	[^\x00]+(?=Ports) 		# swallow maximum up to Ports
	Ports: \s+ ([^\x00]+) 	# swallow all
	/x;

	my $paramre = qr/
	"([^"]+)"   #  name inside quotes
	\s+
	(.+)        # rest
	/x;
		
	my $i;

	for my $file (@plugins){
		my @stanzas = split "\n\n", qx(analyseplugin $file);
		for my $stanza (@stanzas) {

			my ($plugin_name, $plugin_label, $plugin_unique_id, $ports)
			  = $stanza =~ /$pluginre/ 
				or carp "*** couldn't match plugin stanza $stanza ***";
			$debug and print "plugin label: $plugin_label $plugin_unique_id\n";

			my @lines = grep{ /input/ and /control/ } split "\n",$ports;

			my @params;  # data
			my @names;
			for my $p (@lines) {
				next if $p =~ /^\s*$/;
				$p =~ s/\.{3}/10/ if $p =~ /amplitude|gain/i;
				$p =~ s/\.{3}/60/ if $p =~ /delay|decay/i;
				$p =~ s(\.{3})($config->{sample_rate}/2) if $p =~ /frequency/i;
				$p =~ /$paramre/;
				my ($name, $rest) = ($1, $2);
				my ($dir, $type, $range, $default, $hint) = 
					split /\s*,\s*/ , $rest, 5;
				$debug and print join( 
				"|",$name, $dir, $type, $range, $default, $hint) , $/; 
				#  if $hint =~ /logarithmic/;
				if ( $range =~ /toggled/i ){
					$range = q(0 to 1);
					$hint .= q(toggled);
				}
				my %p;
				$p{name} = $name;
				$p{dir} = $dir;
				$p{hint} = $hint;
				my ($beg, $end, $default_val, $resolution) 
					= range($name, $range, $default, $hint, $plugin_label);
				$p{begin} = $beg;
				$p{end} = $end;
				$p{default} = $default_val;
				$p{resolution} = $resolution;
				push @params, { %p };
			}

			$plugin_label = "el:" . $plugin_label;
			$fx_cache->{ladspa_help}->{$plugin_label} = $stanza;
			$fx_cache->{ladspa_id_to_filename}->{$plugin_unique_id} = $file;
			$fx_cache->{ladspa_label_to_unique_id}->{$plugin_label} = $plugin_unique_id; 
			$fx_cache->{ladspa_label_to_unique_id}->{$plugin_name} = $plugin_unique_id; 
			$fx_cache->{ladspa_id_to_label}->{$plugin_unique_id} = $plugin_label;
			$fx_cache->{ladspa}->{$plugin_label}->{name}  = $plugin_name;
			$fx_cache->{ladspa}->{$plugin_label}->{id}    = $plugin_unique_id;
			$fx_cache->{ladspa}->{$plugin_label}->{params} = [ @params ];
			$fx_cache->{ladspa}->{$plugin_label}->{count} = scalar @params;
			$fx_cache->{ladspa}->{$plugin_label}->{display} = 'scale';
		}	#	pager( join "\n======\n", @stanzas);
		#last if ++$i > 10;
	}

	$debug and print yaml_out($fx_cache->{ladspa}); 
}

sub srate_val {
	my $input = shift;
	my $val_re = qr/(
			[+-]? 			# optional sign
			\d+				# one or more digits
			(\.\d+)?	 	# optional decimal
			(e[+-]?\d+)?  	# optional exponent
	)/ix;					# case insensitive e/E
	my ($val) = $input =~ /$val_re/; #  or carp "no value found in input: $input\n";
	$val * ( $input =~ /srate/ ? $config->{sample_rate} : 1 )
}
	
sub range {
	my ($name, $range, $default, $hint, $plugin_label) = @_; 
	my $multiplier = 1;;
	my ($beg, $end) = split /\s+to\s+/, $range;
	$beg = 		srate_val( $beg );
	$end = 		srate_val( $end );
	$default = 	srate_val( $default );
	$default = $default || $beg;
	$debug and print "beg: $beg, end: $end, default: $default\n";
	if ( $name =~ /gain|amplitude/i ){
		$beg = 0.01 unless $beg;
		$end = 0.01 unless $end;
	}
	my $resolution = ($end - $beg) / 100;
	if    ($hint =~ /integer|toggled/i ) { $resolution = 1; }
	elsif ($hint =~ /logarithmic/ ) {

		$beg = round ( log $beg ) if $beg;
		$end = round ( log $end ) if $end;
		$resolution = ($end - $beg) / 100;
		$default = $default ? round (log $default) : $default;
	}
	
	$resolution = d2( $resolution + 0.002) if $resolution < 1  and $resolution > 0.01;
	$resolution = dn ( $resolution, 3 ) if $resolution < 0.01;
	$resolution = int ($resolution + 0.1) if $resolution > 1 ;
	
	($beg, $end, $default, $resolution)

}
sub integrate_ladspa_hints {
	$debug2 and print "&integrate_ladspa_hints\n";
	map{ 
		my $i = $fx_cache->{full_label_to_index}->{$_};
		# print("$_ not found\n"), 
		if ($i) {
			$fx_cache->{registry}->[$i]->{params} = $fx_cache->{ladspa}->{$_}->{params};
			# we revise the number of parameters read in from ladspa-register
			$fx_cache->{registry}->[$i]->{count} = scalar @{$fx_cache->{ladspa}->{$_}->{params}};
			$fx_cache->{registry}->[$i]->{display} = $fx_cache->{ladspa}->{$_}->{display};
		}
	} keys %{$fx_cache->{ladspa}};

my %L;
my %M;

map { $L{$_}++ } keys %{$fx_cache->{ladspa}};
map { $M{$_}++ } grep {/el:/} keys %{$fx_cache->{full_label_to_index}};

for my $k (keys %L) {
	$M{$k} or $debug and print "$k not found in ecasound listing\n";
}
for my $k (keys %M) {
	$L{$k} or $debug and print "$k not found in ladspa listing\n";
}


$debug and print join "\n", sort keys %{$fx_cache->{ladspa}};
$debug and print '-' x 60, "\n";
$debug and print join "\n", grep {/el:/} sort keys %{$fx_cache->{full_label_to_index}};

#print yaml_out $fx_cache->{registry}; exit;

}

## generate effects help data

sub prepare_effects_help {

	# presets
	map{	s/^.*? //; 				# remove initial number
					$_ .= "\n";				# add newline
					my ($id) = /(pn:\w+)/; 	# find id
					s/,/, /g;				# to help line breaks
					push @{$fx_cache->{user_help}},    $_;  #store help

				}  split "\n",eval_iam("preset-register");

	# LADSPA
	my $label;
	map{ 

		if (  my ($_label) = /-(el:[-\w]+)/  ){
				$label = $_label;
				s/^\s+/ /;				 # trim spaces 
				s/'//g;     			 # remove apostrophes
				$_ .="\n";               # add newline
				push @{$fx_cache->{user_help}}, $_;  # store help

		} else { 
				# replace leading number with LADSPA Unique ID
				s/^\d+/$fx_cache->{ladspa_label_to_unique_id}->{$label}/;

				s/\s+$/ /;  			# remove trailing spaces
				substr($fx_cache->{user_help}->[-1],0,0) = $_; # join lines
				$fx_cache->{user_help}->[-1] =~ s/,/, /g; # 
				$fx_cache->{user_help}->[-1] =~ s/,\s+$//;
				
		}

	} reverse split "\n",eval_iam("ladspa-register");


#my @lines = reverse split "\n",eval_iam("ladspa-register");
#pager( scalar @lines, $/, join $/,@lines);
	
	#my @crg = map{s/^.*? -//; $_ .= "\n" }
	#			split "\n",eval_iam("control-register");
	#pager (@lrg, @prg); exit;
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


1;
__END__
