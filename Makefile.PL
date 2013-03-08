use inc::Module::Install;

         # Define metadata
         name                'Audio-Nama';
		 version_from        'lib/Audio/Nama.pm';
		 all_from            'script/nama';
         license             'gpl';
		 install_script      'script/nama'; 
	 keywords
	        'audio',
	        'recording',
	        'mixing',
	        'daw';
	 repository
	        'https://github.com/bolangi/nama';

         # Specific dependencies
         
         requires
		
		qw(
			autodie  0
			AnyEvent  5.0
			Data::Dumper::Concise 0
			Data::Section::Simple 0
			Event  0
			File::Find::Rule  0
			File::Copy  0
			File::Copy::Link  0
			File::HomeDir  0
			File::Slurp  0
			File::Temp  0
			Git::Repository 0
			Graph  0
			IO::Socket  0
			IO::Select  0
			JSON::XS	0
			IPC::Open3  0
			List::Util 0
			Log::Log4perl 0
			Modern::Perl  0
			Module::Load::Conditional  0 
			Parse::RecDescent  0
			Term::ReadLine::Gnu  0
			Text::Format  0
			Time::HiRes  0
			Try::Tiny  0
			YAML::Tiny  0
		);
        WriteAll;

