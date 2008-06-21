use Carp;
sub new { my $class = shift; return bless { @_ }, $class; }
sub loop {
	local $debug = 0;
	::Text::OuterShell::create_help_subs();
	package ::;
	load_project(name => $project_name, create => $opts{c}) if $project_name;
#	my $term = new Term::ReadLine 'Ecmd';
#	my $prompt = "Enter command: ";
#	$OUT = $term->OUT || \*STDOUT;
	$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";


 #	use ::Text::OuterShell; # not needed, class is present in this file
	  my $shell = ::Text::OuterShell->new;

          $shell->cmdloop;
}

	
sub command_process {

package ::;
		my ($user_input) = shift;
		# my ($user_input) = $term->readline($prompt) ; # old way
		return if $user_input =~ /^\s*$/;
		# $term->addhistory($user_input) ; # this is done # for us too
		my @user_input = split /\s*;\s*/, $user_input;
		map {
			my $user_input = $_;
			my ($cmd, $predicate) = ($user_input =~ /([!\S]+)(.*)/);
			$debug and print "cmd: $cmd \npredicate: $predicate\n";
			if ($cmd eq 'eval') {
				$debug and print "Evaluating perl code\n";
				print eval $predicate;
				print "\n";
				$@ and print "Perl command failed: $@\n";
			} elsif ($cmd eq '!') {
				$debug and print "Evaluating shell commands!\n";
				system $predicate;
			} elsif ($tn{$cmd}) { 
				$debug and print qq(Selecting track "$cmd"\n);
				$this_track = $tn{$cmd};
				$predicate !~ /^\s*$/ and $parser->read($predicate);
			} elsif ($cmd =~ /^\d+$/ and $ti[$cmd]) { 
				$debug and print qq(Selecting track ), $ti[$cmd]->name, $/;
				$this_track = $ti[$cmd];
				$predicate !~ /^\s*$/ and $parser->read($predicate);
			} elsif ($iam_cmd{$cmd}){
				$debug and print "Found Iam command\n";
				print ::eval_iam($user_input), $/ ;
			} else {
				$debug and print "Passing to parser\n";
				$parser->command($user_input) 
			}

		} @user_input;
}
package ::Text;
sub show_tracks {
	no warnings;
	my @tracks = @_;
	map { 	push @::format_fields,  
			$_->n,
			$_->name,
			$_->rw,
			$_->rec_status,
			$_->ch_r || 1,
			$_->current_version || 'none',
			(join " ", @{$_->versions}),

		} grep{ ! $_-> hide} @tracks;
		
	write; # using format at end of file UI.pm
	$- = 0; # $FORMAT_LINES_LEFT # force header on next output
	1;
	use warnings;
	no warnings q(uninitialized);
}

format STDOUT_TOP =
Chain  Track name     Setting  Status  Input  Active  Versions   
==========================================================================
.
format STDOUT =
@>>    @<<<<<<<<<<<<   @<<<     @<<<   @>>     @>>>   @<<<<<<<<<<<<<<<<<<< ~~
splice @::format_fields, 0, 7
.
	
# prepare help and autocomplete

package ::Text::OuterShell;
use base qw(Term::Shell); 
#create_help_subs();
sub catch_run { # 
  my ($o, $cmd, @args) = @_;
  my $original_command_line = join " ", $cmd, @args;
  #print "foudn $0 $original_command_line\n";
  ::Text::command_process( $original_command_line );
}
sub catch_help {
  my ($o, $cmd, @args) = @_;
  local $debug = 0;
  $debug and print "cmd: $cmd\n";
  #my $main_name = 
  #
  print grep{ $_ eq $cmd } join " ", 
  my $main_name;
  CMD: for my $k ( keys %commands ){
  	for my $alias ( $k, split " ",$commands{$k}{short} ){
		if ($cmd eq $alias){
			$main_name = $k;
			last CMD;
		}
	}
  }
  $debug and print "main_name: $main_name\n";
			
	my $txt = $o->help($main_name, @_);
	if ($o->{command}{help}{found}) {
	    $o->page("$txt\n")
	}
}


#my $print "catched help @_"}
sub prompt_str { 'Enter command: ' }
sub run_help {
    my $o = shift;
    my $cmd = shift;
    if ($cmd) {
	my $txt = $o->help($cmd, @_);
	if ($o->{command}{help}{found}) {
	    $o->page("$txt\n")
	}
	else {
	    my @c = sort $o->possible_actions($cmd, 'help');
	    if (@c and $o->{API}{match_uniq}) {
		local $" = "\n\t";
		print <<END;
Ambiguous help topic '$cmd': possible help topics:
	@c
END
	    }
	    else {
		print <<END;
Unknown help topic '$cmd'; type 'help' for a list of help topics.
END
	    }
	}
    }
    else {
	print "Type 'help command' for more detailed help on a command.\n";
# 	my (%cmds, %docs);
# 	my %done;
# 	my %handlers;
# 	for my $h (keys %{$o->{handlers}}) {
# 	    next unless length($h);
# 	    next unless grep{defined$o->{handlers}{$h}{$_}} qw(run smry help);
# 	    my $dest = exists $o->{handlers}{$h}{run} ? \%cmds : \%docs;
# 	    my $smry = do { my $x = $o->summary($h); $x ? $x : "" };
# 	    my $help = exists $o->{handlers}{$h}{help}
# 		? (exists $o->{handlers}{$h}{smry}
# 		    ? " "
# 		    : "")
# 		: "";
# 	    $dest->{"    $h"} = "$smry$help";
# 	}
# 	my @t;
# 	push @t, "  Commands:\n" if %cmds;
# 	push @t, scalar $o->format_pairs(
# 	    [sort keys %cmds], [map {$cmds{$_}} sort keys %cmds], ' - ', 1
# 	);
# 	push @t, "  Extra Help Topics: (not commands)\n" if %docs;
# 	push @t, scalar $o->format_pairs(
# 	    [sort keys %docs], [map {$docs{$_}} sort keys %docs], ' - ', 1
# 	);
my $help_screen = <<HELP;
Ecasound-IAM commands:

    start, t - Processing is started 
    stop, s - Stops processing
    rewind <time-in-seconds>, rw <time-in-seconds> - Rewind
    forward <time-in-seconds>, fw <time-in-seconds> - Forward
    setpos <time-in-seconds> - Sets the current position to <time-in-seconds> 
    engine-launch - Initialize and start engine
    engine-status - Engine status
    cs-status, st - Chainsetup status
    c-status, cs - Chain status
    cop-status, es - Chain operator status
    ctrl-status - Controller status
    aio-status, fs - Audio input/output status

Ecmd commands (additional help available by typing 'help <command>')

  -- Unsupported in text mode  --

    additional effects (chain operators)
    marks
    
  -- General --

    help          - prints this screen, or help on 'command'
    exit          - exits the program

  -- Project -- 

    load_project, load         -  load an existing project 
    create_project, create     -  create a new project directory tree 
    get_state, get, retrieve <state_file>    
                               -  retrieve project settings 
    save_state, keep, k, save  -  save project settings to disk, optional name    
  -- Setup --

    setup, arm              -  generate and connect chain setup    
    show_setup, show        -  show setup    

  -- Track -- 

    show_track, sh          -  show track setup 
    add_track, add          -  create a new track 

  - version

    set_version, version, n -  select current track version    

  - rw_status

    rec                     -  set track to REC  
    mon                     -  set track to MON
    off, z                  -  set track OFF (omit from setup)

  - vol/pan 

    pan, p               -  get/set pan position
    pan_back, pb         -  restore pan    
    pan_center, pc       -  set pan center    
    pan_left, pl         -  pan track fully left    
    pan_right, pr        -  pan track fully right    
    unity, cc            -  unity volume    
    vol, v               -  get/set track volume    
    mute, c, cut          -  mute volume 

  - channel assignments

    r,record_channel        -   set track input channel number    
    m, monitor_channel      -  set current track output channel 

  - effects 

    add_effect,    fxa, afx    - add an effect to the current track
    modify_effect, fxm, mfx    - set an effect parameter to a new value
    delta_effect,  fxd, dfx    - increment/decrement effect parameter
    remove_effect, fxr, rfx    - remove an effect

  -- Group control --

    group_rec, grec, R      -  group REC mode 
    group_mon, gmon, M      -  group MON mode 
    group_off, goff, MM     -  group OFF mode 
    group_version, gn, gver, gv -  select group version 

  -- Mixdown --

    mixdown, mxd               -  enable mixdown 
    mixoff, norm, normal, mxo  -  mix off 
    mixplay, mxp               -  play mix 

HELP
	$o->page($help_screen);
    }
}


sub create_help_subs {
	$debug2 and print "create_help_subs\n";
	local $debug = 0;
	%commands = %{ ::yaml_in( $::commands_yml) };

	$debug and print ::yaml_out \%commands;
	
	#map{ print $_, $/} grep{ $_ !~ /mark/ and $_ !~ /effect/ } keys %commands;
	
	map{ 
			my $run_code = qq!sub run_$_ { splice \@_,1,0,  q($_); catch_run( \@_) }; !;
			$debug and print "evalcode: $run_code\n";
			eval $run_code;
			$debug and $@ and print "create_sub eval error: $@\n";
			my $help_code = qq!sub help_$_ { q($commands{$_}{what}) };!;
			$debug and print "evalcode: $help_code\n";
			eval $help_code;
			$debug and $@ and print "create_sub eval error: $@\n";
			my $smry_text = 
			$commands{$_}{smry} ? $commands{$_}{smry} : $commands{$_}{what};
			$smry_text .= qq! ($commands{$_}{short}) ! 
					if $commands{$_}{short};

			my $smry_code = qq!sub smry_$_ { q( $smry_text ) }; !; 
			$debug and print "evalcode: $smry_code\n";
			eval $smry_code;
			$debug and $@ and print "create_sub eval error: $@\n";

			my $alias_code = qq!sub alias_$_ { qw($commands{$_}{short}) }; !;
			$debug and print "evalcode: $alias_code\n";
			#eval $alias_code;# noisy in docs
			$debug and $@ and print "create_sub eval error: $@\n";

		}

	grep{ $_ !~ /mark/ and $_ !~ /effect/ } keys %commands;

}
	
