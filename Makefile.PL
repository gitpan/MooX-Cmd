
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Giving an easy Moo style way to make command organized CLI apps",
  "AUTHOR" => "Torsten Raudssus <torsten\@raudss.us>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "MooX-Cmd",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "MooX::Cmd",
  "PREREQ_PM" => {
    "Data::Record" => "0.02",
    "Module::Pluggable" => "4.8",
    "Moo" => "0.009013",
    "Package::Stash" => "0.33",
    "Regexp::Common" => "2011121001"
  },
  "TEST_REQUIRES" => {
    "Test::LoadAllModules" => "0.021",
    "Test::More" => "0.98"
  },
  "VERSION" => "0.008",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "Data::Record" => "0.02",
  "Module::Pluggable" => "4.8",
  "Moo" => "0.009013",
  "Package::Stash" => "0.33",
  "Regexp::Common" => "2011121001",
  "Test::LoadAllModules" => "0.021",
  "Test::More" => "0.98"
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



