# ------- Jack port connect routines -------
package ::;
use Modern::Perl;
use File::Slurp;
no warnings 'uninitialized';

# general functions

sub poll_jack { 
		jack_update(); # first time
		# then repeat
		$project->{events}->{poll_jack} = AE::timer(0,5,\&jack_update) 
}

sub jack_update {
	#logsub("&jack_update");
	# cache current JACK status
	
	# skip if Ecasound is busy
	return if ecasound_engine_running();

	if( $jack->{jackd_running} = process_is_running('jackd') ){
		# reset our clients data 
		$jack->{clients} = {};

		$jack->{use_jacks} 
			?  jacks_get_port_latency() 
			:  parse_port_latency();
		parse_ports_list();

		my ($bufsize) = qx(jack_bufsize);
		($jack->{periodsize}) = $bufsize =~ /(\d+)/;

	} else {  }
}

sub client_port {
	my $name = shift;
$name =~ /(.+?):([^:]+)$/;
=comment
	$name =~ /
				(?<client>.+?)	# anything, non-greedy 
	:							# a colon
				(?<port>[^:]+$) # non-colon stuff to end
	/x;

	@+{qw(client port)}
=cut
$1, $2
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
	my ($client_name,$port_name) = client_port($pname);

	logpkg('debug',qq(client: $client_name, port: $port_name));

    my $port = $jc->getPort($pname);

	#my @connections = $jc->getAllConnections($client_name, $port_name);
	#say for @connections;

    my $platency = $port->getLatencyRange($jacks::JackPlaybackLatency);
    my $pmin = $platency->min();
    my $pmax = $platency->max();
    logpkg('debug',"$pname: playback Latency [ $pmin $pmax ]");
	$jack->{clients}->{$client_name}->{$port_name}->{latency}->{playback}->{min} 
		= $pmin;
	$jack->{clients}->{$client_name}->{$port_name}->{latency}->{playback}->{max} 
		= $pmax;

    my $clatency = $port->getLatencyRange($jacks::JackCaptureLatency);
    my $cmin = $clatency->min();
    my $cmax = $clatency->max();
    logpkg('debug',"$pname: capture Latency [ $cmin $cmax ]");
	$jack->{clients}->{$client_name}->{$port_name}->{latency}->{capture}->{min} 
		= $cmin;
	$jack->{clients}->{$client_name}->{$port_name}->{latency}->{capture}->{max} 
		= $cmax;
}


}

sub parse_port_connections {
	my $j = shift || qx(jack_lsp -c 2> /dev/null); 
	return unless $j;

	# initialize
	$jack->{connections} = {}; 
	
	# convert to single lines
	$j =~ s/\n\s+/ /sg;

	my @lines = split "\n",$j;
	#say for @ports;

	for (@lines){
	
		my ($port, @connections) = split " ", $_;
		#say "$port @connections";
		$jack->{connections}->{$port} = \@connections;
		
	}
}
sub jack_port_to_nama {
	my $jack_port = shift;
	grep{ /$config->{ecasound_jack_client_name}/ and $jack->{is_own_port}->{$_} } @{ $jack->{connections}->{$jack_port} };
}
	
sub parse_port_latency {
	
	# default to use output of jack_lsp -l
	
	my $j = shift || qx(jack_lsp -l 2> /dev/null); 
	logpkg('debug', "latency input $j");
	
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

		#logpkg('debug', Dumper %+);
		logpkg('debug', "client: ",$+{client});
		logpkg('debug', "port: ",$+{port});
		logpkg('debug', "capture min: ", $+{capture_min});
		logpkg('debug', "capture max: ",$+{capture_max});
		logpkg('debug', "playback min: ",$+{playback_min});
		logpkg('debug', "playback max: ",$+{playback_max});
		
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
	logpkg('debug', "input: $j");

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

# connect jack ports via jack_connect


sub quote { $_[0] =~ /^"/ ? $_[0] : qq("$_[0]")}

sub make_connections {
	my ($code, $tracks, $direction) = @_;
	my $ports_list = $direction eq 'in' ? 'source_id' : 'send_id';
	map{  
		my $track = $_; 
 		my $name = $track->name;
 		my $ecasound_port = $config->{ecasound_jack_client_name}.":$name\_$direction\_";
		my $file = join_path(project_root(), $track->$ports_list);
		throw($track->name, 
			": JACK ports file $file not found. No sources connected."), 
			return if ! -e -r $file;
		my $line_number = 0;
		my @lines = read_file($file);
		for my $external_port (@lines){   
			# $external_port is the source port name
			chomp $external_port;
			logpkg('debug', "port file $file, line $line_number, port $external_port");
			# setup shell command
			
			if(! $jack->{clients}->{$external_port}){
				throw($track->name, 
					qq(: port "$external_port" not found. Skipping.));
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
sub jack_client : lvalue {
	my $name = shift;
	logit('::Jack','info',"$name: non-existent JACK client") if not $jack->{clients}->{$name} ;
	$jack->{clients}->{$name}
}
sub port_mapping {
	my $jack_port = shift;
	my $own_port;
	#.....
	$own_port
}

sub register_other_ports { 
	return unless $jack->{jackd_running};
	$jack->{is_other_port} = { map{ chomp; $_ => 1 } qx(jack_lsp) } 
}

sub register_own_ports { # distinct from other Nama instances 
	return unless $jack->{jackd_running};
	$jack->{is_own_port} = 
	{ 
		map{chomp; $_ => 1}
		grep{ ! $jack->{is_other_port}->{$_} }
		grep{ /^$config->{ecasound_jack_client_name}/ } 
		qx(jack_lsp)
	} 
}


1;
__END__
	
