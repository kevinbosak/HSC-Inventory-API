#!/usr/local/www/perl/bin/perl

use warnings;
use strict;

use lib 'lib';

# Builds the databases from the schema and adds a test user

use Data::Dumper;
use DBI;
use DBIx::Class::Exception;
use HSC::Schema;
use Module::Load;
use Digest::SHA qw(sha256_hex);
use YAML;

my $username = 'hsc';
my $password = 'test';

my $config_yaml;
{
    open(my $CFG, '<', 'config.yml') or die 'Could not open config file';
    local $/;
    $config_yaml = <$CFG>;
    close $CFG;
}

my $config = Load($config_yaml);

my $schema_config = $config->{plugins}->{DBIC}->{hsc_inventory};
# FIXME: this don't work for some reason
load $schema_config->{schema_class};

my $schema = $schema_config->{schema_class}->connect($schema_config->{dsn}, $schema_config->{user}, $schema_config->{pass}, $schema_config->{options});
#my $schema = HSC::Schema->connect('DBI:mysql:database=hsc_inventory','hsc_inventory', undef, {mysql_enable_utf8 => 1});
$schema->deploy({ add_drop_table => 1 }, '.');

my $password_hash = sha256_hex($config->{password_salt} . $password);
$schema->resultset('User')->create({username => $username, password_hash => $password_hash}) or die "Could not create user: $@";
