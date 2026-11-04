use v5.36;
use Test::More;
use FindBin;
use File::Spec;
our (%formats, %tn, $config, @tracks_data, @bus_data);
$config = {};
sub join_path (@parts) { File::Spec->catfile(@parts) }
sub channels ($format) { (split ',', $format)[1] }
sub wav_format ($path) { $formats{$path} }
sub signal_format ($template, $channels) { $template =~ s/N/$channels/r }
sub throw (@message) { die join '', @message }
sub module_source ($name) {
    open my $fh, '<', "$FindBin::Bin/../lib/Audio/Nama/$name.pm" or die $!;
    my $source = do { local $/; <$fh> };
    $source =~ s/Audio\x3a\x3aNama(?=\x3a\x3a)//g;
    return $source;
}
sub install ($package, $code) {
    die "Missing extracted code for $package" unless defined $code;
    eval "package $package; $code";
    die $@ if $@;
}
package ChannelTestTrack {
    sub candidate_play ($s) { $s->{rw} eq 'PLAY' }
    sub live_input_channels ($s) { $s->{live_input_channels} }
    sub playback_version ($s) { $s->{version} }
    sub targets ($s) { $s->{targets} }
    sub dir { '/audio' }
    sub pan_id { 1 }
}
my $track_source = module_source('Track');
my ($track_methods) = $track_source =~ /(sub source_channels .*?)(?=sub snapshot)/s;
install('ChannelTestTrack', $track_methods);
my ($file_method) = module_source('Wav') =~ /(sub file_channels .*?)(?=sub dir)/s;
install('ChannelTestTrack', 'sub join_path { main::join_path(@_) } '.$file_method);
my $track = bless {rw => 'PLAY', version => 2, live_input_channels => 1,
    targets => {1 => 'piano_1.wav', 2 => 'piano_2.wav'}}, 'ChannelTestTrack';
$formats{'/audio/piano_1.wav'} = 's16_le,1,48000';
$formats{'/audio/piano_2.wav'} = 's16_le,2,48000';
is($track->live_input_channels,1,'live setting stays independent of file channels');
is($track->file_channels,2,'file count comes from selected version');
is($track->file_channels(1),1,'explicit version can be inspected');
is($track->source_channels,2,'PLAY uses file count');
is($track->output_channels,2,'output initially copies source count');
$track->{rw}='REC';
is($track->source_channels,1,'REC uses live input count');
is($track->file_channels,2,'file inspection still uses playback version when armed');
is($track->output_channels,1,'REC output initially copies live source');
$track->{live_input_channels}=4; $track->{rw}='MON';
is($track->source_channels,4,'MON uses live input count');
$track->{version}=99;
ok(!defined $track->file_channels,'missing version has no invented file channel count');
$track->{version}=2;
# Exercise production IO AUTOLOAD and directional format/routing methods.
my $io = module_source('IO');
my ($autoload) = $io =~ /(sub AUTOLOAD \{.*?)(?=sub DESTROY)/s;
my ($format) = $io =~ /(sub _format \(.*?)(?=sub _format_template)/s;
my ($direction) = $io =~ /(sub direction \{.*?)(?=sub io_prefix)/s;
install('ChannelTestIO', 'use Carp qw(croak); our ($AUTOLOAD, %tn); *tn = \%main::tn; '.$autoload.$format.$direction.'sub DESTROY {}');
package ChannelTestIO::from_test { our @ISA=('ChannelTestIO') }
package ChannelTestIO::to_test { our @ISA=('ChannelTestIO') }
$tn{piano}=$track;
my $input=bless {track_=>'piano',format_template_=>'s16_le,N,48000'},'ChannelTestIO::from_test';
my $output=bless {track_=>'piano',format_template_=>'s16_le,N,48000'},'ChannelTestIO::to_test';
is($input->format,'s16_le,4,48000','live input format uses live source count');
$track->{rw}='PLAY';
is($output->format,'s16_le,2,48000','output format uses file count rather than live count');
$input->{source_channels_}=6; $output->{output_channels_}=8;
is($input->format,'s16_le,6,48000','graph source override is honored');
is($output->format,'s16_le,8,48000','graph output override is honored independently');
my ($wav_channels)=$io =~ /(sub _source_channels .*?)(?=sub ecs_extra)/s;
install('ChannelTestIO::from_wav', 'our @ISA=("ChannelTestIO"); '.$wav_channels);
my $wav_input=bless {track_=>'piano',full_path_=>'/audio/piano_1.wav'},'ChannelTestIO::from_wav';
is($wav_input->source_channels,1,'WAV input honors graph path override, not selected version');
my ($rec_route)=$io =~ /(sub rec_route \{.*?\n\})/s;
install('ChannelTestIO::from_alsa', 'our @ISA=("ChannelTestIO"); '.$rec_route);
my $alsa_in=bless {input_channel_=>3,source_channels_=>2},'ChannelTestIO::from_alsa';
is($alsa_in->rec_route,'-chorder:3,4','ALSA capture selects source channel count');
my ($output_route)=$io =~ /(sub route \{.*?\n\})/s;
install('ChannelTestIO::to_alsa',$output_route);
is(ChannelTestIO::to_alsa::route(2,3),' -chorder:0,0,1,2','ALSA output routes the supplied output count');
# Use only the current restore-time migration clause; no historical code.
my ($migration) = module_source('Persistence') =~ /####### Backward Compatibility ########(.*?)#######################################/s;
@tracks_data=({width=>2},{width=>1,live_input_channels=>6},{live_input_channels=>4});
@bus_data=(); eval $migration; die $@ if $@;
is_deeply(\@tracks_data,[{live_input_channels=>2},{live_input_channels=>6},{live_input_channels=>4}],
    'restore converts old width, removes it, and preserves any newer setting');
eval $migration; die $@ if $@;
is($tracks_data[0]{live_input_channels},2,'migration is idempotent');
ok(!exists $tracks_data[0]{width},'future saved state has no old width field');
# Slave and cache receiver counts follow their source, not their own defaults.
my ($slave_source) = $track_source =~ /(sub source_channels \{ \$tn\{\$_\[0\]->target\}->source_channels \})/;
install('ChannelTestSlave', 'our %tn; *tn = \%main::tn; sub target { $_[0]->{target} } '.$slave_source);
$track->{rw}='PLAY';
my $slave=bless {target=>'piano',live_input_channels=>8},'ChannelTestSlave';
is($slave->source_channels,2,'slave gets source count from its target');
# The production cache routine must remember file channels before forcing REC.
our ($this_track, $g, $cache_args);
sub logsub (@args) { }
sub logpkg (@args) { }
sub notify (@args) { }
sub cachable ($track) { 'effects' }
sub process_cache_graph ($graph) { 1 }
sub deactivate_vol_pan ($args) { }
sub reactivate_vol_pan ($args) { }
sub cache_engine_run ($args) { $cache_args=$args }
package ChannelTestTrack {
 sub name { 'piano' }
 sub is_mixer { 0 }
 sub candidate_off { 0 }
 sub last { 2 }
 sub rw ($s) { $s->{rw} }
 sub set ($s,%args) { $s->{$_}=$args{$_} for keys %args }
}
package ChannelTestGraph {
 sub add_path { }
 sub set_vertex_attributes ($s,$name,$args) { $s->{$name}={%{$s->{$name}//{}},%$args} }
}
package ChainSetup { sub initialize { bless {},'ChannelTestGraph' } }
package CacheRecTrack {
 sub new ($class,%args) { bless \%args,$class }
 sub name ($s) { $s->{name} }
 sub current_wav { 'piano_cooked_3.wav' }
}
my $cache=module_source('CacheTrack');
my ($cache_routine)=$cache =~ /(sub cache_track \{.*?)(?=sub cachable)/s;
my ($cache_graph)=$cache =~ /(sub generate_cache_track_graph \{.*?)(?=sub process_cache_graph)/s;
install('main', 'our ($this_track, $g, $config, %tn); use constant { MON => "MON", PLAY => "PLAY", OFF => "OFF", REC => "REC" }; '.$cache_routine.$cache_graph);
$tn{Main}=bless {rw=>'MON'},'ChannelTestTrack';
$track->{live_input_channels}=1;
$config->{cache_to_disk_format}='s16_le,N,48000';
cache_track($track);
is($cache_args->{output_channels},2,'caching remembers stereo file count before arming REC');
is($track->{rw},'REC','test reaches temporary cache recording state');
is($cache_args->{graph}{piano_cooked}{format},'s16_le,2,48000','cache output stays stereo despite mono live setting');
done_testing;
