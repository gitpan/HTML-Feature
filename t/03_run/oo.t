use strict;
use Test::More ( tests => 9 );
#use lib("../../lib");
use Path::Class;
use FindBin qw($Bin);
use HTML::Feature;


my $html;
my $f = HTML::Feature->new(enc_type => 'utf8');

for ( 'utf8.html', 'euc-jp.html', 'sjis.html' ){
    my $html = file("$Bin/data", $_)->slurp;
    my $result = $f->parse($html);
    is( $result->title(), "タイトル" );
    is( $result->desc(), "ディスクリプション" );
    is( $result->text(),  "ハローワールド" );
}

