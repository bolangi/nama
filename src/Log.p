# ----------- Logging ------------

package ::Log;
use v5.36;
our $VERSION = 1.1;
use Exporter;
use Carp qw(shortmess longmess);
use File::Basename qw(basename);
use IO::Handle ();
use Time::HiRes qw(time);

our @ISA = 'Exporter';
our @EXPORT_OK = qw(logit logpkg logsub initialize_logger set_log_sink);

my %enabled;
my $noisy;
my $started = time;
my $sink;
my $log_fh;
my @pending;

sub initialize_logger ($cat_string = undef) {
	my @all_cats = qw(
[% qx(./emit_logging_categories) %]
	);
	push @all_cats, qw(ECI SUB);

	close $log_fh if defined $log_fh;
	undef $log_fh;
	undef $sink;
	@pending = ();
	%enabled = ();
	$noisy = 0;
	$started = time;

	my %negate;
	if ($cat_string) {
		my @requested = map { s/^\s+|\s+$//gr } split q(,), $cat_string;
		$noisy = grep { $_ eq 'NOISY' } @requested;
		@requested = grep { $_ ne 'NOISY' } @requested;

		%negate = map { $_ => 1 }
			expand_cats(map { s/^#//r } grep { /^#/ } @requested);

		my @cats = expand_cats(@requested);
		@cats = grep { !$negate{$_} } @all_cats
			if grep { $_ eq 'ALL' } @cats;
		%enabled = map { $_ => 1 } @cats;
		$enabled{NOISY} = 1 if $noisy;

		$SIG{__DIE__} = sub {
			local $SIG{__DIE__};
			die longmess(@_);
		};
	}

	if ($cat_string and defined $ENV{NAMA_LOGFILE}) {
		open $log_fh, '>>:encoding(UTF-8)', $ENV{NAMA_LOGFILE}
			or die "Unable to open $ENV{NAMA_LOGFILE}: $!";
		$log_fh->autoflush(1);
		$sink = sub ($message) { print {$log_fh} $message };
	}

	return { %enabled };
}

sub set_log_sink ($new_sink) {
	return if defined $log_fh;
	$sink = $new_sink;
	my @messages = splice @pending;
	$sink->($_) for @messages;
}

sub expand_cats (@cats) {
	for (@cats) {
		unless (/^::/ or /^#?ECI/ or /^#?SUB/ or /^ALL$/) {
			s/^#/#::/ or s/^/::/;
		}
		s/^::/Audio::Nama::/;
		s/^#::/#Audio::Nama::/;
	}
	return @cats;
}

my %valid_level = map { $_ => 1 } qw(
	trace debug info warn error fatal
	logwarn logdie logcarp logcroak logcluck logconfess
);

sub logit ($line_number, $category, $level, @message) {
	_emit($line_number, $category, $level, @message);
}

sub _emit ($line_number, $category, $level, @message) {
	return unless $enabled{$category};
	return if $level eq 'trace' and !$noisy;

	die "illegal log level: $level" unless $valid_level{$level};
	@message = map { ref $_ eq 'CODE' ? $_->() : $_ } @message;
	my $message = join q(), @message;

	{
		local $Carp::CarpLevel = 1;
		$message = shortmess($message) if $level eq 'logcarp' or $level eq 'logcroak';
		$message = longmess($message)  if $level eq 'logcluck' or $level eq 'logconfess';
	}

	my $elapsed = int((time - $started) * 1000);
	my $line = $line_number ? " (L $line_number) " : q( );
	my $formatted = "[$elapsed] $category$line$message";
	$formatted .= "\n" unless $formatted =~ /\n\z/;

	if (defined $sink) {
		$sink->($formatted);
	}
	else {
		push @pending, $formatted;
	}

	die $message if $level eq 'logdie' or $level eq 'logcroak' or $level eq 'logconfess';
	return;
}

sub logsub ($sub_name, @ignored) { _emit(0, 'SUB', 'debug', $sub_name) }

sub logpkg ($file, $line_no, $level, @message) {
	my $pkg = basename($file);
	$pkg =~ s/\.pm\z//;
	$pkg = "Audio::Nama::$pkg"; # SKIP_PREPROC
	_emit($line_no, $pkg, $level, @message);
}

1;
