use v5.36;
use Test::More;
use FindBin;
our ($setup, $this_track, $this_engine, $this_edit, $ui, $time, $running, $stops, $starts, @messages, %tn);
package EditTestTrack {
 sub name ($s) { $s->{name} }
 sub playback_version ($s) { $s->{version} }
 sub candidate_play { 1 }
 sub candidate_rec { 0 }
 sub current_edit ($s) { $s->{current_edit} //= {} }
}
package EditTestEngine { sub started { $main::running } }
package EditTestUI {
 sub prompt_for_text ($s,$m,$cb) { $s->{callback}=$cb; $s->{prompts}++ }
 sub prompt_yn ($s,$m,$default,$cb) { $s->{callback}=$cb; $s->{default}=$default }
}
package ChainSetup { sub really_recording { 0 } }
sub current_timeline_position { $time }
sub set_timeline_position ($t) { $time=$t }
sub start_transport { $running=1; $starts++ }
sub stop_transport { $running=0; $stops++ }
sub notify (@m) { push @messages, join '', @m }
sub throw (@m) { notify(@m) }
sub d1 ($n) { sprintf '%.1f', $n }
sub valid_track_name ($n) { $n ne 'play' and not $tn{$n} }
sub edit_action ($action) { }
open my $fh,'<',"$FindBin::Bin/../lib/Audio/Nama/Edit.pm" or die $!;
my $source = do { local $/; <$fh> };
$source =~ s/Audio\x3a\x3aNama(?=\x3a\x3a)//g;
my ($capture) = $source =~ /(# Capture state.*?)(?=sub transfer_edit_points)/s;
my ($new_edit) = $source =~ /(sub new_edit \{.*?)(?=\{my %edit_actions)/s;
eval $capture; die $@ if $@;
eval $new_edit; die $@ if $@;
# Constructor stub emulates the nested constructor selection side effect, scoped
# exactly as the production Edit constructor is scoped.
package Edit {
 our ($n, %by_index);
 sub new ($class,%args) {
  local $main::this_track = $main::this_track;
  $main::this_track = bless {name=>'auxiliary'}, 'EditTestTrack';
  my $s=bless {n=>++$n,%args},$class; $by_index{$n}=$s; $s;
 }
 sub n ($s) { $s->{n} }
 sub host_track ($s) { $s->{host_track} }
 sub host_version ($s) { $s->{host_version} }
 sub edit_name ($s) { join '-', $s->host_track, 'v'.$s->host_version, ($s->{edit_label}//('edit'.$s->n)) }
 sub rec_start_time ($s) { $s->{points}[1] }
 sub rec_end_time ($s) { $s->{points}[2] }
}
sub transfer_edit_points ($edit) { $edit->{points}=[@{$setup->{edit_points}}]; initialize_edit_points() }
sub reset_case {
 $setup={}; $this_track=bless {name=>'sax',version=>5},'EditTestTrack';
 $this_engine=bless {},'EditTestEngine'; $ui=bless {},'EditTestUI';
 $time=0; $running=1; $stops=$starts=0; @messages=(); %tn=();
 %Edit::by_index=(); $Edit::n=0; undef $this_edit; initialize_edit_points();
}
reset_case();
mark_rec_start(); like($messages[-1],qr/F3/,'F4 before F3 explains prerequisite');
mark_play_start(); ok(!$running,'name prompt stops transport');
$time=99; $ui->{callback}->('play'); is($ui->{prompts},2,'invalid name prompts again');
$ui->{callback}->('phrase'); is_deeply($setup->{edit_points},[0],'captures position before prompt, including zero');
ok($running,'resumes previously running transport');
is($setup->{edit_label},'phrase','retains supplied name');
$time=2; mark_edit_record(); $time=2; mark_edit_record();
is(scalar @{$setup->{edit_points}},2,'rejects zero-length recording');
$time=4; mark_edit_record(); ok(!$running,'completion stops transport');
ok(!edit_marking_active(),'completion exits capture');
new_edit(); is($this_edit->edit_name,'sax-v5-phrase','name replaces editN suffix');
is($this_track->name,'sax','host selection survives creation');
is($this_track->current_edit->{5},1,'current edit belongs to host');
new_edit(); like($messages[-1],qr/Mark playback/,'consumed empty points rejected');
$setup->{edit_points}=[0,2,4]; new_edit(); like($messages[-1],qr/overlaps/,'identical interval rejected');
$setup->{edit_points}=[0,2,5]; new_edit(); like($messages[-1],qr/overlaps/,'shared start overlap rejected');
$setup->{edit_points}=[0,1,4]; new_edit(); like($messages[-1],qr/overlaps/,'shared end overlap rejected');
$setup->{edit_points}=[0,4,6]; new_edit(); is(scalar keys %Edit::by_index,2,'touching intervals allowed on same version');
$this_track->{version}=6; $setup->{edit_points}=[0,2,4]; new_edit();
is(scalar keys %Edit::by_index,3,'other version does not conflict');
reset_case(); $running=0; mark_play_start(''); ok(!$running,'stopped transport remains stopped');
$time=1; mark_rec_start(); cancel_edit_marking(); is($ui->{default},'no','cancel defaults to no');
$ui->{callback}->(0); ok(edit_marking_active(),'declining preserves marking');
is_deeply($setup->{edit_points},[0,1],'declining preserves points');
cancel_edit_marking(); $ui->{callback}->(1); ok(!edit_marking_active(),'confirmation ends marking');
is_deeply($setup->{edit_points},[],'confirmation discards points');
reset_case(); mark_play_start('phrase'); $this_track->{version}=6;
$time=2; mark_rec_start(); is_deeply($setup->{edit_points},[0],'cannot mark on another version');
reset_case(); mark_play_start(); $ui->{callback}->(undef);
ok(!edit_marking_active(),'cancelled name prompt creates no capture');
ok($running,'cancelled name prompt restores transport');
# Exercise the actual constructor, including reuse of the version mixer.
{
 no warnings 'redefine';
 my ($constructor) = $source =~ /(sub new \{.*?)(?=# default mark names)/s;
 eval 'package Edit; use Carp qw(croak confess); use constant { PLAY => "PLAY", REC => "REC" }; our (%_is_field, $n, %by_name, %by_index); '.$constructor;
 die $@ if $@;
 %Edit::_is_field = map { $_ => 1 } qw(host_track host_version edit_label n fades);
}
package Edit {
 sub edit_label ($s) { $s->{edit_label} }
 sub next_n { ++$Edit::n }
}
package EditTestTrack {
 sub activate_bus { }
 sub source_type { 'soundcard' }
 sub source_id { 1 }
 sub live_input_channels { 1 }
 sub file_channels { 2 }
}
package Track {
 sub new ($class,%args) {
  return if $main::tn{$args{name}};
  my $s=bless {%args},'EditTestTrack';
  $main::tn{$args{name}}=$s; $main::this_track=$s; return $s;
 }
}
package VersionTrack { our @ISA=('Track') }
package EditTrack { our @ISA=('Track') }
reset_case(); $tn{sax}=$this_track;
my $host=$this_track;
my $first=Edit->new(host_track=>'sax',host_version=>5,edit_label=>'phrase');
is($this_track,$host,'actual constructor restores caller selection');
is($tn{'sax-v5-phrase'}{live_input_channels},2,'edit inherits file channels despite mono live input setting');
my $mixer=$tn{'sax-v5'};
my $second=Edit->new(host_track=>'sax',host_version=>5);
is($tn{'sax-v5'},$mixer,'second edit reuses existing version mixer');
is($this_track,$host,'second edit also restores selection');
my $restored=Edit->new(host_track=>'sax',host_version=>5,n=>42);
my $next=Edit->new(host_track=>'sax',host_version=>5);
is($next->n,43,'restored IDs advance counter to avoid future collisions');
# Destruction confirmation is asynchronous and must preserve selection on No.
our $ended_edit_mode = 0;
sub end_edit_mode { $ended_edit_mode++ }
package EditTestDestroy { sub edit_name { 'sax-v5-phrase' } sub destroy ($s) { $s->{destroyed}++ } }
my ($destroy) = $source =~ /(sub destroy_edit \{.*?)(?=sub set_edit_mode)/s;
eval $destroy; die $@ if $@;
$this_edit=bless {}, 'EditTestDestroy';
destroy_edit(); $ui->{callback}->(0);
ok(!$this_edit->{destroyed},'declining destruction preserves edit');
is($ended_edit_mode,0,'declining destruction preserves edit mode');
destroy_edit(); $ui->{callback}->(1);
is($this_edit->{destroyed},1,'confirmed destruction removes edit');
is($ended_edit_mode,1,'confirmed destruction exits edit mode');
done_testing;
