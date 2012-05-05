# ----------- Logging ------------

package ::;
use Carp;

sub initialize_logger {

	my $layout = "[\%R] %m%n"; # backslash to protect from source filter
	my $logfile = $ENV{NAMA_LOGFILE};
	my $appender = $logfile ? 'FILE' : 'STDERR';
	my $conf = qq(
		#log4perl.rootLogger			= DEBUG, IAM
		#log4perl.category.ECI			= DEBUG, IAM, IAM_file
		log4perl.category.ECI			= DEBUG, $appender

		# screen appender
		log4perl.appender.STDERR		= Log::Log4perl::Appender::Screen
		log4perl.appender.STDERR.layout	= Log::Log4perl::Layout::PatternLayout
		log4perl.appender.STDERR.layout.ConversionPattern = $layout

		# file appender
		log4perl.appender.FILE		= Log::Log4perl::Appender::File
		log4perl.appender.FILE.filename	= $logfile
		log4perl.appender.FILE.layout	= Log::Log4perl::Layout::PatternLayout
		log4perl.appender.FILE.layout.ConversionPattern = $layout

		#log4perl.additivity.IAM			= 0 # doesn't work... why?
	);
	Log::Log4perl::init(\$conf);

}
sub log_eci_cmd {
	my $cmd = shift;
	my $cat = 'ECI';
	log_msg({
		category 	=> $cat,
		cmd			=> $cmd,
	});
}
sub logit {
	my ($category, $level, $message) = @_;
	my $logger = get_logger($category);
	$logger->$level($message);
}
	
sub log_eci_result {
	my $msg = shift;
	my $cat = 'ECI';
	log_msg({
		category 	=> $cat,
		result 		=> $msg,
	});
}
sub log_eci {
	my $msg = shift;
}
	

sub log_msg {
	my $log = shift;
	if ( $log )
	{
		my $category 	= $log->{category};
		my $level		= $log->{level} || 'debug';
		my $msg			= $log->{msg};
		my $cmd			= $log->{cmd};
		my $result		= $log->{result}; 
		my $logger = ref $category 
			? $category 
			: Log::Log4perl->get_logger($category);
		my @msg;
		push @msg, "command: $cmd" if $cmd;
		push @msg, "message: $msg" if $msg;
		push @msg, "result: $result" if $result;
		my $message = join q(, ), @msg;
		$logger->$level($message);
	}
}
1;
