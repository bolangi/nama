use inc::Module::Install;

         # Define metadata
         name                'Audio-Ecasound-Multitrack';
		 version_from        'lib/Audio/Ecasound/Multitrack.pm';
		 perl_version_from   'lib/Audio/Ecasound/Multitrack.pm';
		 abstract_from       'scripts/nama';
		 install_script      'scripts/nama'; 
		 author_from         'scripts/nama';
		 license_from        'README';

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
