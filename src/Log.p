# ----------- Logging ------------

package ::Log;
use Exporter;
our @ISA = 'Exporter';
our @EXPORT_OK = qw(logit initialize_logger);
use Modern::Perl;
use Log::Log4perl qw(get_logger :levels);
use Carp;

sub initialize_logger {
	my $cat_string = shift;

	my $layout = "[\%r] %m%n"; # backslash to protect from source filter
	my $logfile = $ENV{NAMA_LOGFILE} || "";
	my $appender = $logfile ? 'FILE' : 'STDERR';

	my @log_cats = grep{ $_ } split /\s*\n\s*/, qq(
		log4perl.category.ECI_WAVINFO	= DEBUG, $appender
		log4perl.category.ECI_OTHER		= DEBUG, $appender
		log4perl.category.ECI			= DEBUG, $appender
		log4perl.category.CONFIG		= DEBUG, $appender
		log4perl.category.ECI_FX		= DEBUG, $appender
		log4perl.category.FX			= DEBUG, $appender
		log4perl.category.SUB			= DEBUG, $appender
);
	my %log_cats = map
	{
		my ($cat) = /category\.(\S+)/;
		($cat => $_)
	} @log_cats;
	
	my @cats = grep{ $log_cats{$_} }  split ',', $cat_string;
	
	say "Logging categories: @cats" if @cats;

	#say Dumper %log_cats;

	my $conf = qq(
		#log4perl.rootLogger			= DEBUG, $appender
		#log4perl.category.Audio.Nama	= DEBUG, $appender

		# dummy entry - avoid no logger/no appender warnings
		log4perl.category.DUMMY			= DEBUG, DUMMY
		log4perl.appender.DUMMY			= Log::Log4perl::Appender::Screen
		log4perl.appender.DUMMY.layout	= Log::Log4perl::Layout::NoopLayout

		# screen appender
		log4perl.appender.STDERR		= Log::Log4perl::Appender::Screen
		log4perl.appender.STDERR.layout	= Log::Log4perl::Layout::PatternLayout
		log4perl.appender.STDERR.layout.ConversionPattern = $layout

		# file appender
		log4perl.appender.FILE		= Log::Log4perl::Appender::File
		log4perl.appender.FILE.filename	= $logfile
		log4perl.appender.FILE.layout	= Log::Log4perl::Layout::PatternLayout
		log4perl.appender.FILE.layout.ConversionPattern = $layout

		#log4perl.additivity.SUB			= 0 # doesn't work... why?
	);
	# add lines for the categories we want to log
	$conf .= join "\n", "", @log_cats{@cats} if @cats;
	#say $conf; 
	Log::Log4perl::init(\$conf);
	return( { map { $_, 1 } @cats } )
}
sub logit {
	my ($category, $level, $message) = @_;
	return unless $category;
	my $logger = get_logger($category);
	$logger->$level($message);
}
	
1;
