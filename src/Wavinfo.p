# ------- WAV file info routines ---------

package ::;
use Modern::Perl;

### WAV file length/format/modify_time are cached in $setup->{wav_info} 

sub ecasound_get_info {
	# get information about an audio object
	
	my ($path, $command) = @_;

	local $config->{log} = 'WAVINFO';

	$path = qq("$path");
	teardown_engine();
	_eval_iam('cs-add gl');
	_eval_iam('c-add g');
	_eval_iam('ai-add ' . $path);
	_eval_iam('ao-add null');
	_eval_iam('cs-connect');
	_eval_iam('ai-select '. $path);
	my $result = _eval_iam($command);
	teardown_engine();
	$result;
}
sub _eval_iam { eval_iam($_[0], 'WAVINFO') }

sub cache_wav_info {
	my @files = File::Find::Rule
		->file()
		->name( '*.wav' )
		->in( this_wav_dir() );	
	map{  get_wav_info($_) } @files;
}
sub get_wav_info {
	my $path = shift;
	#say "path: $path";
	$setup->{wav_info}->{$path}{length} = get_length($path);
	$setup->{wav_info}->{$path}{format} = get_format($path);
	$setup->{wav_info}->{$path}{modify_time} = get_modify_time($path);
}
sub get_length { 
	my $path = shift;
	my $length = ecasound_get_info($path, 'ai-get-length');
	sprintf("%.4f", $length);
}
sub get_format {
	my $path = shift;
	ecasound_get_info($path, 'ai-get-format');
}
sub get_modify_time {
	my $path = shift;
	my @stat = stat $path;
	$stat[9]
}
sub wav_length {
	my $path = shift;
	update_wav_cache($path);
	$setup->{wav_info}->{$path}{length}
}
sub wav_format {
	my $path = shift;
	update_wav_cache($path);
	$setup->{wav_info}->{$path}{format}
}
sub update_wav_cache {
	my $path = shift;
	return unless get_modify_time($path) != $setup->{wav_info}->{$path}{modify_time};
	say qq(WAV file $path has changed! Updating cache.);
	get_wav_info($path) 
}
1;
__END__
	
