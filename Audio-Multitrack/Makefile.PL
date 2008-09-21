use inc::Module::Install;

         # Define metadata
         name           'Audio-Ecasound-Multitrack';
         all_from       'scripts/nama';

         # Specific dependencies
		
requires
		Tk => 0,
		IO::All => 0,
		Carp => 0,
		Cwd => 0,
		Storable => 0,
		Getopt::Std => 0,
		Audio::Ecasound => 0,
		Parse::RecDescent => 0,
		Term::ReadLine => 0,
		Data::YAML => 0,
		File::Find::Rule => 0,
		File::Spec::Link => 0,
		;

         WriteAll;
