use Carp;
sub wav_dir { $wav_dir };  # we agree to hereinafter use &wav_dir
sub config_file { "config.yml" }
sub ecmd_dir { join_path(wav_dir, ".ecmd") }
sub this_wav_dir {$project_name and join_path(wav_dir, $project_name) }
sub project_dir  {$project_name and join_path(ecmd_dir, $project_name) }

sub sc { print join $/, "STATE_C", yaml_out( \%state_c); }
sub status_vars {
	serialize -class => '::', -vars => \@status_vars;
}

sub discard_object {
	shift @_ if (ref $_[0]) =~ /UI/; # discard_object
	@_;
}
sub prepare {  

	local $debug = $debug3;

	$debug2 and print "&prepare\n";

    $yw = Data::YAML::Writer->new;
    $yr = Data::YAML::Reader->new;

	$debug and print ("\%opts\n======\n", yaml_out(\%opts)); ; 

	my $create = $opts{c} ? 1 : 0;

	$ecasound  = $ENV{ECASOUND} ? $ENV{ECASOUND} : q(ecasound);

	## now i should read .ecmdrc
	## should have .ecmd holding files.
	
	## but for me, i am really really happy to read my 
	# internal ones. 
	
	read_config(); # sets $wav_dir

	$opts{d} and $wav_dir = $opts{d};

	-d $wav_dir or croak

	("wav_dir: '$wav_dir' not found, invoke using -d option ");


	# TODO
	# Tie mixdown version suffix to global monitor version 

	new_engine();
	initialize_oids();
	prepare_static_effects_data() unless $opts{e};
	#print "keys effect_i: ", join " ", keys %effect_i;
	#map{ print "i: $_, code: $effect_i{$_}->{code}\n" } keys %effect_i;
	#die "no keys";	
	$debug and print "wav_dir: ", wav_dir(), $/;
	$debug and print "this_wav_dir: ", this_wav_dir(), $/;
	$debug and print "project_dir: ", project_dir() , $/;
	1;	
}

sub eval_iam {
	local $debug = $debug3;
	$debug2 and print "&eval_iam\n";
	my $command = shift;
	$debug and print "iam command: $command\n";
	my $result = $e->eci($command);
	$debug and print "$result\n" unless $command =~ /register/;
	my $errmsg = $e->errmsg();
	# $errmsg and carp("IAM WARN: ",$errmsg), 
	# not needed ecasound prints error on STDOUT
	$e->errmsg('');
	$result;
}
## configuration file

sub global_config{
	my $config = join_path( &ecmd_dir, &config_file );
	-f $config and io($config)->all;
}
sub project_config {
	&project_dir or return;
	my $config = join_path( &project_dir, &config_file );
	-f $config and io($config)->all;
}
sub config { strip_all( &project_config or &global_config or $default) }

sub read_config {
	$debug2 and print "&read_config\n";
	local $debug = $debug3;
	#print &config; exit;
	%cfg = %{  $yr->read(config())  };
	#print yaml_out( $cfg{abbreviations}); exit;
	*subst = \%{ $cfg{abbreviations} }; # alias
	#print yaml_out( \%subst ); exit;
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	#print yaml_out( \%cfg ); #exit;
	#print ("doing nothing") if $a eq $b eq $c; exit;
	assign_var( \%cfg, @config_vars); 
	$mixname eq 'mix' or die" bad mixname: $mixname";

}
sub walk_tree {
	#$debug2 and print "&walk_tree\n";
	my $ref = shift;
	map { substitute($ref, $_) } 
		grep {$_ ne q(abbreviations)} 
			keys %{ $ref };
}
sub substitute{
	my ($parent, $key)  = @_;
	my $val = $parent->{$key};
	#$debug and print qq(key: $key val: $val\n);
	ref $val and walk_tree($val)
		or map{$parent->{$key} =~ s/$_/$subst{$_}/} keys %subst;
}
## project handling
=comment
sub load_project { project(@_) }

sub project { # object method
#	my $ui = shift; 
	my %h = @_;
	$debug2 and print "&load_project\n";
	$debug and print "project name: $h{-name} create: $h{-create}\n";
	carp ("project name required\n"), return unless $h{-name};
	my $old_project = $project_name;
	$project_name = $h{-name};
	if ( ! -d project_dir) {
		$debug and print "directory not found: ", project_dir, $/;
		if ( $h{-create} ){ 
			$debug and print join " ", 
				"creating directories:", this_wav_dir, project_dir, $/;
			create_dir(this_wav_dir, project_dir);
		} else { 
			print "project: ", project_dir, $/;
			$project_name = $old_project;
			return;
		}
	}
	read_config;
	initialize_project_data;
	remove_small_wavs; 
	print "reached here!!!\n";
	retrieve_state( $h{-settings} ? $h{-settings} : $state_store_file) unless $opts{m} ;
	$debug and print "found ", scalar @all_chains, "chains\n";
	add_mix_track, dig_ruins unless scalar @all_chains;
	$ui->global_version_buttons;

}

=cut
sub load_project {
	my %h = @_;
	$debug2 and print "&load_project\n";
	$debug and print "\$project: $project name: $h{-name} create: $h{-create}\n";
	return unless $h{-name} or $project;

	# we could be called from Tk with variable $project _or_
	# called with a hash with 'name' and 'create' fields.
	
	my $project = remove_spaces($project); # internal spaces to underscores
	$project_name = $h{-name} ? $h{-name} : $project;
	$h{-create} and 
		print ("Creating directories....\n"),
		map{create_dir($_)} &this_wav_dir, &project_dir;
# =comment 
# 	# OPEN EDITOR TODO
# 	my $new_file = join_path ($ecmd_home, $project_name, $parameters);
# 	open PARAMS, ">$new_file" or carp "couldn't open $new_file for write: $!\n";
# 	print PARAMS $configuration;
# 	close PARAMS;
# 	system "$ENV{EDITOR} $new_file" if $ENV{EDITOR};
# =cut
	read_config();
	initialize_project_data();
	remove_small_wavs(); 
	print "reached here!!!\n";
	retrieve_state( $h{-settings} ? $h{-settings} : $state_store_file) unless $opts{m} ;
	$debug and print "found ", scalar @all_chains, "chains\n";
	add_mix_track(), dig_ruins() unless scalar @all_chains;
	$ui->global_version_buttons();

}
#The mix track will always be track index 1 i.e. $state_c{$n}
# for $n = 1, And take index 1.

sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# assign_var($project_init_file, @project_vars);

	$last_version = 0;
	%track_names = ();
	%state_c        = ();   #  chain related state
	%state_t        = ();   # take related state
	%cops        = ();   
	$cop_id           = "A"; # autoincrement
	%copp           = ();    # chain operator parameters, dynamic
	                        # indexed by {$id}->[$param_no]
							# and others
	%old_vol = ();

	%take        = (); # the group a chain belongs to # by chain_id
	%chain       = (); # the chain_id corresponding to a track name
	#%alias      = ();  # a way of naming takes

	@takes       = ();  
	@record		= ();
	@monitor	= ();
	@mute = (); 
	@all_chains  = (); # indices of all chains
	@input_chains = ();
	@output_chains = ();

	$i           = 0;  # chain counter
	$t           = 0;  # take counter

	%widget_c = ();
	@widget_t = ();
	%widget_e = ();
	

	# time related
	
	$markers_armed = 0;
	@marks = ();

	
	# volume settings
	
	%old_vol = ();

	# $is_armed = 0;

$ui->destroy_widgets();

increment_take();  # to 1

$ui->take_gui;

}
## track and wav file handling

sub add_track {
	@_ = discard_object(@_);
	$debug2 and print "&add_track\n";
	return 0 if transport_running();
	my $name = shift;
	if ($track_names{$name}){
		$debug and carp ("Track name in use\n");
		return 0;
	}
	$state_t{$t}->{rw} = "REC"; # enable recording for the group
	$track_names{$name}++;
	$i++; # global variable track counter
	register_track($i, $name, $ch_r, $ch_m);
	find_wavs($i);
	#set_active_version($i) if ! defined $state_c{$i}->{active};
	$track_name = $ch_m = $ch_r = undef;

	$state_c{$i}->{ops} = [] if ! defined $state_c{$i}->{ops};
	$state_c{$i}->{rw} = "REC" if ! defined $state_c{$i}->{rw};
	$ui->track_gui($i);
	$debug and print "Added new track!\n",yaml_out(\%state_c);
}
sub add_mix_track {
	return if $opts{m}; # or ! -e join_path(&project_dir,$state_store_file);
	add_track($mixname) ;
	$state_t{$t}->{rw} = "MUTE"; 
	new_take(); # $t increments
	$state_t{$t}->{rw} = "MON";
}
sub mix_suffix {
	my $stub = shift;
	$stub eq $mixname ? ' (mix)' : ''
}
sub restore_track {
	$debug2 and print "&restore_track\n";
	@_ = discard_object(@_);
	my $n = shift;
	find_wavs($n);
	$ui->track_gui($n), $ui->refresh();
}
sub register_track {
	@_ = discard_object(@_);
	$debug2 and print "&register_track\n";
	my ($i, $name, $ch_r, $ch_m) = @_;
	$debug and print <<VARS;
i          : $i
name       : $name
Rec channel: $ch_r
Mon channel: $ch_m
VARS
  	push @all_chains, $i;
  	# print "ALL chains: @all_chains\n";
	$take{$i} = $t;
	$chain{$name} = $i;
	$state_c{$i}->{rw} = "REC";
	$state_c{$i}->{ch_m} = $ch_m;
	$state_c{$i}->{ch_r} = $ch_r;
	$name =~ s/\.wav$//;
	$state_c{$i}->{file} = $name;
}
sub dig_ruins { 

	# only if there are no tracks , 
	# we exclude the mixchain
	#
	
	$debug2 and print "&dig_ruins";

	if ( ! grep { $_ ne $mixchain and $_ ne $project_name} keys %state_c ) {  # there are no tracks yet

		# look for wave files
		
		my $d = this_wav_dir();
		opendir WAV, $d or carp "couldn't open $d: $!";

		# remove version numbers
		
		my @wavs = grep{s/(_\d+)?\.wav//i} readdir WAV;

		$debug and print "tracks found: @wavs\n";

		map{add_track($_)}@wavs;

	}
}
sub find_wavs {
	@_ = discard_object(@_);
	my $n = shift; 
	$debug2 and print "&find_wavs\n";
	$debug and print "track: $n\n";
	$debug and print "this_wav dir: ", this_wav_dir,": $n\n";

	
	# GET VERSIONS 
	#  Assign bare (unversioned) file as version 1 
	
	$debug and 
	print "getting versions for chain $n, state_c{$n}->{file}\n";
		my %versions =  get_versions (
			this_wav_dir(),
			$state_c{$n}->{file},
			'_', 'wav' )  ;
		if ($versions{bare}) {  $versions{1} = $versions{bare}; 
			delete $versions{bare};
		}
	$debug and print "\%versions\n================\n", yaml_out(\%versions);
		delete $state_c{$n}->{targets};
		$state_c{$n}->{targets} = { %versions };

		 $state_c{$n}->{versions} = [ sort { $a <=> $b } 
		 	keys %{$state_c{$n}->{targets}} ];
		$debug and print join " ", "versions: ",@ {$state_c{$n}->{versions}} , "\n\n";
		my $this_last = $state_c{$n}->{versions}->[-1];
no warnings;
		$last_version = $this_last if $this_last > $last_version ;
use warnings;
# VERSION	
		# set last version active if the current active version is missing
		$state_c{$n}->{active} = $state_c{$n}->{versions}->[-1]
			unless grep{ $state_c{$n}->{active} == $_ }
				@{$state_c{$n}->{versions}};

	
	$debug and print "\$last_version: $last_version\n";

}
sub remove_small_wavs {
	$debug2 and print "&remove_small_wavs\n";
	# left by a recording chainsetup that is 
	# connected by not started

	my $a = this_wav_dir();
	my $cmd = qq(find $a  -name '*.wav' -size 44c);
	$debug and print $cmd; 
	my @wavs = split "\n",qx($cmd);
	#map {system qq(ls -l $_ ) } @wavs; exit;
	map { print ($_, "\n") if -s == 44 } @wavs; 
	map { unlink $_ if -s == 44 } @wavs; 
}
## track group handling
#
sub new_take {
	$debug2 and print "&new_take\n";
	increment_take();
	$ui->take_gui; $ui->refresh_t();
}
sub increment_take {
	$debug2 and print "&increment_take\n";
			return if transport_running(); 
					$t++;
					$state_t{active} = $t;
					$state_t{$t}->{rw} = "REC";
					push @takes, $t;
	$debug and print "take $t\n";
}
sub decrement_take {
			$debug2 and print "&decrement_take\n";
			return if transport_running(); 
			return if $t == 1; 
			# can't proceed if tracks already defined for this take
			$debug and print ("found chains, aborting"),return 
				if grep{$take{$_}==$t} @all_chains;
			pop @takes;
			$t--;
			$state_t{active} = $t;
			# print SESSION "CANCEL take $t\n";
			my @candidate = $take_frame->children;
			$candidate[-1]->destroy;
			
}
sub select_take {
	my ($t, $status) = @_; 
	$status =~ m/REC|MON|MUTE/
		or croak "illegal status: $status, expected one of REC|MON|MUTE\n";
	return if transport_running();
	$state_t{$t}->{rw} = $status; 
	$state_t{active} = $t; 
	$ui->refresh();
	setup_transport();
	connect_transport();
}
sub add_volume_control {
	my $n = shift;
	
	my $vol_id = cop_add({
				chain => $n, 
				type => 'ea',
				cop_id => $state_c{$n}->{vol}, # often undefined
				});
	
	$state_c{$n}->{vol} = $vol_id;  # save the id for next time
}
sub add_pan_control {
	my $n = shift;
	
	my $vol_id = cop_add({
				chain => $n, 
				type => 'epp',
				cop_id => $state_c{$n}->{pan}, # often undefined
				});
	
	$state_c{$n}->{pan} = $vol_id;  # save the id for next time
}
## version functions

sub selected_version {
	# return track-specific version if selected,
	# otherwise return global version selection
	# but only if this version exists
	my $n = shift;
no warnings;
	my $version = $state_c{$n}->{active} 
		? $state_c{$n}->{active} 
		: $monitor_version ;
	(grep {$_ == $version } @{$state_c{$n}->{versions}}) ? $version : undef;

use warnings;
}
sub set_active_version {
	my $n = shift;
	$debug and print "chain $n: versions: @{$state_c{$n}->{versions}}\n";    
		$state_c{$n}->{active} = $state_c{$n}->{versions}->[-1] 
			if $state_c{$n}->{versions};    
		$debug and print "active version, chain $n: $state_c{$n}->{active}\n\n";
}
sub new_version {
	$last_version + 1;
}
sub get_versions {
	my ($dir, $basename, $sep, $ext) = @_;

	$debug and print "getver: dir $dir basename $basename sep $sep ext $ext\n\n";
	opendir WD, $dir or carp ("can't read directory $dir: $!");
	$debug and print "reading directory: $dir\n\n";
	my %versions = ();
	for my $candidate ( readdir WD ) {
		$debug and print "candidate: $candidate\n\n";
		$candidate =~ m/^ ( $basename 
		   ($sep (\d+))? 
		   \.$ext )
		   $/x or next;
		$debug and print "match: $1,  num: $3\n\n";
		$versions{ $3 ? $3 : 'bare' } =  $1 ;
	}
	$debug and print "get_version: " , yaml_out(\%versions);
	closedir WD;
	%versions;
}
sub mon_vert {
	my $ver = shift;
	return if $ver == $monitor_version;
	# store @{ $state_c{$ver}{ops} }
	# store %copp
	# remove effects  and use $ver's set if there are effects for $v
	$monitor_version = $ver;
	$ui->refresh();
}
## chain setup generation
#
sub collect_chains {
	$debug2 and print "&collect\n";
	local $debug = $debug3;
	@monitor = @record = ();

	
	for my $n (@all_chains) {
	$debug and print "rec_status $n: ", rec_status($n), "\n";
		push (@monitor, $n) if rec_status($n) eq "MON"; 
		push (@record, $n) if rec_status($n) eq "REC";
	}

	$debug and print "monitor chains:  @monitor\n\n";
	$debug and print "record chains:  @record\n\n";
	$debug and print "this take: $state_t{active}\n\n";
		
}
sub rec_status {
	my $n = shift;
	local $debug = $debug3;
	$debug2 and print "&rec_status\n";
	$debug and print "found object: ", ref $n, $/ if ref $n;
	no warnings;
	$debug and print "chain $n: active: selected_version($n) trw: $state_t{$take{$n}}->{rw} crw: $state_c{$n}->{rw}\n";
	use warnings;

no warnings;
my $file = join_path(this_wav_dir ,  $state_c{$n}->{targets}->{selected_version($n)});
my $file_exists = -f $file;
use warnings;
    return "MUTE" if $state_c{$n}->{rw} eq "MON" and ! $file_exists;
	return "MUTE" if $state_c{$n}->{rw} eq "MUTE";
	return "MUTE" if $state_t{$take{$n}}->{rw} eq "MUTE";
	if ($take{$n} == $state_t{active} ) {

		if ($state_t{$take{$n}}->{rw} eq "REC") {

			
			if ($state_c{$n}->{rw} eq "REC"){
				return "REC" if $state_c{$n}->{ch_r};
				return "MON" if $file_exists; #or carp "file not found;
				return "MUTE";
			}
		}
	}
	return "MON" if selected_version($n);
	return "MUTE";
}
sub really_recording {  # returns filename stubs

#	scalar @record  # doesn't include mixdown track
	print join "\n", "", ,"file recorded:", keys %{$outputs{file}}; # includes mixdown
	keys %{$outputs{file}}; # includes mixdown
}
sub make_io_lists {
	#local $debug = $debug3;
	$debug2 and print "&make_io_lists\n";
	@input_chains = @output_chains = ();

	%inputs = (); # chain fragments
	$inputs{mixed} = [];
	%outputs = ();      
	%post_input = ();
	%pre_output = ();
	my $rec_status;

	# set up track independent chains for MIX and STEREO (type: mixed)
	for my $oid (@oids) {
		my %oid = %{$oid};
		next unless lc $oid{type} eq 'mixed' and $oid_status{ $oid{name} };
			push @{ $inputs{mixed} }, $oid{id};
		if (lc $oid{output} eq 'file') {
			$outputs{file}->{ $mixname } = [ $oid{id} ] ;
		} else { # assume device
			defined $outputs{$oid{output}} or $outputs{$oid{output}} = [];
			push @{ $outputs{$oid{output}} }, $oid{id}
		#	hash_push( \%outputs, $oid{output}, $oid{id});
		}
	}

	for my $n (@all_chains) {
		$debug and print "chain $n: begin\n";
		$rec_status = rec_status($n);
		next if $rec_status eq "MUTE";

OID:		for my $oid (@oids) {

			# rec_setup comes last so that
			# we can check inputs{cooked}->$n to
			# see if it is needed.

			my %oid = %{$oid};
			
			next if $oid{type} eq 'mixed'; # already done
			next if $oid{name} eq 'rec_setup' and ! $inputs{cooked}->{$n};
			next if $oid{name} eq 'mix_setup' and ! @{ $inputs{mixed} };

			no warnings;
			my $chain_id = $oid{id}. $n; 
			use warnings;

			# check per-project setting for output oids

			next if ! $oid_status{ $oid{name} };
			$debug and print "Active oid match candidate found...\n";
			$debug and print "chain_id: $chain_id\n";
			$debug and print "oid name: $oid{name}\n";
			$debug and print "oid target: $oid{target}\n";
			$debug and print "oid input: $oid{input}\n";
			$debug and print "oid output: $oid{output}\n";
			$debug and print "oid type: $oid{type}\n";

		# check track $n against template

			next unless $oid{target} eq 'all' or lc $oid{target} eq lc $rec_status; 

			# if we've arrived here we will create chains
			$debug and print "really making chains!\n";

 #######     INPUTS

			if ($oid{type} eq 'raw')  {  #  only mon_setup, rec_setup and rec_file
			$debug and print "oid type is raw!\n";
				if ($oid{input} eq 'file') { # only mon_setup
					$debug and print "oid input is file!\n";
					defined $inputs{file}->{ $state_c{$n}->{file} } 
						or  $inputs{file}->{ $state_c{$n}->{file} } = [];
					push @{ $inputs{file}->{ $state_c{$n}->{file} } }, $chain_id;
				}
				else {   # we presume it is a device

					$debug and print "we presume it is a device\n";
					defined $inputs{$oid{input}}
						or  $inputs{$oid{input}} = [];
					push @{ $inputs{$oid{input}} }, $chain_id;

					#   if status is 'rec' every raw customer gets
					#   rec_setup's post_input string

				$post_input{$chain_id} .= rec_route($n) if lc $rec_status eq 'rec';

				}
		}
		elsif ($oid{type} eq 'cooked') {    
			$debug and print "hmmm... cooked!\n";
			defined $inputs{cooked}->{$n} or $inputs{cooked}->{$n} = [];
			push @{ $inputs{cooked}->{$n} }, $chain_id;
		}
		else { croak "$oid{name}: neither input defined nor type 'cooked'"; }

 #######     OUTPUTS

		if( defined $oid{output}) {
			if ($oid{output} eq 'file') {
				$debug and print "output is 'file'\n";

				defined $outputs{file}->{ $state_c{$n}->{file} } 
					or  $outputs{file}->{ $state_c{$n}->{file} } = [];
				push @{ $outputs{file}->{ $state_c{$n}->{file} } }, $chain_id;
			}
			elsif ($oid{output} eq 'loop') { # only rec_setup and mon_setup
				my $loop_id = "loop,$n";
				$debug and print "output is 'loop'\n";
				$outputs{ $loop_id } = [ $chain_id ]; 
			}
			elsif ($oid{output} eq $loopa ) { # only mix_setup
				$debug and print "output is 'mix_loop'\n";
				defined $outputs{ $loopa } 
					or $outputs{ $loopa } = [];
				push @{ $outputs{ $loopa } } , $chain_id; 
			}
			else  { 

				$debug and print "presume output is a device\n";
				defined $outputs{$oid{output}} or $outputs{$oid{output}} = [];
				push @{ $outputs{$oid{output}} }, $chain_id;


			}
			# add intermediate processing
		} # fi
		my ($post_input, $pre_output);
		$post_input = &{$oid{post_input}}($n) if defined $oid{post_input};
		$pre_output = &{$oid{pre_output}}($n) if defined $oid{pre_output};
		$debug and print "pre_output: $pre_output, post_input: $post_input\n";
		$pre_output{$chain_id} .= $pre_output if defined $pre_output;
		$post_input{$chain_id} .= $post_input 
			if defined $post_input and $chain_id ne '1'; # MIX

			# TODO no channel copy for stereo input files
            # such as version 1 backing.wav
			
		} # next oid


	}     # next $n

	# add signal multiplier
# 
# 	for my $dev (grep{$_ ne 'file'} keys %outputs){
# 		my @chain_ids = @{$outputs{$dev}};
# 		 map{
# 		 	$pre_output{$_} .=  " -ea:" . 100 * scalar @chain_ids 
# 				unless @chain_ids < 2
# 		} @chain_ids;
# 	}

	#$debug and print "\@oids\n================\n", yaml_out(\@oids);
	$debug and print "\%post_input\n================\n", yaml_out(\%post_input);
	$debug and print "\%pre_output\n================\n", yaml_out(\%pre_output);
	$debug and print "\%inputs\n================\n", yaml_out(\%inputs);
	$debug and print "\%outputs\n================\n", yaml_out(\%outputs);


}
sub rec_route {
	my $n = shift;
	return if $state_c{$n}->{ch_r} == 1;
	return if ! defined $state_c{$n}->{ch_r};
	"-erc:$state_c{$n}->{ch_r},1 -f:$raw_to_disk_format"
}
sub route {
	my ($width, $dest) = @_;
	return undef if $dest == 1 or $dest == 0;
	$debug and print "route: width: $width, destination: $dest\n\n";
	my $offset = $dest - 1;
	my $map ;
	for my $c ( map{$width - $_ + 1} 1..$width ) {
		$map .= " -erc:$c," . ( $c + $offset);
		$map .= " -eac:0,"  . $c;
	}
	$map;
}
sub hash_push {
	my ($hash_ref, $key, @vals) = @_;
	$hash_ref->{$key} = [] if ! defined $hash_ref->{$key};
	push @{ $hash_ref->{$key} }, @vals;
}
sub eliminate_loops {
	my $n = shift;
	return unless defined $inputs{cooked}->{$n} and scalar @{$inputs{cooked}->{$n}} == 1;
	# get customer's id from cooked list and remove it from the list

	my $cooked_id = pop @{ $inputs{cooked}->{$n} }; 

	# add chain $n to the list of the customer's output device 
	
	no warnings;
	my ($oid) = grep{ $cooked_id =~ /$_->{id}/ } @oids;
	use warnings;
	my %oid = %{$oid};
	defined $outputs{ $oid{output} } or $outputs{ $oid{output}} = [];
	push @{ $outputs{ $oid{output} } }, $n;

	

	# remove chain $n as source for the loop

	my $loop_id = "loop,$n";
	delete $outputs{$loop_id}; 
	
	# remove customers that use loop as input

	delete $inputs{$loop_id}; 

	# remove cooked customer from his output device list

	@{ $outputs{$oid{output}} } = grep{$_ ne $cooked_id} @{ $outputs{$oid->{output}} };

	# transfer any intermediate processing to numeric chain,
	# deleting the source.
	no warnings;
	$post_input{$n} .= $post_input{$cooked_id};
	$pre_output{$n} .= $pre_output{$cooked_id}; 
	use warnings;
	delete $post_input{$cooked_id};
	delete $pre_output{$cooked_id};

}
=comment    

%inputs
  |----->device-->$devname-->[ chain_id, chain_id,... ]
  |----->file---->$filename->[ chain_id, chain_id,... ]
  |----->bus1---->loop_id--->[ chain_id, chain_id,... ]
  |----->cooked-->loop_id--->[ chain_id, chain_id,... ]
  |_____>mixed___>loop_id___>[ chain_id, chain_id,... ]

%outputs
  |----->device-->$devname-->[ chain_id, chain_id,... ]
  |----->file---->$key**---->[ chain_id, chain_id,... ]
  |----->bus1---->loop_id--->[ chain_id, chain_id,... ]
  |----->cooked-->loop_id--->[ chain_id, chain_id,... ]
  |_____>mixed___>loop_id___>[ chain_id, chain_id,... ]

  ** consists of full path to the file ($filename) followed
  by a space, followed the output format specification.

=cut
sub write_chains {
	$debug2 and print "&write_chains\n";


	# $bus->apply;
	# $mixer->apply;
	# $ui->write_chains

	# we can assume that %inputs and %outputs will have the
	# same lowest-level keys
	#
	my @buses = grep { $_ ne 'file' and $_ ne 'device' } keys %inputs;
	
	### Setting devices as inputs (used by i.e. rec_setup)
	
	for my $dev (keys %{ $inputs{devices} } ){

		$debug and print "dev: $dev\n";
		push  @input_chains, 
		join " ", "-a:" . (join ",", @{ $inputs{$dev} }),
			"-f:" .  $devices{$dev}->{input_format},
			"-i:" .  $devices{$dev}->{ecasound_id}, 
	}

	#####  Setting devices as outputs
	#
	for my $dev ( keys %{ $outputs{devices} }){
			push @output_chains, join " ",
				"-a:" . (join "," , @{ $outputs{devices}->{$dev} }),
				"-f:" . $devices{$dev}->{output_format},
				"-o:". $devices{$dev}->{ecasound_id};
	}

	### Setting loops as inputs 

	for my $bus( @buses ){ # i.e. 'mixed', 'cooked'
		for my $loop ( keys %{ $inputs{$bus} }){
			push  @input_chains, 
			join " ", 
				"-a:" . (join ",", @{ $inputs{$bus}->{$loop} }),
				"-i:$loop";
		}
	}
	##### Setting files as inputs (used by mon_setup)

	for my $full_path (keys %{ $inputs{file} } ) {
		$debug and print "monitor input file: $file\n";
		my $chain_ids = join ",",@{ $inputs{file}->{$full_path} };
		push @input_chains, join ( " ",
					"-a:".$chain_ids,
			 		"-i:".$full_path,

	   );
 	}
	##### Setting files as outputs (used by rec_file and mix)

	for my $key ( keys %{ $outputs{file} } ){
		my ($full_path, $format) = split " ", $key;
		$debug and print "chain: $n, record output file: $name\n";
		my $chain_ids = join ",",@{ $outputs{file}->{$key} };
		
		push @output_chains, join ( " ",
			 "-a:".$chain_ids,
			 "-f:".$format,
			 "-o:".$full_path,
		 );
			 
	}

	# $debug and print "\%state_c\n================\n", yaml_out(\%state_c);
	# $debug and print "\%state_t\n================\n",  yaml_out(\%state_t);
							
		
	## write general options
	
	my $ecs_file = "# ecasound chainsetup file\n\n\n";
	$ecs_file   .= "# general\n\n";
	$ecs_file   .= $ecasound_globals;
	$ecs_file   .= "\n\n\n# audio inputs\n\n";
	$ecs_file   .= join "\n", sort @input_chains;
	$ecs_file   .= "\n\n# post-input processing\n\n";
	$ecs_file   .= join "\n", sort map{ "-a:$_ $post_input{$_}"} keys %post_input;
	$ecs_file   .= "\n\n# pre-output processing\n\n";
	$ecs_file   .= join "\n", sort map{ "-a:$_ $pre_output{$_}"} keys %pre_output;
	$ecs_file   .= "\n\n# audio outputs\n\n";
	$ecs_file   .= join "\n", sort @output_chains, "\n";
	
	$debug and print "ECS:\n",$ecs_file;
	my $sf = join_path(&project_dir, $chain_setup_file);
	open ECS, ">$sf" or croak "can't open file $sf:  $!\n";
	print ECS $ecs_file;
	close ECS;
}
sub new_wav_name {
	# used to name output file
	my $stub = shift;
	my $version;
	if (@record) {  # we are recording an audio input
		$version = new_version(); # even mix track
	}
	else { # we are only mixing
		$version = $stub eq $mixname  # mix track 
			? ($use_monitor_version_for_mixdown 
					? $monitor_version 
					: $state_c{1}->{versions}->[-1] + 1
				)
			: new_version();
	}
	join_path(this_wav_dir,	"$stub\_$version.wav");
}
sub output_format {
	my $stub = shift;
	$stub eq $project_name or $stub eq $mixname
		? $mix_to_disk_format
		: $mixer_out_format
}
## templates for generating chains

sub initialize_oids {
	local $debug = $debug3;
	$debug2 and print "&initialize_oids\n";

@oids = @{ $yr->read($oids) };


# these are templates for building chains
map {	
	my $name = $_;
	map{ 		defined $_->{$name} 
					and $_->{$name} =~ /(&)(.+)/ 
					and $_->{$name} = \&$2 
	} @oids; 
} qw( post_input pre_output);
#map{ $_->{post_input} =~ /(&)(.+)/ and $_->{post_input} = \&{ $2 } } @oids; 
#map{ $_->{pre_output} =~ /(&)(.+)/ and $_->{pre_output} = \&{ $2 } } @oids; 


$debug and print "rec_setup $oids[-1]->{input}\n";

	# oid settings
	
	map{ $oid_status{$_->{name}} = $_->{default} eq 'on' ? 1 : 0 } @oids;
	$debug and print yaml_out(\%oid_status); 

}
sub mono_to_stereo { " -erc:1,2 " }

sub pre_multi {
	$debug2 and print "&pre_multi\n";
	my $n = shift;
	$debug and print "track: $n\n";
	return if ! defined $state_c{$n}->{ch_m} or $state_c{$n}{ch_m} == 1;
	route(2,$state_c{$n}->{ch_m}); # stereo signal
}
sub convert_to_jack {
	map{ $_->{input} = q(jack)} grep{ $_->{name} =~ /rec_/ } @oids;	
	map{ $_->{output} = q(jack)} grep{ $_->{name} =~ /live|multi|stereo/ } @oids;	
}
sub convert_to_alsa { initialize_oids }

## transport functions

sub load_ecs {
		my $project_file = join_path(&project_dir , $chain_setup_file);
		eval_iam("cs-remove $project_file");
		eval_iam("cs-load ". $project_file);
		$debug and map{print "$_\n\n"}map{$e->eci($_)} qw(cs es fs st ctrl-status);
}
sub new_engine { 
	system qq(killall $ecasound);
	sleep 1;
	system qq(killall -9 $ecasound);
	$e = Audio::Ecasound->new();
}
sub setup_transport {
	$debug2 and print "&setup_transport\n";
	collect_chains();
	make_io_lists();
	#map{ eliminate_loops($_) } @all_chains;
	#print "minus loops\n \%inputs\n================\n", yaml_out(\%inputs);
	#print "\%outputs\n================\n", yaml_out(\%outputs);
	write_chains();
}
sub connect_transport {
	load_ecs(); 
	carp("Invalid chain setup, cannot arm transport.\n"),return unless eval_iam("cs-is-valid");
	find_op_offsets(); 
	apply_ops();
	eval_iam('cs-connect');
	carp("Invalid chain setup, cannot arm transport.\n"), return 
		unless eval_iam("engine-status") eq 'not started' ;
	eval_iam('engine-launch');
	carp("Invalid chain setup, cannot arm transport.\n"), return
		unless eval_iam("engine-status") eq 'stopped' ;
	$length = eval_iam('cs-get-length'); 
	$ui->length_display(-text => colonize($length));
	eval_iam("cs-set-length $length") unless @record;
	$ui->clock_config(-text => colonize(0));
	print eval_iam("fs");
	$ui->flash_ready();
	
}
sub start_transport { 
	$debug2 and print "&start_transport\n";
	carp("Invalid chain setup, aborting start.\n"),return unless eval_iam("cs-is-valid");
	eval_iam('start');
	sleep 1; # time for engine
	start_clock();
}
sub stop_transport { 
	$debug2 and print "&stop_transport\n"; $e->eci('stop');
	$ui->project_label_configure(-background => $old_bg);
	# what if we are recording
}
sub transport_running {
#	$debug2 and print "&transport_running\n";
	 $e->eci('engine-status') eq 'running' ;
}
sub disconnect_transport {
	return if transport_running();
	eval_iam('cs-disconnect') }


sub toggle_unit {
	if ($unit == 1){
		$unit = 60;
		
	} else{ $unit = 1; }
}
sub show_unit { $time_step->configure(
	-text => ($unit == 1 ? 'Sec' : 'Min') 
)}
## clock and clock-refresh functions ##
#

sub start_clock {
	$clock_id = $clock->repeat(1000, \&refresh_clock);
}
sub restart_clock {
	eval q($clock_id->cancel);
	start_clock();
}
sub refresh_clock{
	update_clock();
	my $status = eval_iam('engine-status');
	return if $status eq 'running' ;
	$clock_id->cancel;
	$ui->project_label_configure(-background => $old_bg);
	if ($status eq 'error') { new_engine();
		&connect_transport unless &really_recording; 
	}
	elsif ($status eq 'finished') {
		&connect_transport unless &really_recording; 
	}
	else { # status: stopped, not started, undefined
	&rec_cleanup if &really_recording();
	}

}
## recording head positioning

sub to_start { 
	return if really_recording();
	eval_iam(qq(cs-set-position 0));
	restart_clock();
}
sub to_end { 
	# ten seconds shy of end
	return if really_recording();
	my $end = eval_iam(qq(cs-get-length)) - 10 ;  
	eval_iam(qq(cs-set-position $end));
	restart_clock();
} 
sub jump {
	$debug2 and print "&jump\n";
	return if really_recording();
	my $delta = shift;
	my $here = eval_iam(qq(getpos));
	$debug and print "delta: $delta\nhere: $here\nunit: $unit\n\n";
	my $new_pos = $here + $delta * $unit;
	$new_pos = $new_pos < $length ? $new_pos : $length - 10;
	# eval_iam("setpos $new_pos");
	my $cmd = "setpos $new_pos";
	$e->eci("setpos $new_pos");
	print "$cmd\n";
	restart_clock();
}
## post-recording functions

sub rec_cleanup {
	$debug2 and print "&rec_cleanup\n";
	$debug and print "I was recording!\n";
 	my @k = really_recording();
	disconnect_transport();
	my $recorded = 0;
 	for my $k (@k) {   
 		my ($n) = $outputs{file}{$k}[-1] =~ m/(\d+)/; 
 		my $test_wav = new_wav_name($k);
		$debug and print "new wave name for $k: ", new_wav_name($k), "\n";
 		my ($v) = ($test_wav =~ /_(\d+)\.wav$/); # #01 regex error, fixed
		$debug and print "n: $n\nv: $v\n";
		$debug and print "testing for $test_wav\n";
		if (-e $test_wav) {
			if (-s $test_wav > 44100) { # 0.5s x 16 bits x 44100/s
				find_wavs($n);
				$state_c{$n}->{active} = $state_c{$n}->{versions}->[-1]; # XXX
				update_version_button($n, $v);
			$recorded++;
			}
			else { unlink $test_wav }
		}
	}
	my $mixed = scalar ( grep{ $_ eq $project_name or $_ eq $mixname} @k );
	$debug and print "recorded: $recorded mixed: $mixed\n";
	if ( ($recorded -  $mixed) >= 1) {
			# i.e. there are first time recorded tracks
			$ui->update_master_version_button();
			$state_t{ $state_t{active} }->{rw} = "MON";
			setup_transport();
			connect_transport();
			$ui->refresh();
	}
		
} 
## effect functions
sub add_effect {
	
	$debug2 and print "&add_effect\n";
	
	my %p 			= %{shift()};
	my $n 			= $p{chain};
	my $code 			= $p{type};
	my $parent_id = $p{parent_id};  
	my $id		= $p{cop_id};   # initiates restore
	my $parameter		= $p{parameter}; 
	my $i = $effect_i{$code};

	return if $id eq $state_c{$n}->{vol} or
	          $id eq $state_c{$n}->{pan};   # skip these effects 
			   								# already created in add_track

	$id = cop_add(\%p); 
	my %pp = ( %p, cop_id => $id); # replace chainop id
	add_effect_gui(\%pp);
	apply_op($id) if eval_iam("cs-is-valid");

}

sub add_effect_gui {
		$debug2 and print "&add_effect_gui\n";
		@_ = discard_object(@_);
		my %p 			= %{shift()};
		my $n 			= $p{chain};
		my $code 			= $p{type};
		my $parent_id = $p{parent_id};  
		my $id		= $p{cop_id};   # initiates restore
		my $parameter		= $p{parameter}; 
		my $i = $effect_i{$code};

		$debug and print yaml_out(\%p);

		$debug and print "cop_id: $id, parent_id: $parent_id\n";
		# $id is determined by cop_add, which will return the
		# existing cop_id if supplied

		# check display format, may be 'scale' 'field' or 'hidden'
		
		my $display_type = $cops{$id}->{display}; # individual setting
		defined $display_type or $display_type = $effects[$i]->{display}; # template
		$debug and print "display type: $display_type\n";

		return if $display_type eq q(hidden);

		my $frame ;
		if ( ! $parent_id ){ # independent effect
			$frame = $widget_c{$n}->{parents}->Frame->pack(
				-side => 'left', 
				-anchor => 'nw',)
		} else {                 # controller
			$frame = $widget_c{$n}->{children}->Frame->pack(
				-side => 'top', 
				-anchor => 'nw')
		}

		no warnings;
		$widget_e{$id} = $frame; 
		# we need a separate frame so title can be long

		# here add menu items for Add Controller, and Remove

		my $parentage = $effects[ $effect_i{ $cops{$parent_id}->{type}} ]
			->{name};
		$parentage and $parentage .=  " - ";
		$debug and print "parentage: $parentage\n";
		my $eff = $frame->Menubutton(
			-text => $parentage. $effects[$i]->{name}, -tearoff => 0,);
		use warnings;

		$eff->AddItems([
			'command' => "Remove",
			-command => sub { remove_effect($id) }
		]);
		$eff->grid();
		my @labels;
		my @sliders;

		# make widgets

		for my $p (0..$effects[$i]->{count} - 1 ) {
		my @items;
		#$debug and print "p_first: $p_first, p_last: $p_last\n";
		for my $j ($e_bound{ctrl}{a}..$e_bound{ctrl}{z}) {   
			push @items, 				
				[ 'command' => $effects[$j]->{name},
					-command => sub { add_effect ({
							parent_id => $id,
							chain => $n,
							parameter  => $p,
							type => $effects[$j]->{code} } )  }
				];

		}
		push @labels, $frame->Menubutton(
				-text => $effects[$i]->{params}->[$p]->{name},
				-menuitems => [@items],
				-tearoff => 0,
		);
			$debug and print "parameter name: ",
				$effects[$i]->{params}->[$p]->{name},"\n";
			my $v =  # for argument vector 
			{	parent => \$frame,
				cop_id => $id, 
				p_num  => $p,
			};
			push @sliders,make_scale($v);
		}

		if (@sliders) {

			$sliders[0]->grid(@sliders[1..$#sliders]);
			 $labels[0]->grid(@labels[1..$#labels]);
		}
}

sub remove_effect {
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect\n";
	my $id = shift;
	my $n = $cops{$id}->{chain};
		
	$debug and print "ready to remove cop_id: $id\n";

	# if i belong to someone remove their ownership of me

	if ( my $parent = $cops{$id}->{belongs_to} ) {
	$debug and print "parent $parent owns list: ", join " ",
		@{ $cops{$parent}->{owns} }, "\n";

		@{ $cops{$parent}->{owns} }  =  grep{ $_ ne $id}
		@{ $cops{$parent}->{owns} } ; 
	$debug and print "parent $parent new owns list: ", join " ",
	}

	# recursively remove children
	$debug and print "children found: ", join "|",@{$cops{$id}->{owns}},"\n";
		
	# parameter controllers are not separate ops
	map{remove_effect($_)}@{ $cops{$id}->{owns} };

	
	# remove my own cop_id from the stack
	remove_op($id), $ui->remove_effect_gui($id) unless $cops{$id}->{belongs_to};

}
sub remove_effect_gui {
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect_gui\n";
	my $id = shift;
	my $n = $cops{$id}->{chain};
	$debug and print "id: $id, chain: $n\n";

	$state_c{$n}->{ops} = 
		[ grep{ $_ ne $id} @{ $state_c{ $cops{$id}->{chain} }->{ops} } ];
	$debug and print "i have widgets for these ids: ", join " ",keys %widget_e, "\n";
	$debug and print "preparing to destroy: $id\n";
	$widget_e{$id}->destroy();
	delete $widget_e{$id}; 

}

sub remove_op {

	my $id = shift;
	my $n = $cops{$id}->{chain};
	if ( $cops{$id}->{belongs_to}) { 
		return;
	}
	my $index; 
	$debug and print "ops list for chain $n: @{$state_c{$n}->{ops}}\n";
	$debug and print "operator id to remove: $id\n";
		for my $pos ( 0.. scalar @{ $state_c{$n}->{ops} } - 1  ) {
			($index = $pos), last if $state_c{$n}->{ops}->[$pos] eq $id;
		};
	$debug and print "ready to remove from chain $n, operator id $id, index $index\n";
	$debug and eval_iam ("cs");
	 eval_iam ("c-select $n");
	eval_iam ("cop-select ". ($state_c{$n}->{offset} + $index));
	eval_iam ("cop-remove");
	$debug and eval_iam ("cs");

	delete $cops{$id};
	delete $copp{$id};
}
sub cop_add {
	my %p 			= %{shift()};
	my $n 			= $p{chain};
	my $code		= $p{type};
	my $parent_id = $p{parent_id};  
	my $id		= $p{cop_id};   # causes restore behavior when present
	my $i       = $effect_i{$code};
	my $parameter	= $p{parameter};  # needed for parameter controllers
	$debug2 and print "&cop_add\n";

	return $id if $id; # do nothing if cop_id has been issued

	# make entry in %cops with chain, code, display-type, children

	$debug and print "Issuing a new cop_id for track $n: $cop_id\n";
	# from the cop_id, we may also need to know chain number and effect

	$cops{$cop_id} = {chain => $n, 
					  type => $code,
					  display => $effects[$i]->{display},
					  owns => [] };

 	cop_init ( { %p, cop_id => $cop_id} );

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship
		$debug and print "parent owns" , join " ",@{ $cops{$parent_id}->{owns}}, "\n";

		push @{ $cops{$parent_id}->{owns}}, $cop_id;
		$debug and print join " ", "my attributes:", (keys %{ $cops{$cop_id} }), "\n";
		$cops{$cop_id}->{belongs_to} = $parent_id;
		$debug and print join " ", "my attributes again:", (keys %{ $cops{$cop_id} }), "\n";
		$debug and print "parameter: $parameter\n";
		$copp{$cop_id}->[0] = $parameter + 1; # set fx-param to the parameter number.
 		# find position of parent and insert child immediately afterwards

 		my $end = scalar @{ $state_c{$n}->{ops} } - 1 ; 
 		for my $i (0..$end){
 			splice ( @{$state_c{$n}->{ops}}, $i+1, 0, $cop_id ), last
 				if $state_c{$n}->{ops}->[$i] eq $parent_id
 		}
	}
	else { push @{$state_c{$n}->{ops} }, $cop_id; }

	$cop_id++; # return value then increment
}

sub cop_init {
	local $debug = $debug3;
	$debug2 and print "&cop_init\n";
	my %p = %{shift()};
	my $id = $p{cop_id};
	my $parent_id = $p{parent_id};
	my $vals_ref  = $p{vals_ref};
	local $debug = $debug3;
	$debug and print "cop__id: $id\n";

	my @vals;
	if (ref $vals_ref) {
	# untested
		@vals = @{ $vals_ref };
		$debug and print ("values supplied\n");
		@{ $copp{$id} } = @vals;
		return;
	} 
	else { 
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$id}->{type} };
		
		# CONTROLLER
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		#for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		# XXX support controller-type operators
		
		for my $p (0..$effects[$i]->{count} - 1) {
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		@{ $copp{$id} } = @vals;
		$debug and print "copid: $id defaults: @vals \n";
	#}

	}
}
sub effect_update {
	my ($chain, $id, $param, $val) = @_;
	$debug2 and print "&effect_update\n";
	# return if rec_status($chain) eq "MUTE"; 
	return if ! defined $state_c{$chain}->{offset}; # MIX
	return unless transport_running();
 	$debug and print join " ", @_, "\n";	

	# update Ecasound's copy of the parameter

	$debug and print "valid: ", eval_iam("cs-is-valid"), "\n";
	$param++; # so the value at $p[0] is applied to parameter 1
	my $controller; 
	for my $op (0..scalar @{ $state_c{$chain}->{ops} } - 1) {
		${ $state_c{$chain}->{ops} } [$op] eq $id and $controller = $op 
	}
	$debug and print "cop_id $id corresponds to track: $chain, controller: $controller, offset: $state_c{$chain}->{offset}\n";
	eval_iam ("c-select $chain");
	eval_iam ("cop-select ". ($state_c{$chain}->{offset} + $controller));
	eval_iam ("copp-select $param");
	eval_iam ("copp-set $val");
}
sub find_op_offsets {

=comment
	Op offsets are needed to calculate the index to an effect (chain operator).
	If reverb is added and it is the first user-added effect, the offset will
	typically include an operator for routing (which will appear in the chain
	setup file) plus operators for volume and pan, which are provided for each
	track.

	find_op_offsets reads the output of the cs command to determine
	the number of chain operators from the setup file, then adds 
	two for the volume and pan operators, to give the index offset
	for the first user effect.

	Here is the relevant line from the 'cs' command output:

		Chain "1" [selected] "Channel copy"
			
	we will count the quotes, divide by two, and subtract one (for the chain id)
	to get offset. Then we add two for volume and pan. Finally, we will
	add 1, since perl arrays (used to represent chain operators) are indexed
	starting at 0, whereas ecasound indexes operators starting at 1.

	In this example, the first user effect will have an index of 4, which
	will also be the offset needed for our start-at-zero array. 
=cut


	$debug2 and print "&find_op_offsets\n";
	eval_iam('c-select-all');
		my @op_offsets = split "\n",eval_iam("cs");
		shift @op_offsets; # remove comment line
		$debug and print join "\n\n",@op_offsets; 
		for my $output (@op_offsets){
			my $chain_id;
			($chain_id) = $output =~ m/Chain "(\w*\d+)"/;
			print "chain_id: $chain_id\n";
			next if $chain_id =~ m/\D/; # skip id's containing non-digits
										# i.e. M1
			my $quotes = $output =~ tr/"//;
			$debug and print "offset: $quotes in $output\n"; 
			$state_c{$chain_id}->{offset} = ($quotes/2 - 1) + 1; 

		}
}
sub apply_ops {  # in addition to operators in .ecs file
	local $debug = $debug3;
	$debug2 and print "&apply_ops\n";
	for my $n (@all_chains) {
	$debug and print "chain: $n, offset: $state_c{$n}->{offset}\n";
 		next if rec_status($n) eq "MUTE" and $n != 1; #MIX
		next if ! defined $state_c{$n}->{offset}; # for MIX
 		next if ! $state_c{$n}->{offset} ;
		for my $id ( @{ $state_c{$n}->{ops} } ) {
		#	next if $cops{$id}->{belongs_to}; 
		apply_op($id);
		}
	}
}
sub apply_op {
	$debug2 and print "&apply_op\n";
	local $debug = $debug3;
	my $id = shift;
	$debug and print "id: $id\n";
	my $code = $cops{$id}->{type};
	$debug and print "chain: $cops{$id}->{chain} type: $cops{$id}->{type}, code: $code\n";
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ $copp{$id} };
	$debug and print "values: @vals\n";

	# we start to build iam command

	
	my $add = "cop-add "; 
	$add .= $code . join ",", @vals;

	# if my parent has a parent then we need to append the -kx  operator

	my $dad = $cops{$id}->{belongs_to};
	$add .= " -kx" if $cops{$dad}->{belongs_to};
	$debug and print "operator:  ", $add, "\n";

	eval_iam ("c-select $cops{$id}->{chain}") 
		unless $cops{$id}->{belongs_to}; # avoid reset
	eval_iam ($add);
	$debug and print "children found: ", join ",", "|",@{$cops{$id}->{owns}},"|\n";
	map{apply_op($_)} @{ $cops{$id}->{owns} };

}
## static effects data



# @ladspa_sorted # XXX

sub prepare_static_effects_data{
	local $debug = $debug3;
	$debug2 and print "&prepare_static_effects_data\n";

	my $effects_cache = join_path(&ecmd_dir, $effects_cache_file);

	# TODO re-read effects data if ladspa or user presets are
	# newer than cache

	if (-f $effects_cache and ! $opts{s}){  
		$debug and print "found effects cache: $effects_cache\n";
		assign_var($effects_cache, @effects_static_vars);
	} else {
		local $debug = 0;
		$debug and print "reading in effects data, please wait...\n";
		read_in_effects_data(); 
		get_ladspa_hints();
		integrate_ladspa_hints();
		sort_ladspa_effects();
		serialize (
			-file => $effects_cache, 
			-vars => \@effects_static_vars,
			-class => '::',
			-storable => 1 );
	}

}
sub extract_effects_data {
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
		$effects[$j]={};
		$effects[$j]->{number} = $no;
		$effects[$j]->{code} = $id;
		$effects[$j]->{name} = $name;
		$effects[$j]->{count} = scalar @p_names;
		$effects[$j]->{params} = [];
		$effects[$j]->{display} = qq(field);
		map{ push @{$effects[$j]->{params}}, {name => $_} } @p_names;
	}
}
sub sort_ladspa_effects {
	$debug2 and print "&sort_ladspa_effects\n";
#	print yaml_out(\%e_bound); 
	my $aa = $e_bound{ladspa}{a};
	my $zz = $e_bound{ladspa}{z};
#	print "start: $aa end $zz\n";
	map{push @ladspa_sorted, 0} ( 1 .. $aa ); # fills array slice [0..$aa-1]
	splice @ladspa_sorted, $aa, 0,
		 sort { $effects[$a]->{name} cmp $effects[$b]->{name} } ($aa .. $zz) ;
	$debug and print "sorted array length: ". scalar @ladspa_sorted, "\n";
}		
sub read_in_effects_data {

	$debug = 0;
	read_in_tkeca_effects_data();

	# read in other effects data
	
	my @ladspa = grep {! /^\w*$/ } split "\n", eval_iam("ladspa-register");
	
	# join the two lines of each entry
	my @lad = map { join " ", splice(@ladspa,0,2) } 1..@ladspa/2; 

	my @preset = grep {! /^\w*$/ } split "\n", eval_iam("preset-register");
	my @ctrl  = grep {! /^\w*$/ } split "\n", eval_iam("ctrl-register");

	# index boundaries we need to make effects list and menus

	$e_bound{ladspa}{a} = $e_bound{tkeca}{z} + 1;
	$e_bound{ladspa}{b} = $e_bound{tkeca}{z} + int(@lad/4);
	$e_bound{ladspa}{c} = $e_bound{tkeca}{z} + 2*int(@lad/4);
	$e_bound{ladspa}{d} = $e_bound{tkeca}{z} + 3*int(@lad/4);
	$e_bound{ladspa}{z} = $e_bound{tkeca}{z} + @lad;
	$e_bound{preset}{a} = $e_bound{ladspa}{z} + 1;
	$e_bound{preset}{b} = $e_bound{ladspa}{z} + int(@preset/2);
	$e_bound{preset}{z} = $e_bound{ladspa}{z} + @preset;
	$e_bound{ctrl}{a}   = $e_bound{preset}{z} + 1;
	$e_bound{ctrl}{z}   = $e_bound{preset}{z} + @ctrl;

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
		(\w.+?) # name, starting with word-char,  non-greedy
		\s+     # spaces
		-(el:\w+),? # ladspa_id maybe followed by comma
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
		$e_bound{ladspa}{a},
		$e_bound{ladspa}{z},
		$ladspa_re,
		q(','),
		@lad,
	);

	extract_effects_data(
		$e_bound{preset}{a},
		$e_bound{preset}{z},
		$preset_re,
		q(,),
		@preset,
	);
	extract_effects_data(
		$e_bound{ctrl}{a},
		$e_bound{ctrl}{z},
		$ctrl_re,
		q(,),
		@ctrl,
	);



	for my $i (0..$#effects){
		no warnings;
		 $effect_i{ $effects[$i]->{code} } = $i; 
		 use warnings;
		 $debug and print "i: $i code: $effects[$i]->{code} display: $effects[$i]->{display}\n";
	}

	$debug and print "\@effects\n======\n", yaml_out(\@effects); ; 
}
sub read_in_tkeca_effects_data {

# Based on GPL code in Tkeca

# controller (effect) data format
# code|name|number_of_parameters| ( Label|scale_start|scale_end|default|resolution ) x number_of_parameters

# I left the tcl code 'as is' in the following pasted section, using regexes 
# so future updates from him can be pasted in without editing.

# divide by lines, remove stuff outside quotes, 
# then make an anonymous array of the fields of each line

	my @effects_data = 	map { [split /\|/, $_ ]  }  
						map{ s/^.*?"//; s/"\s*$//; $_} 
						split "\n",$tkeca_effects_data; 
	
	$e_bound{tkeca}{a}  = 1;
	$e_bound{tkeca}{z}  = scalar @effects_data;  

	for my $i (1..@effects_data){
		my @row = @{ shift @effects_data };
		@{$effects[$i]}{ qw(code name count) } = splice @row, 0, 3;

		# default display format

		$effects[$i]->{display} = qq(scale);

	# maps effect code (i.e. epp) to an index in array holding static effects data
	#print "effects code: $i stands for ", $effects[$i]->{code}, "\n";
	#print "count: $effects[$i]->{count}\n";

			for (1..$effects[$i]->{count}){
				my %p;
				#print join " / ",splice (@row, 0,5), "\n";
				@p{ qw(name begin end default resolution) }  =  splice @row, 0, 5;
				# print "\%p\n======\n", yaml_out(\%p);
				push @{$effects[$i]->{params}}, \%p;

			}
	}

}
sub get_ladspa_hints{
	$debug2 and print "&get_ladspa_hints\n";
	my @dirs =  split ':', $ENV{LADSPA_PATH};
	my $data = '';
	for my $dir (@dirs) {
		opendir DIR, $dir or carp qq(can't open LADSPA dir "$dir" for read: $!\n);
		my @plugins = grep{ /\.so$/ } readdir DIR;
		$data .= join "", map { `analyseplugin $_` } @plugins;
		closedir DIR;
	}
	# print $data; exit;
	my @plugin_stanzas = split "\n\n\n", $data;
	# print scalar @plugin_stanzas; exit;
	# print $data;

	# print "@plugins"; exit;
	# | perl -ne 'chomp; s/$ENV{LADSPA_PATH}//; system qq(analyseplugin $_)'
	my $ladspa_sample_rate = 44100; # for sample-rate dependent effect
	use Data::Dumper;

	my $pluginre = qr/
	Plugin\ Name: \s+ "([^"]+)" \s+
	Plugin\ Label:\s+ "([^"]+)" \s+
	[^\x00]+(?=Ports) 		# swallow maximum up to Ports
	Ports: \s+ ([^\x00]+) 	# swallow all
	/x;

	my $paramre = qr/
	"([^"]+)"   #  name inside quotes
	\s+
	(.+)        # rest
	/x;



	for my $stanza (@plugin_stanzas) {

		$stanza =~ /$pluginre/ or carp "*** couldn't match plugin stanza $stanza ***";

		my ($plugin_name, $plugin_label, $ports) = ($1, $2, $3);
		#print "$1\n$2\n$3"; exit;

		 my @lines = split "\n",$ports;
	#	print join "\n",@lines; exit;
		my @params;  # data

		my @names;
		for my $p (@lines) {
			next if $p =~ /^\s*$/;
			$p =~ /$paramre/;
			my ($name, $rest) = ($1, $2);
			my ($dir, $type, $range, $default, $hint) = split /\s*,\s*/ , $rest, 5;
			#print join "|",$dir, $type, $range, $default, $hint;
			next if $type eq q(audio);
			my %p;
			$p{name} = $name;
			$p{dir} = $dir;
			$p{hint} = $hint;
			my ($beg, $end, $default_val, $resolution) = range($name, $range, $default, $hint);
			$p{begin} = $beg;
			$p{end} = $end;
			$p{default} = $default_val;
			$p{resolution} = $resolution;
			push @params, { %p };
		}

		$plugin_label = "el:" . $plugin_label;
		$effects_ladspa {$plugin_label}->{params} = [ @params ];
		$effects_ladspa {$plugin_label}->{count} = scalar @params;
		$effects_ladspa {$plugin_label}->{display} = 'scale';
	}

	$debug and print yaml_out(\%effects_ladspa); 
}
no warnings;
sub range {
	my ($name, $range, $default, $hint) = @_; 
	my $multiplier = 1;;
	$multiplier = $ladspa_sample_rate if $range =~ s/\*srate//g;
	my ($beg, $end) = split /\s+to\s+/, $range;
	# if end is '...' set to $default + 10dB or $default * 10
	$default =~ s/default\s+//;
	$end =~ /\.{3}/ and $end = (
		$default == 0 ? 10  # '0' is probably 0db, so 0+10db
					  : $default * 10
		);
#	print "1 beg: $beg  end: $end\n";
	$beg = $beg * $multiplier;
	$end = $end * $multiplier;
#	print "2 beg: $beg  end: $end\n";

	my $resolution = ($end - $beg) / 100;
	if    ($hint =~ /integer/ ) { $resolution = 1; }
	elsif ($hint =~ /logarithmic/ ) {
		$beg = 0.0001 * $multiplier if ! $beg;
		$beg = round ( log $beg );
		$end = round ( log $end );
		$resolution = ($end - $beg) / 100;
		$default = round (log $default);
	}
	
	$resolution = d2( $resolution + 0.002) if $resolution < 1  and $resolution > 0.01;
	$resolution = dn ( $resolution, 3 ) if $resolution < 0.01;
	$resolution = int ($resolution + 0.1) if $resolution > 1 ;
	
	#print "3 beg: $beg  end: $end\n";
	($beg, $end, $default, $resolution)

}
use warnings;
sub integrate_ladspa_hints {
	map{ 
		my $i = $effect_i{$_};
		print ("$_ not found\n"), next unless $i;
		$effects[$i]->{params} = $effects_ladspa{$_}->{params};
		$effects[$i]->{display} = $effects_ladspa{$_}->{display};
	} keys %effects_ladspa;

my %L;
my %M;

map { $L{$_}++ } keys %effects_ladspa;
map { $M{$_}++ } grep {/el:/} keys %effect_i;

for my $k (keys %L) {
	$M{$k} or print "$k not found in ecasound listing\n";
}
for my $k (keys %M) {
	$L{$k} or print "$k not found in ladspa listing\n";
}


$debug and print join "\n", sort keys %effects_ladspa;
$debug and print '-' x 60, "\n";
$debug and print join "\n", grep {/el:/} sort keys %effect_i;

#print yaml_out \@effects; exit;

}
sub d2 {
	my $n = shift;
	sprintf("%.2f", $n)
}
sub dn {
	my ($n, $places) = @_;
	sprintf("%." . $places . "f", $n);
}
sub round {
	my $n = shift;
	return 0 if $n == 0;
	$n = int $n if $n > 10;
	$n = d2($n) if $n < 10;
	$n;
}
	

=comment

 ls $LADSPA_PATH | perl -ne 'chomp; s/$ENV{LADSPA_PATH}//; system qq(analyseplugin $_)'

my $ds = q(
Plugin Name: "LS Filter"
Plugin Label: "lsFilter"
Plugin Unique ID: 1908
Maker: "Steve Harris <steve@plugin.org.uk>"
Copyright: "GPL"
Must Run Real-Time: No
Has activate() Function: Yes
Has deativate() Function: No
Has run_adding() Function: Yes
Environment: Normal or Hard Real-Time
Ports:  "Filter type (0=LP, 1=BP, 2=HP)" input, control, 0 to 2, default 0, integer
        "Cutoff frequency (Hz)" input, control, 0.002*srate to 0.5*srate, default 0.0316228*srate, logarithmic
        "Resonance" input, control, 0 to 1, default 0
        "Input" input, audio
        "Output" output, audio
);
=cut
## persistent state support

sub save_state {
	$debug2 and print "&save_state\n";
	my $file = shift;
	# restore muted volume levels
	#
	my %muted;
	
	map{ $copp{ $state_c{$_}{vol} }->[0] = $old_vol{$_} ;
		 $muted{$_}++;
	#	 $ui->paint_button($widget_c{$_}{mute}, q(brown) );
		} grep { $old_vol{$_} } @all_chains;

 # old vol level has been stored, thus is muted
	$file = $file ? $file : $state_store_file;
	$file = join_path(&project_dir, $file);
		$debug and 1;
	print "filename: $file\n";

	serialize(
		-file => $file, 
		-vars => \@persistent_vars,
		-class => '::',
		-storable => 1,
		);

# store alsa settings

	my $result2 = system "alsactl -f $file.alsa store";
	$debug and print "alsactl store result: ", $result2 >>8, "\n";

	# now remute
	
	map{ $copp{ $state_c{$_}{vol} }->[0] = 0} 
	grep { $muted{$_}} 
	@all_chains;

}
sub assign_var {
	my ($source, @vars) = @_;
	assign_vars(
				-source => $source,
				-vars   => \@vars,
				-class => '::');
}
sub retrieve_state {
	$debug2 and print "&retrieve_state\n";
	my $file = shift;
	$file = $file ? $file : $state_store_file;
	$file = join_path(project_dir(), $file);
	my $yamlfile = $file;
	$yamlfile .= ".yml" unless $yamlfile =~ /yml$/;
	$file = $yamlfile if -f $yamlfile;
	! -f $file and carp("file not found: $file\n"), return;
	$debug and print "using file: $file";
	assign_var( $file, @persistent_vars );
	#print status_vars; exit;

=comment
	$debug and print ref $ref->{marks};
	 @marks = @{ $ref->{marks} };
	 print "array size ", scalar @marks;
=cut

	my $toggle_jack = $widget_o[$#widget_o];
	convert_to_jack if $jack_on;
	$ui->paint_button($toggle_jack, q(lightblue)) if $jack_on;
	$ui->refresh_oids();

	# restore mixer settings

	my $result = system "sudo alsactl -f $file.alsa restore";
	$debug and print "alsactl restore result: " , $result >> 8 , "\n";

	# restore time marker labels

	$ui->restore_time_marker_labels();
=comment
	
	map{ $time_marks[$_]->configure( 
		-text => colonize($marks[$_]),
		-background => $old_bg,
	)} 
	grep{ $marks[$_] }1..$#time_marks;
=cut

	# restore take and track guis
	
	for my $t (@takes) { 
		next if $t == 1; 
		$ui->take_gui;
	}; #
	my $did_apply = 0;
	$last_version = 0; 
	for my $n (@all_chains) { 
		$debug and print "restoring track: $n\n";
		restore_track($n) ;
		for my $id (@{$state_c{$n}->{ops}}){
			$did_apply++ 
				unless $id eq $state_c{$n}->{vol}
					or $id eq $state_c{$n}->{pan};

			
			add_effect({
						chain => $cops{$id}->{chain},
						type => $cops{$id}->{type},
						cop_id => $id,
						parent_id => $cops{$id}->{belongs_to},
						});

		# TODO if parent has a parent, i am a parameter controller controlling
		# a parameter controller, and therefore need the -kx switch
		}
	}
	$did_apply and $ui->manifest(); # $ew->deiconify();

}


sub save_effects {
	$debug2 and print "&save_effects\n";
	my $file = shift;
	
	# restore muted volume levels
	#
	my %muted;
	
	map  {$copp{ $state_c{$_}{vol} }->[0] = $old_vol{$_} ;
		  $ui->paint_button($widget_c{$_}{mute}, $old_bg ) }
	grep { $old_vol{$_} }  # old vol level stored and muted
	@all_chains;

	# we need the ops list for each track
	#
	# i dont see why, do we overwrite the effects section
	# in one of the init routines?
	# I will follow for now 12/6/07
	
	%state_c_ops = ();
	map{ 	$state_c_ops{$_} = $state_c{$_}->{ops} } @all_chains;

	# map {remove_op} @{ $state_c{$_}->{ops} }

	store_vars(
		-file => $file, 
		-vars => \@effects_dynamic_vars,
		-class => '::');

}

=comment
sub r {
	retrieve_effects(shift);
}

sub r5 { r("eff5") };
=cut
sub retrieve_effects {
	$debug2 and print "&retrieve_effects\n";
	my $file = shift;
	my %current_cops = %cops; # XXX why bother
	my %current_copp = %copp; # similar name!!!!
	assign_vars($file, @effects_dynamic_vars);
	my %old_copp = %copp;  # XXX why bother
	my %old_cops = %cops; 
	%cops = %current_cops;
	%copp = %current_copp; ## similar name!!


	print "\%state_c_ops\n ", yaml_out( \%state_c_ops), "\n\n";
	print "\%old_cops\n ", yaml_out( \%old_cops), "\n\n";
	print "\%old_copp\n ", yaml_out( \%old_copp), "\n\n";
#	return;

	restore_time_marker_labels();

	# remove effects except vol and pan, in which case, update vals

	map{ 	
	
		$debug and print "found chain $_: ", join " ",
		@{ $state_c{$_}->{ops} }, "\n";

		my $n = $_;
		map {	my $id = $_; 
				$debug and print "checking chain $n, id $id: ";
				
				if (	$state_c{$n}->{vol} eq $id or
						$state_c{$n}->{pan} eq $id  ){

					# do nothing
				$debug and print "is vol/pan\n";

				}
				else {
					
					$debug and print "is something else\n";
					remove_effect($id) ;
					remove_op($id)
			}

		} @{ $state_c{$_}->{ops} }
	} @all_chains;
			
	return;

	# restore ops list
	
	map{ $state_c{$_}->{ops} = $state_c_ops{$_} } @all_chains;

	# restore ops->chain mapping
	
	%cops = %old_copp;

	# add the correct copp entry for each id except vol/pan
	map{ my $n = $_;
			map {	my $id = $_; 
				if (	$state_c{$n}->{vol} eq $id or
						$state_c{$n}->{pan} eq $id  ){

					$copp{$id}->[0] = $old_copp{$id}->[0];
				}
				else {  $copp{$id} = $old_copp{$id} }

			} @{ $state_c{$_}->{ops} }
		} @all_chains;

	# apply ops
	
	my $did_apply = 0;

	for my $n (@all_chains) { 
		for my $id (@{$state_c{$n}->{ops}}){
			$did_apply++ 
				unless $id eq $state_c{$n}->{vol}
					or $id eq $state_c{$n}->{pan};

			
			add_effect({  
						chain => $cops{$id}->{chain},
						type => $cops{$id}->{type},
						cop_id => $id,
						parent_id => $cops{$id}->{belongs_to},
						});

		# TODO if parent has a parent, i am a parameter controller controlling
		# a parameter controller, and therefore need the -kx switch
		}
	}
	$did_apply and print "########## applied\n\n";
	
	# $ew->deiconify or $ew->iconify;

}

	

### end
