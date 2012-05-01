# ----------- Latency Compensation -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use ::Globals qw(:all);

sub latency_comp {
	my $mix_track_name = shift;
	my $g = $setup->{latency_graph};
	my @members = $g->predecessors($mix_track_name);
	my $latency = track_latency($tn{$mix_track_name});
	my @latencies;
	map 
	{ 
		
	$_	
		
	} @members;
}

sub track_latency {
	my $track = shift;
	my $total = 0;
	map
	{ 
		my $op = $_;
		my $i = effect_index(type($op));	
		my $p = 0; 
		my $p_index;

		# get latency parameter
		
		# TODO make this a lazy object method

		for my $param ( @{ $fx_cache->{registry}->[$i]->{params} } )
		{
			($p_index = $p), last 
				if lc( $param->{name}) eq 'latency' 
					and $param->{dir} eq 'output';
			$p++;
		}
		$total += get_live_param($op, $p_index) if defined $p_index;

	} $track->fancy_ops;
	$total
}

sub get_live_param { # for effect, not controller
					 # $param is position, starting at zero
	my ($op, $param) = @_;
	$param++; # index from one
	my $n = chain($op);
	my $i = ecasound_effect_index($op);
	eval_iam("c-select $n");
	eval_iam("cop-select $i");
	eval_iam("copp-select $param");
	eval_iam("copp-get")
}
	

sub adjust_latency {

	$debug2 and print "&adjust_latency\n";
	map { $fx->{params}->{$_->latency}[0] = 0  if $_->latency() } 
		::Track::all();
	set_preview_mode();
	exit_preview_mode();
	my $cop_status = eval_iam('cop-status');
	$debug and print $cop_status;
	my $chain_re  = qr/Chain "(\d+)":\s+(.*?)(?=Chain|$)/s;
	my $latency_re = qr/\[\d+\]\s+latency\s+([\d\.]+)/;
	my %chains = $cop_status =~ /$chain_re/sg;
	$debug and print yaml_out(\%chains);
	my %latency;
	map { my @latencies = $chains{$_} =~ /$latency_re/g;
			$debug and print "chain $_: latencies @latencies\n";
			my $chain = $_;
		  map{ $latency{$chain} += $_ } @latencies;
		 } grep { $_ > 2 } sort keys %chains;
	$debug and print yaml_out(\%latency);
	my $max;
	map { $max = $_ if $_ > $max  } values %latency;
	$debug and print "max: $max\n";
	map { my $adjustment = ($max - $latency{$_}) / $config->{sampling_freq} * 1000;
			$debug and print "chain: $_, adjustment: $adjustment\n";
			effect_update_copp_set($ti{$_}->latency, 2, $adjustment);
			} keys %latency;
}
1;
