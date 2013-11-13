package MooX::Cmd::Role;
BEGIN {
  $MooX::Cmd::Role::AUTHORITY = 'cpan:GETTY';
}
{
  $MooX::Cmd::Role::VERSION = '0.008';
}
# ABSTRACT: MooX cli app commands do this

use strict;
use warnings;

use Moo::Role;

use Carp;
use Module::Runtime qw/ use_module /;
use Regexp::Common;
use Data::Record;
use Module::Pluggable::Object;

use List::Util qw/first/;
use Scalar::Util qw/blessed/;
use Params::Util qw/_ARRAY/;


has 'command_args' => ( is => "ro" );


has 'command_chain' => ( is => "ro" );


has 'command_chain_end' => ( is => "lazy" );

sub _build_command_chain_end { $_[0]->command_chain->[-1] }


has 'command_name' => ( is => "ro" );


has 'command_commands' => ( is => "lazy" );

sub _build_command_commands
{
	my ($class, $params) = @_;
	defined $params->{command_base} or $params->{command_base} = $class->_build_command_base($params);
	my $base = $params->{command_base};

	# i have no clue why 'only' and 'except' seems to not fulfill what i need or are bugged in M::P - Getty
	my @cmd_plugins = grep {
		my $plug_class = $_;
		$plug_class =~ s/${base}:://;
		$plug_class !~ /:/;
	} Module::Pluggable::Object->new(
		search_path => $base,
		require => 0,
	)->plugins;

	my %cmds;

	for my $cmd_plugin (@cmd_plugins) {
		$cmds{_mkcommand($cmd_plugin,$base)} = $cmd_plugin;
	}

	\%cmds;
}


has command_base => ( is => "lazy" );

sub _build_command_base
{
    my $class = blessed $_[0] || $_[0];
    return $class . '::Cmd'
}


has command_execute_method_name => ( is => "lazy" );

sub _build_command_execute_method_name { "execute" }


has command_execute_return_method_name => ( is => "lazy" );

sub _build_command_execute_return_method_name { "execute_return" }


has command_creation_method_name => ( is => "lazy" );

sub _build_command_creation_method_name { "new_with_cmd" }


has command_creation_chain_methods => ( is => "lazy" );

sub _build_command_creation_chain_methods { ['new_with_options','new'] }


has command_execute_from_new => ( is => "lazy" );

sub _build_command_execute_from_new { 0 }


sub new_with_cmd { goto &_initialize_from_cmd; }

sub _mkcommand {
	my ( $package, $base ) = @_;
	$package =~ s/^${base}:://g;
	lc($package);
}

my @private_init_params = qw(command_base command_execute_method_name command_execute_return_method_name command_creation_chain_methods command_execute_method_name);

my $required_method = sub {
	my ($tgt, $method) = @_;
	$tgt->can($method) or croak("You need an '$method' in " . (blessed $tgt || $tgt));
};

my $call_required_method = sub {
	my ($tgt, $method, @args) = @_;
	my $m = $required_method->($tgt, $method);
	return $m->($tgt, @args);
};

my $call_optional_method = sub {
	my ($tgt, $method, @args) = @_;
	my $m = $tgt->can($method) or return;
	return $m->($tgt, @args);
};

my $call_indirect_method = sub {
	my ($tgt, $name_getter, @args) = @_;
	my $g = $call_required_method->($tgt, $name_getter);
	my $m = $required_method->($tgt, $g);
	return $m->($tgt, @args);
};

sub _initialize_from_cmd
{
	my ( $class, %params ) = @_;

	my $opts_record = Data::Record->new({
		split  => qr{\s+},
		unless => $RE{quoted},
	});

	my @args = $opts_record->records(join(' ',@ARGV));
	my (@used_args, $cmd, $cmd_name);

	my %cmd_create_params = %params;
	delete @cmd_create_params{qw(command_commands), @private_init_params};

	defined $params{command_commands} or $params{command_commands} = $class->_build_command_commands(\%params);
	while (my $arg = shift @args) {
		push @used_args, $arg and next unless $cmd = $params{command_commands}->{$arg};

		$cmd_name = $arg; # be careful about relics
		use_module( $cmd );
		defined $cmd_create_params{command_execute_method_name}
		  or $cmd_create_params{command_execute_method_name} = $call_optional_method->($cmd, "_build_command_execute_method_name", \%cmd_create_params);
		defined $cmd_create_params{command_execute_method_name} 
		  or $cmd_create_params{command_execute_method_name} = "execute";
		$required_method->($cmd, $cmd_create_params{command_execute_method_name});
		last;
	}

	defined $params{command_creation_chain_methods} or $params{command_creation_chain_methods} = $class->_build_command_creation_chain_methods(\%params);
	my @creation_chain = _ARRAY($params{command_creation_chain_methods}) ? @{$params{command_creation_chain_methods}} : ($params{command_creation_chain_methods});
	my $creation_method_name = first { defined $_ and $class->can($_) } @creation_chain;
	croak "Can't find a creation method on " . $class unless $creation_method_name;
	my $creation_method = $class->can($creation_method_name); # XXX this is a perfect candidate for a new function in List::MoreUtils

	@ARGV = @used_args;
	$params{command_args} = [ @args ];
	$params{command_name} = $cmd_name;
	defined $params{command_chain} or $params{command_chain} = [];
	my $self = $creation_method->($class, %params);
	$cmd and push @{$self->command_chain}, $self;

	my @execute_return;

	defined $params{command_execute_return_method_name}
	  or $params{command_execute_return_method_name} = $class->_build_command_execute_return_method_name(\%params);
	if ($cmd) {
		@ARGV = @args;
		my ($creation_method,$creation_method_name,$cmd_plugin);
		$cmd->can("_build_command_creation_method_name") and $creation_method_name = $cmd->_build_command_creation_method_name(\%params);
		$creation_method_name and $creation_method = $cmd->can($creation_method_name);
		if ($creation_method) {
			@cmd_create_params{qw(command_chain)} = @params{qw(command_chain)};
			$cmd_plugin = $creation_method->($cmd, %cmd_create_params);
			@execute_return = @{ $call_indirect_method->($cmd_plugin, "command_execute_return_method_name") };
		} else {
			$creation_method_name = first { $cmd->can($_) } @creation_chain;
			croak "Can't find a creation method on " . $cmd unless $creation_method_name;
			$creation_method = $cmd->can($creation_method_name); # XXX this is a perfect candidate for a new function in List::MoreUtils
			$cmd_plugin = $creation_method->($cmd);
			defined $params{command_execute_from_new} or $params{command_execute_from_new} = $class->_build_command_execute_from_new(\%params);
			$params{command_execute_from_new}
			  and @execute_return = $call_required_method->($cmd_plugin, $cmd_create_params{command_execute_method_name}, \@ARGV, $self->command_chain);
		}
	} else {
		$self->command_execute_from_new
		  and @execute_return = $call_indirect_method->($self, "command_execute_method_name", \@ARGV, $self->command_chain);
	}

	$self->{$params{command_execute_return_method_name}} = \@execute_return;

	return $self;
}


# XXX should be an r/w attribute - can be renamed on loading ...
sub execute_return { $_[0]->{execute_return} }

1;

__END__

=pod

=head1 NAME

MooX::Cmd::Role - MooX cli app commands do this

=head1 VERSION

version 0.008

=head1 SYNOPSIS

=head2 using role and want behavior as MooX::Cmd

  package MyFoo;
  
  with MooX::Cmd::Role;
  
  sub _build_command_execute_from_new { 1 }

  package main;

  my $cmd = MyFoo->new_with_cmd;

=head2 using role and don't execute immediately

  package MyFoo;

  with MooX::Cmd::Role;
  use List::MoreUtils qw/ first_idx /;

  sub _build_command_base { "MyFoo::Command" }

  sub _build_command_execute_from_new { 0 }

  sub execute {
      my $self = shift;
      my $chain_idx = first_idx { $self == $_ } @{$self->command_chain};
      my $next_cmd = $self->command_chain->{$chain_idx+1};
      $next_cmd->owner($self);
      $next_cmd->execute;
  }

  package main;

  my $cmd = MyFoo->new_with_cmd;
  $cmd->command_chain->[-1]->run();

=head2 explicitely expression of some implicit stuff

  package MyFoo;

  with MooX::Cmd::Role;

  sub _build_command_base { "MyFoo::Command" }

  sub _build_command_execute_method_name { "run" }

  sub _build_command_execute_from_new { 0 }

  package main;

  my $cmd = MyFoo->new_with_cmd;
  $cmd->command_chain->[-1]->run();

=head1 DESCRIPTION

MooX::Cmd::Role is made for modern, flexible Moo style to tailor cli commands.

=head1 ATTRIBUTES

=head2 command_args

ARRAY-REF of args on command line

=head2 command_chain

ARRAY-REF of commands lead to this instance

=head2 command_chain_end

COMMAND accesses the finally detected command in chain

=head2 command_name

ARRAY-REF the name of the command lead to this command

=head2 command_commands

HASH-REF names of other commands 

=head2 command_base

STRING base of command plugins

=head2 command_execute_method_name

STRING name of the method to invoke to execute a command, default "execute"

=head2 command_execute_return_method_name

STRING I have no clue what that is goood for ...

=head2 command_creation_method_name

STRING name of constructor

=head2 command_creation_chain_methods

ARRAY-REF names of methods to chain for creating object (from L</command_creation_method_name>)

=head2 command_execute_from_new

BOOL true when constructor shall invoke L</command_execute_method_name>, false otherwise

=head1 METHODS

=head2 new_with_cmd

initializes by searching command line args for commands and invoke them

=head2 execute_return

returns the content of $self->{execute_return}

=head1 AUTHOR

Torsten Raudssus <torsten@raudss.us>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Torsten Raudssus.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut