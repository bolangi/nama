#! /usr/bin/env perl
use v5;
use strict;
use warnings;
 
use Module::Build;
 
my $build = Module::Build->new(
   module_name => 'Audio::Nama',
   dist_abstract => "multitrack recorder and digital audio workstation",
   dist_author => 'Joel Roth <joelz@pobox.com>',
   configure_requires => {
      'Module::Build' => '0.4004', # test_requires
   },
   requires => {
		'autodie'  => 0,
		'Data::Dumper::Concise' => 0,
		'Data::Section::Simple' => 0,
		'Event'  => 0,
		'File::Find::Rule'  => 0,
		'File::Copy'  => 0,
		'File::Copy::Link'  => 0,
		'File::HomeDir'  => 0,
		'File::Slurp'  => 0,
		'File::Temp'  => 0,
		'Git::Repository' => 0,
		'Graph'  => 0,
		'IO::Socket'  => 0,
		'IO::Select'  => 0,
		'IO::Async::Timer::Periodic' => 0,
		'IO::Async::Timer::Countdown' => 0,
		'IO::Async::Loop' => 0,
		'IO::Async::Loop::Select' => 0,
		'JSON::XS' => 0,
		'IPC::Open3'  => 0,
		'IPC::System::Simple' => 0,
		'List::Util' => 0,
		'List::MoreUtils' => 0,
		'Log::Log4perl' => 0,
		'Module::Load::Conditional'  => 0, 
		'Parse::RecDescent'  => 0,
		'Path::Tiny' => 0,
		'Role::Tiny' => 0,
		'SUPER' => 0,
		'Test2::Bundle::More' => 0,
		'Text::Diff'  => 0,
		'Text::Format'  => 0,
		'Text::Template' => 0,
		'Tickit::Async' => 0,
		'Tickit::Widget::Static' => 0,
		'Tickit::Widget::Entry' => 0,
		'Tickit::Widget::ScrollBox' => 0,
		'Tickit::Widget::VBox' => 0,
		'Tickit::Widget::Entry::Plugin::Completion' => 0,
		'Time::HiRes'  => 0,
		'Try::Tiny'  => 0,
		'YAML::Tiny'  => 0,
      'perl' => '5.036', 
   },
   test_requires => {
	  'Test2::Bundle::More' => 0,
   },
   license => 'perl',
   create_license => 0,
   create_readme  => 0,
);
 
$build->create_build_script;

