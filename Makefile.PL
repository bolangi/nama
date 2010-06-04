use inc::Module::Install;

         # Define metadata
         name                'Audio-Nama';
		 all_from            'lib/Audio/Nama.pm';
         license             'perl';
		 install_script      'script/nama'; 

         # Specific dependencies
         
         requires
		
		autodie => 0,
		AnyEvent => 5.0,
		Data::Section =>0,
		Event => 0,
		File::Find::Rule => 0,
		File::Copy::Link => 0,
		File::Temp => 0,
		Graph => 0,
		IO::All => 0,
		IO::Socket => 0,
		Modern::Perl => 0,
		Module::Load::Conditional => 0, 
		Parse::RecDescent => 0,
		Term::ReadLine::Gnu => 0,
		Text::Format => 0,
		Time::HiRes => 0,
		YAML::Tiny => 0,
		;
        WriteAll;
