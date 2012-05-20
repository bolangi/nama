# ------- WAV file info routines ---------

package ::;
use Modern::Perl;

### WAV file length/format/modify_time are cached in $setup->{wav_info} 

### Cached methods

sub wav_length {  
	my $path = shift;
	_update_wav_cache($path);
	$setup->{wav_info}->{$path}{length}
}
sub wav_format {
	my $path = shift;
	_update_wav_cache($path);
	$setup->{wav_info}->{$path}{format}
}

### Implementation

sub cache_wav_info {
	my @files = File::Find::Rule
		->file()
		->name( '*.wav' )
		->in( this_wav_dir() );	
	map{  _get_wav_info($_) } @files;
}
sub _get_wav_info {
	my $path = shift;
	#say "path: $path";
	$setup->{wav_info}->{$path}{length} = _get_length($path);
	$setup->{wav_info}->{$path}{format} = _get_format($path);
	$setup->{wav_info}->{$path}{modify_time} = _get_modify_time($path);
}
sub _get_length { 
	my $path = shift;
	my $length = ecasound_get_info($path, 'ai-get-length');
	$length ? sprintf("%.4f", $length) : undef
}
sub _get_format {
	my $path = shift;
	ecasound_get_info($path, 'ai-get-format');
}
sub _get_modify_time {
	my $path = shift;
	my @stat = stat $path;
	$stat[9]
}
sub _update_wav_cache {
	my $path = shift;
	return unless _get_modify_time($path) != $setup->{wav_info}->{$path}{modify_time};
	say qq(WAV file $path has changed! Updating cache.);
	_get_wav_info($path) 
}

sub ecasound_get_info {
	# get information about an audio object
	
	my ($path, $command) = @_;

	local $config->{category} = 'ECI_WAVINFO';

	$path = qq("$path");
	teardown_engine();
	eval_iam('cs-add gl');
	eval_iam('c-add g');
	eval_iam('ai-add ' . $path);
	eval_iam('ao-add null');
	eval_iam('cs-connect');
	eval_iam('ai-select '. $path);
	my $result = eval_iam($command);
	teardown_engine();
	$result;
}
1;
__END__
	
