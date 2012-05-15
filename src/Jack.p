# ------- Jack port connect routines -------
package ::;
use Modern::Perl;
use File::Slurp;
no warnings 'uninitialized';

# general functions

sub poll_jack { 
		jack_update(); # first time
		# then repeat
		$engine->{events}->{poll_jack} = AE::timer(0,5,\&jack_update) 
}

sub jack_update {
	logsub("&jack_update");
	# cache current JACK status
	#
	# skip if Ecasound is busy
	return if engine_running();
	if( $jack->{jackd_running} = process_is_running('jackd') ){
		#parse_ports_list();
		$jack->{use_jacks} 
			?  jacks_get_port_latency() 
			:  parse_port_latency();

		# we know that JACK capture latency is 1 period
		$jack->{period} = $jack->{clients}->{system}->{capture}->{max};

	} else { $jack->{clients} = {} }
}

sub jack_client_array {

	# returns array of ports if client and direction exist
	
	my ($name, $direction)  = @_;
	$jack->{clients}->{$name}{$direction} // []
}

sub jacks_get_port_latency {
	logsub('&jacks_get_port_latency');
	delete $jack->{clients};

my $jc;

$jc = jacks::JsClient->new("watch latency", undef, $jacks::JackNullOption, 0);

my $plist =  $jc->getPortNames(".");

for (my $i = 0; $i < $plist->length(); $i++) {
    my $pname = $plist->get($i);
	my ($client_name,$port_name) = $pname =~ /
		(.+?)	# anything, non-greedy 
		:		# a colon
		([^:]+$)# non-colon stuff to end
		/x;

	say qq(client: $client_name, port: $port_name);

    my $port = $jc->getPort($pname);

    my $platency = $port->getLatencyRange($jacks::JackPlaybackLatency);
    my $pmin = $platency->min();
    my $pmax = $platency->max();
    logit(__LINE__,'::Jack','debug',"$pname: playback Latency [ $pmin $pmax ]");
	$jack->{clients}->{$client_name}->{$port_name}->{latency}->{playback}->{min} 
		= $pmin;
	$jack->{clients}->{$client_name}->{$port_name}->{latency}->{playback}->{max} 
		= $pmax;

    my $clatency = $port->getLatencyRange($jacks::JackCaptureLatency);
    my $cmin = $clatency->min();
    my $cmax = $clatency->max();
    logit(__LINE__,'::Jack','debug',"$pname: capture Latency [ $cmin $cmax ]");
	$jack->{clients}->{$client_name}->{$port_name}->{latency}->{capture}->{min} 
		= $cmin;
	$jack->{clients}->{$client_name}->{$port_name}->{latency}->{capture}->{max} 
		= $cmax;
}


}
sub parse_port_latency {
	
	# default to use output of jack_lsp -l
	
	my $j = shift || qx(jack_lsp -l 2> /dev/null); 
	logit(__LINE__,'::Jack','debug', "latency input $j");
	
	state $port_latency_re = qr(


							# ecasound:in_1
							
							(?<client>[^:]+)  # non-colon
							:                 # colon
							(?<port>\S+?)     # non-space
							\s+

							# port latency = 2048 frames #  DEPRECATED

							\Qport latency = \E    
							\d+ # don't capture
							\Q frames\E
							\s+

							# port playback latency = [ 0 2048 ] frames

							\Qport playback latency = [ \E
							(?<playback_min>\d+)
							\s+
							(?<playback_max>\d+)
							\Q ] frames\E
							\s+

							# port capture latency = [ 0 2048 ] frames

							\Qport capture latency = [ \E
							(?<capture_min>\d+)
							\s+
							(?<capture_max>\d+)
							\Q ] frames\E

						)x;

	# convert to single lines

	$j =~ s/\n\s+/ /sg;
	
	my @ports = split "\n",$j;
	map
	{

		/$port_latency_re/;

		#logit(__LINE__,'::Jack','debug', Dumper %+);
		logit(__LINE__,'::Jack','debug', "client: ",$+{client});
		logit(__LINE__,'::Jack','debug', "port: ",$+{port});
		logit(__LINE__,'::Jack','debug', "capture min: ", $+{capture_min});
		logit(__LINE__,'::Jack','debug', "capture max: ",$+{capture_max});
		logit(__LINE__,'::Jack','debug', "playback min: ",$+{playback_min});
		logit(__LINE__,'::Jack','debug', "playback max: ",$+{playback_max});
		
		$jack->{clients}->{$+{client}}->{$+{port}}->{latency}->{capture}->{min}
			= $+{capture_min};
		$jack->{clients}->{$+{client}}->{$+{port}}->{latency}->{capture}->{max}
			= $+{capture_max};
		$jack->{clients}->{$+{client}}->{$+{port}}->{latency}->{playback}->{min}
			= $+{playback_min};
		$jack->{clients}->{$+{client}}->{$+{port}}->{latency}->{playback}->{max}
			= $+{playback_max};
		
	} @ports;
	
}


sub parse_ports_list {

	# default to output of jack_lsp -p
	
	logsub("&parse_ports_list");
	my $j = shift || qx(jack_lsp -p 2> /dev/null); 
	logit(__LINE__,'::Jack','debug', "input: $j");

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,
	#fluidsynth:left properties: output,
	#fluidsynth:right properties: output,

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @port_aliases = /
			\s* 			# zero or more spaces
			([^:]+:[^:]+?) # non-colon string, colon, non-greedy non-colon string
			(?=[-+.\w]+:|\s+$) # zero-width port name or spaces to end-of-string
		/gx; 
		map { 
				s/ $//; # remove trailing space

				# make entries for 'system' and 'system:capture_1'
				push @{ $jack->{clients}->{$_}->{$direction} }, $_;
				my ($client, $port) = /(.+?):(.+)/;
				push @{ $jack->{clients}->{$client}->{$direction} }, $_; 

		 } @port_aliases;

	} 
	grep{ ! /^jack:/i } # skip spurious jackd diagnostic messages
	split "\n",$j;
}

# connect jack ports via jack.plumbing or jack_connect

sub jack_plumbing_conf {
	join_path( $ENV{HOME} , '.jack.plumbing' )
}

{ 
  my $fh;
  my $plumbing_tag = q(BEGIN NAMA CONNECTIONS LIST);
  my $plumbing_header = qq(;### $plumbing_tag
;## The following lines are automatically generated.
;## DO NOT place any connection data below this line!!
;
); 
sub initialize_jack_plumbing_conf {  # remove nama lines

		return unless -f -r jack_plumbing_conf();

		my $user_plumbing = read_file(jack_plumbing_conf());

		# keep user data, deleting below tag
		$user_plumbing =~ s/;[# ]*$plumbing_tag.*//gs;

		write_file(jack_plumbing_conf(), $user_plumbing);
}

my $jack_plumbing_code = sub 
	{
		my ($port1, $port2) = @_;
		my $debug++;
		my $config_line = qq{(connect $port1 $port2)};
		say $fh $config_line; # $fh in lexical scope
		logit(__LINE__,'::Jack','debug', $config_line);
	};
my $jack_connect_code = sub
	{
		my ($port1, $port2) = @_;
		my $debug++;
		my $cmd = qq(jack_connect $port1 $port2);
		logit(__LINE__,'::Jack','debug', $cmd);
		system $cmd;
	};
sub connect_jack_ports_list {

	my @source_tracks = 
		grep{ 	$_->source_type eq 'jack_ports_list' and
	  	  		$_->rec_status  eq 'REC' 
			} ::ChainSetup::engine_tracks();

	my @send_tracks = 
		grep{ $_->send_type eq 'jack_ports_list' } ::ChainSetup::engine_tracks();

	# we need JACK
	return if ! $jack->{jackd_running};

	# We need tracks to configure
	return if ! @source_tracks and ! @send_tracks;

	sleeper(0.3); # extra time for ecasound engine to register JACK ports

	if( $config->{use_jack_plumbing} )
	{

		# write config file
		initialize_jack_plumbing_conf();
		open $fh, ">>", jack_plumbing_conf();
		print $fh $plumbing_header;
		make_connections($jack_plumbing_code, \@source_tracks, 'in' );
		make_connections($jack_plumbing_code, \@send_tracks,   'out');
		close $fh; 

		# run jack.plumbing
		start_jack_plumbing();
		sleeper(3); # time for jack.plumbing to launch and poll
		kill_jack_plumbing();
		initialize_jack_plumbing_conf();
	}
	else 
	{
		make_connections($jack_connect_code, \@source_tracks, 'in' );
		make_connections($jack_connect_code, \@send_tracks,   'out');
	}
}
}
sub quote { $_[0] =~ /^"/ ? $_[0] : qq("$_[0]")}

sub make_connections {
	my ($code, $tracks, $direction) = @_;
	my $ports_list = $direction eq 'in' ? 'source_id' : 'send_id';
	map{  
		my $track = $_; 
 		my $name = $track->name;
 		my $ecasound_port = "ecasound:$name\_$direction\_";
		my $file = join_path(project_root(), $track->$ports_list);
		say($track->name, 
			": JACK ports file $file not found. No sources connected."), 
			return if ! -e -r $file;
		my $line_number = 0;
		my @lines = read_file($file);
		for my $external_port (@lines){   
			# $external_port is the source port name
			chomp $external_port;
			logit(__LINE__,'::Jack','debug', "port file $file, line $line_number, port $external_port");
			# setup shell command
			
			if(! $jack->{clients}->{$external_port}){
				say $track->name, qq(: port "$external_port" not found. Skipping.);
				next
			}
		
			# ecasound port index
			
			my $index = $track->width == 1
				?  1 
				: $line_number % $track->width + 1;

		my @ports = map{quote($_)} $external_port, $ecasound_port.$index;

			  $code->(
						$direction eq 'in'
							? @ports
							: reverse @ports
					);
			$line_number++;
		};
 	 } @$tracks
}
sub kill_jack_plumbing {
	qx(killall jack.plumbing >/dev/null 2>&1)
	unless $config->{opts}->{A} or $config->{opts}->{J};
}
sub start_jack_plumbing {
	
	if ( 	$config->{use_jack_plumbing}				# not disabled in namarc
			and ! ($config->{opts}->{J} or $config->{opts}->{A})	# we are not testing   

	){ system('jack.plumbing >/dev/null 2>&1 &') }
}
1;
__END__
	
