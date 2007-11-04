use strict;

use lib("../../lib");
use HTML::Feature;
use Test::More ( tests => 1 ); 
use Path::Class;
use FindBin qw($Bin);

my $html = file("$Bin/data", 'utf8.html')->slurp;

my $f = HTML::Feature->new;
my $result = $f->parse($html);

isa_ok($result->{element}, 'HTML::Element');
