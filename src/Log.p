# ----------- Logging ------------

package ::Log;
use Modern::Perl;
use Log::Log4perl qw(get_logger :levels);
use Exporter;
our @ISA = 'Exporter';
our @EXPORT_OK = qw(logit logsub initialize_logger);
our $appender;

sub initialize_logger {
	my $cat_string = shift;

	my $layout = "[\%r] %m%n"; # backslash to protect from source filter
	my $logfile = $ENV{NAMA_LOGFILE} || "";
	$appender = $logfile ? 'FILE' : 'STDERR';

sub cat_line { "log4perl.category.$_[0]			= DEBUG, $appender" }

	my @cats = map { s/::/Audio::Nama::/; $_}                    # SKIP_PREPROC
				map { s/^/::/ unless /^::/ or /^ECI/ or /^SUB/; $_ } # SKIP_PREPROC
				split ',', $cat_string;                    
	
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
	$conf .= join "\n", "", map{ cat_line($_)} @cats if @cats;
	#say $conf; 
	Log::Log4perl::init(\$conf);
	return( { map { $_, 1 } @cats } )
}
sub logit {
	my ($category, $level, @message) = @_;
	return unless $category;
	my $logger = get_logger($category);
	$logger->$level(@message);
}
sub logsub { logit('SUB','debug',$_[0]) }
	
1;
