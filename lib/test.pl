#!/usr/bin/perl

use warnings;
use strict;

use Digest::SHA qw(sha256_hex);
use MIME::Base64 qw(encode_base64url);

my $password_salt = "fjk&da;325!qwkl;ejqk;";
my $token_salt = "f324q/mmanwelqw3j234!";

my $rand = int(rand(time)*100);
warn "RAND: $rand";

#my $token = encode_base64url(sha256_hex($token_salt) . 'some long username' . $rand);
my $token = encode_base64url('some long username' . $rand);
warn $token;
warn length($token);
