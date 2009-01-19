use inc::Module::Install;

         # Define metadata
         name                'Audio-Ecasound-Multitrack';
		 all_from            'lib/Audio/Ecasound/Multitrack.pm';
		 license_from        'README';
		 install_script      'script/nama'; 

         # Specific dependencies
		
requires
		Carp => 0,
		Cwd => 0,
		Storable => 0,
		Getopt::Std => 0,
		Audio::Ecasound => 0,
		Tk => 0,
		IO::All => 0,
		Parse::RecDescent => 0,
		Term::ReadLine => 0,
		Term::ReadLine::Gnu => 0,
		Data::YAML => 0,
		File::Find::Rule => 0,
		File::Spec::Link => 0,
		Time::HiRes => 0,
		Event => 0,
		;

         WriteAll;
