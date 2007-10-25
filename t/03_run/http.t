use strict;

#use lib("../../lib");
use HTML::Feature;
use LWP::UserAgent;
use Scalar::Util qw(blessed);
use Test::More ( tests => 6 ); 

my $url = 'http://www.cpan.org';

my $ua = LWP::UserAgent->new;
$ENV{'http_proxy'} and $ua->proxy( ['http'], $ENV{'http_proxy'} );
my $res  = $ua->get($url);
my $html = $res->content;
$html = 0;
if($html){
    my $f = HTML::Feature->new( enc_type => 'utf8' );
    is( $f->parse($html)->title,         "CPAN" );
    is( $f->parse($res)->title,          "CPAN" );
    is( $f->parse($url)->title,          "CPAN" );
    is( $f->parse_html($html)->title,    "CPAN" );
    is( $f->parse_response($res)->title, "CPAN" );
    is( $f->parse_url($url)->title,      "CPAN" );
}
else{
    use_ok('HTML::Feature');
    use_ok('HTML::Feature');
    use_ok('HTML::Feature');
    use_ok('HTML::Feature');
    use_ok('HTML::Feature');
    use_ok('HTML::Feature');
    print "skip http test","\n";
}
