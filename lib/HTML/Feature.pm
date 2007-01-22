package HTML::Feature;

use strict;
use warnings;
use Carp;
use version; our $VERSION = qv('0.2.0');

use LWP::Simple;
use HTML::TokeParser;
use HTML::Entities;
use Statistics::Lite qw(mean);
use Encode;
use Encode::Guess;

sub new {
    my $class = shift;
    my %arg   = @_;
    $class = ref $class || $class;
    my $self = bless \%arg, $class;

    # initialize
    $self->_initialize();

    return $self;
}

sub extract {
    my $self = shift;
    my %arg  = @_;

    # undefined data
    undef $self->{ret};
    undef $self->{html};
    undef $self->{blocks};

    # catch url or string
    $self->{html} = defined $arg{string} ? $arg{string} : get( $arg{url} );

    # guess encodings
    $self->_guess_enc();

    # tag cleaning
    $self->_tag_cleaning();

    # split data
    $self->_split();

    # score
    $self->_score();

    return $self->{ret};
}

sub _initialize {
    my $self = shift;

    # set defaule value
    $self->{tag_score} ||= {
        a      => 0.85,
        option => 0.5,
        b      => 1.15,
        strong => 1.15,
        h1     => 2,
        h2     => 1.8,
        h3     => 1.5
    };
    $self->{string_score} ||= {
        'copyright'           => 0.65,
        'all rights reserved' => 0.65
    };
    $self->{ret_num} ||= 1;
    $self->{suspects_enc} ||= [ 'euc-jp', 'shiftjis', '7bit-jis', ];
}

sub _score {
    my $self = shift;

    # score calculation every tag blocks
    my @scored =
      sort { $b->{score} <=> $a->{score} }
      map {
        my $block;
        my $score   = 1;
        my $p       = HTML::TokeParser->new( \$_ );
        my @tags    = keys( %{ $self->{tag_score} } );
        my @strings = keys( %{ $self->{string_score} } );
        while ( my $token = $p->get_token ) {
            $block->{contents} .= $token->[1] if $token->[0] eq 'T';
            for my $tag (@tags) {
                if ( $token->[0] eq 'S' && $token->[1] eq $tag ) {
                    my $text = $p->get_text;
                    if ( $text =~ m{.+} ) {
                        $block->{contents} .= $text;
                        $score = $score * $self->{tag_score}->{$tag};
                        $block->{match_tags}->{$tag}++;
                    }
                }
            }
        }
        $block->{length} = bytes::length( $block->{contents} );
        $block->{score}  = $block->{length} * $score;
        for my $string (@strings) {
            my $quotemeta = quotemeta($string);
            if ( defined( $block->{contents} ) ) {
                while ( $block->{contents} =~ m{($quotemeta)}xmsig ) {
                    $block->{score} =
                      $block->{score} * $self->{string_score}->{$string};
                    $block->{match_string}->{$string}++;
                }
            }
        }
        $block;
      } @{ $self->{blocks} };

    # set return data
    $self->{ret} = {
        'title'       => $self->{title},
        'description' => $self->{description},
        'block'       => [ @scored[ 0 .. ( $self->{ret_num} - 1 ) ] ]
    };

}

sub _split {
    my $self = shift;

    # calculate the average number of an empty line
    my $count = 0;
    my @n;
    return unless $self->{html};
    for ( split( /\n/, $self->{html} ) ) {
        if ( $_ =~ /./ ) {
            if ( $count > 0 ) { push( @n, $count ); }
            $count = 0;
        }
        else {
            $count++;
        }
    }
    my $average = sprintf( "%.0f", mean(@n) );
    $average ||= 1;

    # set boundary and split contents
    my $boundary = "\n" x $average;
    $self->{blocks} = [ split( /$boundary/, $self->{html} ) ];
}

sub _tag_cleaning {
    my $self = shift;

    return unless $self->{html};

    # preprocessing
    $self->{html} =~ s{<script.*?</script>}{}xmsig;
    $self->{html} =~ s{<style.*?</style>}{}xmsig;
    $self->{html} =~ s{<!-.*?->}{}xmsg;
    $self->{html} =~ s{&nbsp;}{ }xmsg;
    $self->{html} =~ s{&quot;}{\'}xmg;
    $self->{html} =~ s{\r\n}{\n}xmg;
    $self->{html} =~ s{^\s*(.+)$}{$1}xmg;
    $self->{html} =~ s{^\t*(.+)$}{$1}xmg;

    # LineFeed_counter
    my $lf_cnt;
    while ( $self->{html} =~ m{(\n)}xmgs ) {
        $lf_cnt++;
    }

    # parse and pickup tag (scored tag)
    my $p = HTML::TokeParser->new( \( $self->{html} ) );
    my $html;
    my @tags = keys( %{ $self->{tag_score} } );
    while ( my $token = $p->get_token ) {
        if ( $token->[0] eq 'S' && $token->[1] eq "title" ) {
            $self->{title} = $p->get_trimmed_text;
        }
        if ( $token->[0] eq 'S' && $token->[1] eq "meta" ) {
            if ( defined( $token->[2]->{name} ) ) {
                if ( $token->[2]->{name} eq 'description' ) {
                    $self->{description} = $token->[2]->{content};
                }
            }
        }
        for (@tags) {
            if ( $token->[0] eq 'S' && $token->[1] eq $_ ) {
                $html .= $token->[4];
                $html .= encode_entities( $p->get_trimmed_text, "<>&" );
            }
            if ( $token->[0] eq 'E' && $token->[1] eq $_ ) {
                $html .= $token->[2];
            }
        }
        $html .= encode_entities( $p->get_text, "<>&" );
        $html .= "\n" unless $lf_cnt;
    }
    $html =~ s{\[IMG\]}{}xmsig;
    $self->{html} = $html;
}

sub _guess_enc {
    my $self = shift;

    my $html = $self->{html};

    $Encode::Guess::NoUTFAutoGuess = 1;

    my $guess =
      Encode::Guess::guess_encoding( $html, @{ $self->{suspects_enc} } );
    unless ( ref $guess ) {
        warn "no match UNICODE";
        $html = "";
    }
    else {
        eval { $html = $guess->decode($html); };
    }
    $self->{html} = $html;
}

1;

__END__

=head1 NAME

HTML::Feature - an extractor of feature sentence from HTML 

=head1 SYNOPSIS

    use strict;
    use HTML::Feature;
    use Data::Dumper;
    use Encode;
    binmode STDOUT, ':encoding(utf-8)';

    my $f = HTML::Feature->new;
    my $data = $f->extract( url => 'http://www.perl.com' );

    # print result data

    my $boundary = "-" x 40;

    print "\n";
    print $boundary, "\n";
    print "* TITLE:\n";
    print $boundary, "\n";
    print $data->{title}, "\n";

    print "\n";
    print $boundary, "\n";
    print "* DESCRIPTION:\n";
    print $boundary, "\n";
    print $data->{description}, "\n";

    my $i = 0;
    for(@{$data->{block}}){
        $i++;
        print "\n";
        print $boundary, "\n";
        print "* CONTENTS-$i:\n";
        print $boundary, "\n";
        print $_->{contents}, "\n";
        print $boundary, "\n";
        print "SCORE:",$_->{score},"\n";
    }

    # print more details
    print Dumper($data);


=head1 DESCRIPTION

This module extracts some feature sentence from HTML.

First, HTML document is divided into plural blocks by a certain boundary line. 

And each blocking is evaluated individually. 

Evaluation of each block is decided by document size (the number of bytes) and a coefficient of a tag.

Being optional, arbitrary value can set a coefficient of a tag.

By the way, this module is not designed to extract a feature sentence from a page such as a list of links(for example, top pages of portal site).  

It may extract well a feature sentence from a page with quantity of some document, (for example, news peg or blog) .

=head1 METHODS

=over 4

=item new([options])

a object is made by using the options.

=item extract(url => $url | string => $string)

return feature blocks with TITLE and DESCRIPTION.

=head1 OPTIONS

    # it is possible to transfer default value to the constructor
    my $f = HTML::Feature->new(
        # set defaule value
        $self->{tag_score} ||= {
            a      => 0.85,
            option => 0.5,
            b      => 1.15,
            strong => 1.15,
            h1     => 2,
            h2     => 1.8,
            h3     => 1.5
        };
        $self->{string_score} ||= {
            'copyright'     => 0.65,
            'all rights reserved' => 0.65
        };
        $self->{ret_num} ||= 1;
        $self->{suspects_enc} ||= [ 'euc-jp', 'shiftjis', '7bit-jis', ];
    );


=head1 SEE ALSO

L<HTML::TokeParser>,L<HTML::Entites>,L<Encode::Guess>


=head1 AUTHOR

Takeshi Miki <miki@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 Takeshi Miki 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

