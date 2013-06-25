# ------ Effect Routines -------
{
package ::Effects; 
use Modern::Perl;
use List::MoreUtils qw(insert_after_string);
use ::Assign qw(json_out json_out);
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
	*process_command    = \&::process_command;
}

use Exporter qw(import);
our %EXPORT_TAGS = ( 'all' => [ qw(

					effect_index
					full_effect_code

					effect_entry_is_bad
					check_fx_consistency

					effect_init
					add_effect
					remove_effect
					position_effect
					remove_fader_effect
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
			
					restore_effects

					fxn

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();

sub effect_entry_is_bad {
		my $id = shift;
		! $id  									# undef key ''
		or ! $fx->{params}->{$id}				# missing params entry 
		or ! ref $fx->{applied}->{$id} 			# applied entry is not ref 
		or keys %{$fx->{applied}->{$id}} < 3	# not enough key/val pairs
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
		$p->{chain} = fxn($p->{parent_id})->chain
	}
	# set chain from insert target if known (insert effect)
	
	elsif( $p->{before} )
	{
		$p->{chain} = fxn($p->{before})->chain;
	}
	#logpkg('debug',(json_out($p));

}


sub add_effect {
	my $p = shift;
	logsub("&add_effect");
	#logpkg('debug',sub{ "add effect arguments - 0:\n".json_out($p)});
	
	set_chain_value($p);

	### We prohibit creating effects on the Mixdown track	

	### We check $track->forbid_user_ops
	### which is set on the Mixdown track,

	### An alternative would be giving each
    ### Track its own add_effect method

	### For now this is a single case

	die "user effects forbidden on this track" 
		if $ti{$p->{chain}} 
		and $ti{$p->{chain}}->forbid_user_ops 
		and $p->{type} !~ /$config->{latency_op}/; 

	logpkg('debug',sub{ "add effect arguments - 1:\n".json_out($p)});

	# either insert or add, depending on 'before' setting
	
	my $id = $p->{before} ?  _insert_effect($p) : _add_effect($p);
	
	# return effect ID
	$id
}


sub _add_effect { 
	my $p = shift;
	my (    $n,   $before, $code,$parent_id,$id, $values) =
	@$p{qw( chain before    type parent_id  effect_id values)};
	! $p->{chain} and
		carp("effect id: $code is missing track number, skipping\n"), return ;

	$p->{values} = fx_defaults($code) 
		if ! $values 
		or ref $values and ! scalar @{ $values };

	$id = effect_init($p); 
	
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
		if fxn($before)->is_controller;

	if ($running){
		$ui->stop_heartbeat;
		::mute();
		::stop_command();
		sleeper( 0.05); 
	}
	my $n = fxn($before)->chain or 
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
		# $parameter: one-based
	
	$parameter--; # convert to zero-based
	my $cop = fxn($op_id)
		or print("$op_id: non-existing effect id. Skipping.\n"), return; 
	my $code = $cop->type;
	my $i = effect_index($code);
	defined $i or croak "undefined effect code for $op_id: ",json_out($cop);
	my $parameter_count = scalar @{ $cop->about->{params} };

	print("$op_id: parameter (", $parameter + 1, ") out of range, skipping.\n"), return 
		unless ($parameter >= 0 and $parameter < $parameter_count);
	print("$op_id: parameter $parameter is read-only, skipping\n"), return 
		if $cop->is_read_only($parameter);
		my $new_value = $value; # unless $sign
		if ($sign) {
			$new_value = 
 			eval (join " ",
 				$cop->params->[$parameter], 
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
				modify_effect($op_id, $parameter, $sign, $value);
		} @$parameters;
	} @$op_ids;
}

sub remove_effect { 
	logsub("&remove_effect");
	my $id = shift;
	my $FX = fxn($id)
		or logpkg('logcarp',"$id: does not exist, skipping...\n"), return;
	my $n 		= $FX->chain;
	my $parent 	= $FX->parent;
	my $owns	= $FX->owns;
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
	@{$ti{$n}->{ops}} = grep { $_ ne $id } @{$ti{$n}->{ops}} if $ti{$n};

	# remove entries for chain operator attributes and parameters
 	delete $fx->{applied}->{$id}; # remove entry from chain operator list
    delete $fx->{params }->{$id}; # remove entry from chain operator parameters likk
	$this_op = undef;
}

sub position_effect {
	my($op, $pos) = @_;

	# we cannot handle controllers
	
	print("$op or $pos: controller not allowed, skipping.\n"), return 
		if grep{ fxn($_)->is_controller } $op, $pos;
	
	# first, modify track data structure
	
	my $FX = fxn($op);
	my $POS = fxn($pos);
	my $track = $ti{$FX->chain};

	my $op_index = $FX->track_effect_index;
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
		print("$pos: position belongs to a different track, skipping.\n"), return
			unless $track eq $track2;
		$new_op_index = $POS->track_effect_index; 
		# insert op
		splice @new_op_list, $new_op_index, 0, $op;
	}
	# reconfigure the entire engine (inefficient, but easy to do)
	#say join " - ",@new_op_list;
	@{$track->ops} = @new_op_list;
	$setup->{changed}++;
	reconfigure_engine();
	$this_track = $track;
	process_command('show_track');
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

sub fx_defaults {
	my $i = effect_index(shift());
	my $values = [];
	foreach my $p ( @{ $fx_cache->{registry}->[$i]->{params} })
	{
		return [] unless defined $p->{default};
		push @$values, $p->{default};
	}
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
	my $code = fxn($id)->type;
	my $dad = fxn($id)->parent;
	my $chain = fxn($id)->chain; 
	logpkg('debug', "chain: ".fxn($id)->chain." type: $code");
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ fxn($id)->params };
	logpkg('debug', "values: @vals");

	# we start to build iam command

	my $add_cmd = $dad ? "ctrl-add " : "cop-add "; 
	
	$add_cmd .= $code . join ",", @vals;

	# append the -kx  operator for a controller-controller
	$add_cmd .= " -kx" if $dad and $dad->is_controller;

	logpkg('debug', "command: $add_cmd");

	eval_iam("c-select $chain") if $selected_chain != $chain;
	eval_iam("cop-select " . $dad->ecasound_effect_index) if $dad;
	eval_iam($add_cmd);
	eval_iam("cop-bypass on") if fxn($id)->bypassed;

	my $owns = fxn($id)->owns;
	(ref $owns) =~ /ARRAY/ or croak "expected array";
	logpkg('debug',"children found: ". join ",", @$owns);

}
sub remove_op {
	# remove chain operator from Ecasound engine

	logsub("&remove_op");
	local $config->{category} = 'ECI_FX';

	# only if engine is configured
	return unless valid_engine_setup();

	my $id = shift;
	my $self = fxn($id);
	my $n = $self->chain;

	# select chain
	
	return unless ecasound_select_chain($n);

	# deal separately with controllers and chain operators
	
	my $index;

	if ( ! $self->is_controller) { # chain operator
		logpkg('debug', "no parent, assuming chain operator");
	
		$index = $self->ecasound_effect_index;
		logpkg('debug', "ops list for chain $n: @{$ti{$n}->ops}");
		logpkg('debug', "operator id to remove: $id");
		logpkg('debug', "ready to remove from chain $n, operator id $id, index $index");
		logpkg('debug',sub{eval_iam("cs")});
		eval_iam("cop-select ".  $self->ecasound_effect_index);
		logpkg('debug',sub{"selected operator: ". eval_iam("cop-selected")});
		eval_iam("cop-remove");
		logpkg('debug',sub{eval_iam("cs")});

	} else { # controller

		logpkg('debug', "has parent, assuming controller");

		my $ctrl_index = $self->ecasound_controller_index;
		logpkg('debug', eval_iam("cs"));
		eval_iam("cop-select ".  $self->root_parent->ecasound_effect_index);
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
#                              = track_effect_index HH - track_effect_index C 
#               
#
# for Nama, chain op array index 2, 
#           ctrl arrray index = chain op array index + ctrl_index
#                             = effect index - 1 + ctrl_index 
#
#

## Nama effects 

## have a unique ID from capital letters
## are represented by entries in $fx->{applied}, $fx->{params}
## IDs are kept in the $track->ops

## Rules for allocating IDs
## new_effect_id() - issues a new ID
## effect_init()    - initializes a Nama effect, should be called effect_init()
## add_effect

sub new_effect_id { 

		# increment $fx->{id_counter} if necessary
		# to find an unused effect_id to allocate
		
		while( $fx->{applied}->{$fx->{id_counter}}){ $fx->{id_counter}++};
		$fx->{id_counter}
}


sub effect_init {
	logsub("&effect_init");
	my $p = shift;
	logpkg('debug',sub{json_out($p)});

	my ($n,  $type, $id, $parent_id)  = 
	@$p{qw(chain type effect_id parent_id)};

	# return existing op_id if effect already exists
	# unless effect chain asks us to get a new id
	#
	logpkg('debug',"$id: returning existing id") if $id and fxn($id);
	return $id if $id and fxn($id);

	my 	$allocated = "recycled";
	if ( ! $id ){ 

		$id = $p->{effect_id} = new_effect_id();
		$allocated = "issued";
	}

	logpkg('debug',"$id: effect id $allocated");

	my $i = effect_index($type);

	logpkg('debug',"Issuing a effect_id for track $n: $id");
	
	# make entry in $fx->{applied} with chain, code, display-type, children

	$fx->{applied}->{$id} = 
	{
		chain 	=> $n, 
		type 	=> $type,
		display => $fx_cache->{registry}->[$i]->{display},
		owns 	=> [],
	}; 

	my $FX = fxn($id);

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
	
	$FX->set(params => $p->{values});

	if ($parent_id) {
		logpkg('debug', "parent found: $parent_id");

		# store relationship

		my $parent = fxn($parent_id);
		my $owns = $parent->owns;
		push @$owns, $id;
		logpkg('debug',"parent owns @$owns");

		logpkg('debug',sub{join " ", "my attributes:", json_out($fx->{applied})});
		#fxn($id)->set(parent => $parent_id);
		$FX->set(parent => $parent_id);
		logpkg('debug',sub{join " ", "my attributes again:", json_out($fx->{applied})});
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

	my $FX = fxn($id) or carp("$id: effect not found. skipping...\n"), return;
	$param++; # so the value at $p[0] is applied to parameter 1
	my $chain = $FX->chain;
	return unless ::ChainSetup::is_ecasound_chain($chain);

	logpkg('debug', "chain $chain id $id param $param value $val");

	# $param is zero-based. 
	# %{$fx->{params}} is  zero-based.

	my $old_chain = eval_iam('c-selected') if valid_engine_setup();
	ecasound_select_chain($chain);

	# update Ecasound's copy of the parameter
	if( $FX->is_controller ){
		my $i = $FX->ecasound_controller_index;
		logpkg('debug', "controller $id: track: $chain, index: $i param: $param, value: $val");
		eval_iam("ctrl-select $i");
		eval_iam("ctrlp-select $param");
		eval_iam("ctrlp-set $val");
	}
	else { # is operator
		my $i = $FX->ecasound_effect_index - $FX->offset;
		logpkg('debug', "operator $id: track $chain, index: $i, offset: ".  $FX->offset . " param $param, value $val");
		eval_iam("cop-select ". ($FX->offset + $i));
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
	fxn($id)->params->[$param] = $val;
}

sub sync_effect_parameters {
	local $config->{category} = 'ECI_FX';
	# when a controller changes an effect parameter
	# the effect state can differ from the state in
	# $fx->{params}, Nama's effect parameter store
	#
	# this routine syncs them in prep for save_state()
	
 	return unless valid_engine_setup();
	my $old_chain = eval_iam('c-selected');
	map{ $_->sync_one_effect } grep{ $_ }  map{ fxn($_) } ops_with_controller(), ops_with_read_only_params();
	eval_iam("c-select $old_chain");
}

	

sub get_ecasound_cop_params {
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
	grep{ ! $_->is_controller }
	grep{ scalar @{$_->owns} }
	map{ fxn($_) }
	map{ @{ $_->ops } } 
	::ChainSetup::engine_tracks();
}
sub ops_with_read_only_params {
	grep{ $_->has_read_only_param() }
	map{ fxn($_) }
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
		expanded_ops_list( reverse @{fxn($_)->owns} );

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
		$ops_data->{$_}            = $fx->{applied}->{$_};
		$ops_data->{$_}->{params}  = $fx->{params }->{$_};
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
	set_bypass_state($track, 'on', @ops);
}
sub restore_effects {
	my($track, @ops) = @_;
	set_bypass_state($track, 'off', @ops);
}

sub set_bypass_state {
	
	local $config->{category} = 'ECI_FX';
	my($track, $bypass_state, @ops) = @_;

	# only process ops that belong to this track
	@ops = intersect_with_track_ops_list($track,@ops);

	$track->mute;
	eval_iam("c-select ".$track->n);

	foreach my $op ( @ops)
	{ 
		my $FX = fxn($op);
		my $i = $FX->ecasound_effect_index;
		eval_iam("cop-select $i");
		eval_iam("cop-bypass $bypass_state");
		$FX->set(bypassed => ($bypass_state eq 'on') ? 1 : 0);
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
		map { fxn($_) or push @uninstantiated_op_ids, $_ } @ops;

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
		grep { ! fxn($_)->params or ! fxn($_)->type or !  fxn($_)->chain } 
		grep { $_ } keys %{$fx->{applied}};

	if(@incomplete_entries)
	{
		$result->{applied}->{incomplete_entries} = \@incomplete_entries;
		$result->{is_error}++
	}
	$result;
}
sub remove_fader_effect {
	my ($track, $role) = @_;
	remove_effect($track->$role);
	delete $track->{$role} 
}
# Object interface for effects

sub fxn {
	my $id = shift;
	bless {id => $id}, '::Effect' if $id and $fx->{applied}->{$id}
}
}
{
package ::Effect;
use Modern::Perl;
use ::Globals qw($fx $fx_cache %tn %ti);
use Carp qw(confess);
our $AUTOLOAD;
my %is_field = map{ $_ => 1} qw(id owns bypassed parent type chain params);
sub id 			{ my $self = shift; $self->{id} }
sub owns 		{ my $self = shift; $fx->{applied}->{$self->{id}}->{owns}		}
sub bypassed 	{ my $self = shift; $fx->{applied}->{$self->{id}}->{bypassed}	}
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
sub is_controller { my $self = shift; $self->parent } 

sub has_read_only_param {
	my $self = shift;
	my $entry = $fx_cache->{registry}->[$self->registry_index];
		for(0..scalar @{$entry->{params}} - 1)
		{
			no warnings 'uninitialized';
			return 1 if $entry->{params}->[$_]->{dir} eq 'output' 
		}
}

sub registry_index {
	my $self = shift;
	$fx_cache->{full_label_to_index}->{ $self->type };
}
sub alternative_ecasound_controller_index { 
	my $self = shift;
	$self->track_effect_index - $self->root_parent->track_effect_index
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
		$operator_count++ if ! fxn($ops[$i])->is_controller;
	}
	$position -= $operator_count; # skip operators
	++$position; # translates 0th to chain-position 1
}
sub ecasound_effect_index { 
	my $self = shift;
	my $n = $self->chain;
	my $id = $self->id;
	my $opcount = 0;
	#logpkg('debug', "id: $id, n: $n, ops: @{ $ti{$n}->ops }" );
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
		eval_iam("c-select $chain");
		eval_iam("cop-select " .( $self->ecasound_effect_index ) );
		$self->set(params => get_ecasound_cop_params( scalar @{$self->params} ));
}
sub offset {
	my $self = shift;
	$fx->{offset}->{$self->chain}
}
sub root_parent { 
	my $self = shift;
	carp($self->id.": has no parent, skipping...\n"),return unless $self->parent;
	$self->parent->parent if $self->parent|| $self->parent;
}
sub about {
	my $self = shift;
	$fx_cache->{registry}->[$self->registry_index]
}
sub AUTOLOAD {
	my $self = shift;
	# get tail of method call
	my ($call) = $AUTOLOAD =~ /([^:]+)$/;
	# see if this can be satisfied by a field from
	# the corresponding effects registry entry
	$self->about->{$call}
}
sub DESTROY {}

}
1;
__END__
