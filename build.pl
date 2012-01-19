#!/usr/local/www/perl/bin/perl

use warnings;
use strict;

use lib 'lib';

use Data::Dumper;
use DBI;
use DBIx::Class::Exception;
use HSC::Schema;

my $schema = HSC::Schema->connect('DBI:mysql:database=hsc_inventory','hsc_inventory', undef, {mysql_enable_utf8 => 1});
$schema->deploy({ add_drop_table => 1 }, '.');
