use v5.36;
use Test::More;

# IO's diagnostics normally come from the main Nama package. Loading just
# IO keeps these routing checks independent of the UI and audio engines.
BEGIN {
    package ::;
    use Data::Dumper::Concise;
    sub logpkg { }
    sub throw { die join q(), @_ }
}
use ::IO;

for my $case (
    [1, 5, '-chorder:5'],
    [2, 7, '-chorder:7,8'],
    [4, 5, '-chorder:5,6,7,8'],
    [2, 2, '-chorder:2,3'],
    [2, 1, ''],
    [1, undef, ''],
) {
    my ($channels, $first, $expected) = @$case;
    my $io = ::IO::from_alsa_soundcard_device->new(
        source_channels => $channels, source_id => $first,
    );
    is($io->rec_route, $expected,
        'select input channels: count ' . $channels . ', first ' . ($first // 'default'));
}

for my $case (
    [1, 5, ' -chorder:0,0,0,0,1'],
    [2, 5, ' -chorder:0,0,0,0,1,2'],
    [2, 2, ' -chorder:0,1,2'],
    [4, 3, ' -chorder:0,0,1,2,3,4'],
    [2, 1, ''],
    [2, undef, ''],
) {
    my ($channels, $first, $expected) = @$case;
    my $io = ::IO::to_alsa_soundcard_device->new(
        output_channels => $channels, send_id => $first,
    );
    is($io->ecs_extra, $expected,
        'place output channels: count ' . $channels . ', first ' . ($first // 'default'));
}

done_testing;
