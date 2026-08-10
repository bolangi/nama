# ----------- Logging ------------

package ::Log;
use v5.36;
our $VERSION = 1.1;
use Exporter;
use File::Basename qw(basename);
use IO::Handle ();
use Time::HiRes qw(time);

our @ISA = 'Exporter';
our @EXPORT_OK = qw(
	logit logpkg logsub initialize_logger
	initialize_output emit_output set_log_sink set_output_sink discard_output_buffer
);

my %enabled;
my $noisy;
my $started = time;
my $sink;
my $log_fh;
my @pending;

sub initialize_output () {
	close $log_fh if defined $log_fh;
	undef $log_fh;
	undef $sink;
	@pending = ();

	if (defined $ENV{NAMA_LOGFILE}) {
		open $log_fh, '>>:encoding(UTF-8)', $ENV{NAMA_LOGFILE}
			or die "Unable to open $ENV{NAMA_LOGFILE}: $!";
		$log_fh->autoflush(1);
	}
}

sub emit_output ($message, $immediate_fh = undef) {
	print {$log_fh} $message if defined $log_fh;

	if (defined $sink) {
		$sink->($message);
	}
	else {
		push @pending, $message;
		print {$immediate_fh} $message if defined $immediate_fh;
	}
}

sub set_output_sink ($new_sink) {
	$sink = $new_sink;
	my @messages = splice @pending;
	$sink->($_) for @messages;
}

sub discard_output_buffer () { @pending = () }

sub initialize_logger ($cat_string = undef) {
	my @all_cats = qw(
[% qx(./emit_logging_categories) %]
	);
	push @all_cats, qw(ECI SUB);

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

	}

	return { %enabled };
}

sub set_log_sink ($new_sink) {
	set_output_sink($new_sink);
}

sub expand_cats (@cats) {
	for (@cats) {
		my $negated = s/^#//;
		unless (/^ECI/ or /^SUB$/ or /^ALL$/) {
			$_ = canonical_category($_);
		}
		$_ = "#$_" if $negated;
	}
	return @cats;
}

sub canonical_category ($category) {
	return $category if $category =~ /^ECI/ or $category eq 'SUB';
	my $name = basename($category);
	$name =~ s/\.(?:pm?|t)\z//;
	$name =~ s/^(?:Audio::Nama::)+//;
	return "Audio::Nama::$name"; # SKIP_PREPROC
}

sub logit ($line_number, $category, $level, @message) {
	_emit($line_number, $category, $level, @message);
}

sub _emit ($line_number, $category, $level, @message) {
	return unless $enabled{$category};
	return if $level eq 'trace' and !$noisy;

	die "illegal log level: $level" unless $level eq 'debug' or $level eq 'trace';
	@message = map { ref $_ eq 'CODE' ? $_->() : $_ } @message;
	my $message = join q(), @message;

	my $elapsed = int((time - $started) * 1000);
	my $line = $line_number ? " (L $line_number) " : q( );
	my $formatted = "[$elapsed] $category$line$message";
	$formatted .= "\n" unless $formatted =~ /\n\z/;

	emit_output($formatted, \*STDERR);

	return;
}

sub logsub ($sub_name, @ignored) { _emit(0, 'SUB', 'debug', $sub_name) }

sub logpkg ($file, $line_no, $level, @message) {
	my $pkg = canonical_category($file);
	_emit($line_no, $pkg, $level, @message);
}

1;
