BUILD INSTRUCTIONS
    You may decide to clone the Nama's github repository and from source
    rather than installing from CPAN. It is easier to browse or hack on
    Nama this way. Functionality is separated into a number of files, and
    you will see $::package_var instead of $Audio::Nama::package_var.

    You can get also updates more quickly and can share patches with other
    developers.

  Procedure
    For typical build and test:

            cpan Text::Template
            git-clone git://github.com/bolangi/nama.git
            cd nama/src
            ./build
            ./ui

    To install the module, do as usual:

            cd ..
            perl Makefile.PL
            make install

  How it works
    The build script creates the perl modules for the distribution under the
    nama/lib directory using *.p, *.pl, *.t and other files in the nama/src
    directory.

    build looks into the *.p files for lines that look like:

        [% somefile.pl %]

    This notation is analogous to the C-preprocessor #include directive:
    somefile.pl gets included in the source at that point. Some of these
    include lines are more complicated:

        [% qx(./strip_comments ./grammar_body) %]

    Here the preprocessor runs the script strip_comments on grammar_body,
    removing text that would choke the parser generator.

    Build provides a few parameters to the preprocessing script preproc,
    which uses the Text::Template to perform most of the required
    substitutions.

    To see the names of the files and scripts used to build the modules
    type:

            ls *.p        
            grep '\[%' *  # shows all include directives

