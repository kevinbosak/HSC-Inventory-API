#!/usr/local/www/perl/bin/perl

use warnings;
use strict;

use lib 'lib/';
use Module::Load;
#use HSC::Schema;
use Digest::SHA qw(sha256_hex);
use MIME::Base64 qw(encode_base64url);
use YAML;
use Getopt::Long;

my ($username, $password, $update);

my $result = GetOptions(
        'username=s' => \$username,
        'password=s' => \$password,
        'update' => \$update,
);

die "Must specify username and password" unless $username && $password;

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
my $password_hash = sha256_hex($config->{password_salt} . $password);
my $existing = $schema->resultset('User')->find($username);
die "User already exists" if $existing && !$update;
$schema->resultset('User')->create({username => $username, password_hash => $password_hash}) or die "Could not create user: $@";
