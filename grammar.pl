### COMMAND LINE PARSER 

print "Reading grammar\n";
$::RD_AUTOSTUB = 1;
$::RD_HINT = 1;

# rec command changes active take

$grammar = q(

command: new | load | add | setup 
command: show | fx
command: mon | rec | mute | r | m
command: vol | pan 
command: renew | exit
command: keep | set
command: version 

show: 'show' { 	map { push @::format_fields,  
							$_,
							$::state_c{$_}->{active},
							$::state_c{$_}->{file},
							$::state_c{$_}->{rw},
							&::rec_status($_),
							$::state_c{$_}->{ch_r},
							$::state_c{$_}->{ch_m},
					} sort keys %::state_c;
				write;
				1;
}

load: 'load' name {
	$::session = $item{name};
	&::load_session unless $::session_name eq $item{name};
	1;
}
new: 'new' name {
	$::session = $item{name};
	&::new_session;
	1;
}


name: /\w+/

wav: name

setup: 'setup' { &::setup_transport; &::connect_transport; 1}

renew: 'renew' {&::new_engine; 1}

mix: 'mix' {1}

norm: 'norm' {1}

exit: 'exit' { &::save_state($::statestore); exit; }


channel: r | m

r: 'r' dd  { $::state_c{$::chain{$::select_track}}->{ch_r} = $item{dd} }
m: 'm' dd  { $::state_c{$::chain{$::select_track}}->{ch_m} = $item{dd} }


rec: 'rec' wav(s?) { 
	map{$::state_c{$::chain{$_}}->{rw} = q(rec)} @{$item{wav}} 
}
mon: 'mon' wav(s?) { 
	map{$::state_c{$::chain{$_}}->{rw} = q(mon)} @{$item{wav}} 
}
mute: 'mute' wav(s?) { 
	map{$::state_c{$::chain{$_}}->{rw} = q(mute)} @{$item{wav}}  
}

mon: 'mon' {$::state_c{$::chain{$::select_track}} = q(mon); }

mute: 'mute' {$::state_c{$::chain{$::select_track}} = q(mute); }

rec: 'rec' {$::state_c{$::chain{$::select_track}} = q(rec); }

last: ('last' | '$' ) 

dd: /\d+/

add: 'add' wav channel(s?) { 
	if ($::track_names{$item{wav}} ){
		print "Track name already in use.\n";
	} else {
		&::add_track($item{wav}) ;
		my %ch = ( @{$item{channel}} );	
		$ch{r} and $::state_c{$::i}->{ch_r} = $::ch{r};
		$ch{m} and $::state_c{$::i}->{ch_m} = $::ch{m};
		
	}
	1;
}

);

# extract top-level commands from grammar

@ecmd_commands = 
	grep{$_} map{&remove_spaces($_)}        # remove null items
	map{split /\s*\|\s*|command:\s*/, $_}  # split apart commands
	grep {/command:/} split "\n", $grammar; # only commands

@ecmd_commands{@ecmd_commands} = 1..@ecmd_commands;
#print join $/, keys %ecmd_commands; 
