package HTML::Feature;
use strict;
use warnings;
use vars qw($VERSION $UserAgent $engine @EXPORT_OK);
use Exporter qw(import);
use Carp;
use HTTP::Response::Encoding;
use Encode::Guess;
use List::Util qw(first);
use Scalar::Util qw(blessed);
use UNIVERSAL::require;

$VERSION = '2.0.1';
@EXPORT_OK = qw(feature);

sub new {
    my $class = shift;
    my %arg   = @_;
    $class = ref $class || $class;
    my $self = bless \%arg, $class;

    $self->{enc_type} ||= 'utf8';

    return $self;
}

sub parse {
    my $self     = shift;
    my $arg_type = $self->_detect_arg(@_);
    if    ( $arg_type eq 'url' )      { $self->parse_url( $self->{url} ); }
    elsif ( $arg_type eq 'response' ) { $self->parse_response( $self->{res} ); }
    elsif ( $arg_type eq 'html' )     { $self->parse_html( $self->{html} ); }
    else                              { croak("bad argument"); }
}

sub parse_url {
    my $self = shift;
    my $url  = shift;
    my $ua   = $self->_user_agent();
    my $res  = $ua->get($url);
    $self->parse_response($res);
}

sub parse_response {
    my $self = shift;
    my $res  = shift;
    $self->{res} = $res;
    $self->_run();
}

sub parse_html {
    my $self = shift;
    my $html = shift;
    $self->{html} = $html;
    $self->_run();
}

sub _run {
    my $self = shift;
    $self->_detect_enc();
    $engine ||= do {
        my $engine_module = $self->{engine} ? $self->{engine} : 'TagStructure';
        my $class = __PACKAGE__ . '::Engine::' . $engine_module;
        $class->require or die $@;
        $class->new;
    };
    $engine->run($self);
}

sub _detect_arg {
    my $self = shift;
    my $argc = @_;
    if ( $argc < 0 ) {
        die "parse() needs more than one params";
    }
    delete $self->{url}  if defined $self->{url};
    delete $self->{res}  if defined $self->{res};
    delete $self->{html} if defined $self->{html};
    my $return;
    my $arg = shift;
    if ( $arg eq 'url' ) {
        $self->{url} = shift;
        $return = 'url';
    }
    elsif ( $arg eq 'string' ) {
        $self->{html} = shift;
        $return = 'html';
    }
    else {
        if ( ( blessed $arg) and qw/HTTP::Response/ ) {
            $self->{res} = $arg;
            $return = 'response';
        }
        elsif ( $arg =~ /^http/ ) { $self->{url}  = $arg; $return = 'url'; }
        else                      { $self->{html} = $arg; $return = 'html'; }
    }
    my $param = shift;
    if ( ref $param eq 'HASH' ) {
        while ( my ( $key, $value ) = each %$param ) {
            $self->{$key} = $value;
        }
    }
    return $return;
}

sub _detect_enc {
    my $self = shift;
    if ( my $res = $self->{res} ) {
        if ( $res->is_success ) {
            my @encoding = (
                $res->encoding,

           # could be multiple because HTTP response and META might be different
                ( $res->header('Content-Type') =~ /charset=([\w\-]+)/g ),
                "latin-1",
            );
            my $encoding =
              first { defined $_ && Encode::find_encoding($_) } @encoding;
            $self->{html} = Encode::decode( $encoding, $res->content );
        }
    }
    else {
        my $html = $self->{html};
        $Encode::Guess::NoUTFAutoGuess = 1;
        my $guess =
          Encode::Guess::guess_encoding( $html,
            ( 'shiftjis', 'euc-jp', '7bit-jis', 'utf8' ) );
        unless ( ref $guess ) {
            $html = Encode::decode( "latin-1", $html );
        }
        else {
            eval { $html = $guess->decode($html); };
        }
        $self->{html} = $html;
    }
}

sub _user_agent {
    my $self = shift;
    require LWP::UserAgent;
    $UserAgent ||= LWP::UserAgent->new();
    return $UserAgent;
}

sub feature {
    my $self   = __PACKAGE__->new;
    my $result = $self->parse(@_);
    my %ret    = (
        text  => $result->text,
        title => $result->title,
        desc  => $result->desc
    );
    return wantarray ? %ret : $ret{text};
}

sub extract {
    warn
"HTML::Feature::extract() has been deprecated. Use HTML::Feature::parse() instead";
    my $self   = shift;
    my $result = $self->parse(@_);
    my $ret    = {
        title       => $result->title,
        description => $result->desc,
        block       => [ { contents => $result->text } ],
    };
    return $ret;
}

1;

__END__

=head1 NAME

HTML::Feature - Extract Feature Sentences From HTML Documents

=head1 SYNOPSIS

    use HTML::Feature;

    my $f = HTML::Feature->new(enc_type => 'utf8');
    my $result = $f->parse('http://www.perl.com');

    # or $f->parse($html);

    print "Title:"        , $result->title(), "\n";
    print "Description:"  , $result->desc(),  "\n";
    print "Featured Text:", $result->text(),  "\n";



    # a simpler method is, 

    use HTML::Feature;
    print feature('http://www.perl.com');

    # very simple!


=head1 DESCRIPTION 

This module extracst blocks of feature sentences out of an HTML document. 

Unlike other modules that performs similar tasks, this module by default
extracts blocks without using morphological analysis, and instead it uses 
simple statistics processing. 

Because of this, HTML::Feature has an advantage over other similar modules 
in that it can be applied to documents in any language.

=head1 METHODS 

=head2 new()

    my $f = HTML::Feature->new(%param);
    my $f = HTML::Feature->new(
        engine => $class, # backend engine module (default: 'TagStructure') 
        max_bytes => 5000, # max number of bytes per node to analyze (default: '')
        min_bytes => 10, # minimum number of bytes per node to analyze (default is '')
        enc_type => 'euc-jp', # encoding of return values (default: 'utf-8')
   );

Instantiates a new HTML::Feature object. Takes the following parameters

=over 4

=item engine

Specifies the class name of the engine that you want to use.

HTML::Feature is designed to accept different engines to change its behavior.
If you want to customize the behavior of HTML::Feature, specify your own
engine in this parameter

=back 

The rest of the arguments are directly passed to the HTML::Feature::Engine 
object constructor.

=head2 parse()

    my $result = $f->parse($url);
    # or
    my $result = $f->parse($html);
    # or
    my $result = $f->parse($http_response);

Parses the given argument. The argument can be either a URL, a string of HTML,
or an HTTP::Response object. HTML::Feature will detect and delegate to the
appropriate method (see below)

=head2 parse_url($url)

Parses an URL. This method will use LWP::UserAgent to fetch the given url.

=head2 parse_html($html)

Parses a string containing HTML.

=head2 parse_response($http_response)

Parses an HTTP::Response object.

=head2 extract()

    $data = $f->extract(url => $url);
    # or
    $data = $f->extract(string => $html);

HTML::Feature::extract() has been deprecated and exists for backwards compatiblity only. Use HTML::Feature::parse() instead.

extract() extracts blocks of feature sentences from the given document,
and returns a data structure like this:

    $data = {
        title => $title,
        description => $desc,
        block => [
            {
                contents => $contents,
                score => $score
            },
            .
            .
        ]
    }

=head2 feature

feature() is a simple wrapper that does new(), parse() in one step.
If you do not require complex operations, simply calling this will suffice.
In scalar context, it returns the feature text only. In list context,
some more meta data will be returned as a hash.

This function is exported on demand.

    use HTML::Feature qw(feature);
    print scalar feature($url);  # print featured text

    my %data = feature($url); # wantarray(hash)
    print $data{title};
    print $data{desc};
    print $data{text};


=head1 AUTHOR 

Takeshi Miki <miki@cpan.org> 

Special thanks to Daisuke Maki

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 Takeshi Miki This library is free software; you can redistribute it and/or modifyit under the same terms as Perl itself, either Perl version 5.8.8 or,at your option, any later version of Perl 5 you may have available.

=cut
