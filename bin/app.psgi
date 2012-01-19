#!/usr/local/www/perl/bin/perl
use Dancer;
use hsc_inventory;
use Plack::Builder;

my $app1 = sub {
    my $env     = shift;
    my $request = Dancer::Request->new(env => $env);
    Dancer->dance($request);
};

#my $app = builder {
#    $app1;
#};
