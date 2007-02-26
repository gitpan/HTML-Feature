package HTML::Feature;

use strict;
use warnings;
use LWP::Simple;
use Encode;
use Encode::Detect;
use HTML::TreeBuilder;
use Statistics::Lite qw(statshash);

our $VERSION = '1.0.2';

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
    $self->{html} = decode( "Detect", $self->{html} );

    # tag cleaning
    $self->_tag_cleaning();

    # score
    $self->_score();

    return $self->{ret};
}

sub _initialize {
    my $self = shift;

    # set defaule value
    $self->{ret_num}   ||= 1;
    $self->{enc_type}  ||= '';
    $self->{max_bytes} ||= '';
    $self->{min_bytes} ||= '';
}

sub _score {
    my $self = shift;

    my $root = HTML::TreeBuilder->new;
    $root->parse( $self->{html} );

    my $data;

    if ( my $title = $root->find("title") ) {
        $self->{ret}->{title} =
          $self->{enc_type}
          ? encode( $self->{enc_type}, $title->as_text )
          : $title->as_text;
    }

    if ( my $desc = $root->look_down( _tag => 'meta', name => 'description' ) )
    {
        my $string = $desc->attr('content');
        $string =~ s{<br>}{}xms;
        $self->{ret}->{description} =
          $self->{enc_type} ? encode( $self->{enc_type}, $string ) : $string;
    }

    my $i = 0;
    my @ratio;
    my @depth;
    my @order;
    for my $node ( $root->look_down( "_tag", qr/body|td|div/i ) ) {

        my @address     = split( /\./, $node->address() );
        my $text_length = bytes::length( $node->as_text );
        my $html_length = bytes::length( $node->as_HTML );
        my $text_ration = $text_length / $html_length;

        next
          if ( $self->{max_bytes} =~ /^[\d]+$/
            && $text_length > $self->{max_bytes} );
        next
          if ( $self->{min_bytes} =~ /^[\d]+$/
            && $text_length < $self->{min_bytes} );

        my $a_count       = 0;
        my $a_length      = 0;
        my $option_count  = 0;
        my $option_length = 0;

        my %node_hash;
        $self->_walk_tree( $node, \%node_hash );

        $node_hash{a_length}      ||= 0;
        $node_hash{option_length} ||= 0;
        $node_hash{text}          ||= '';

        next if $node_hash{text} !~ /[^ ]+/;

        $data->[$i]->{text}        = $node_hash{text};
        $data->[$i]->{text_length} = $text_length;

        push( @ratio,
            ( $text_length - $node_hash{a_length} - $node_hash{option_length} )
              * $text_ration );
        push( @depth, $#address + 1 );

        $i++;
    }

    for ( 0 .. $i ) {
        push( @order, log( $i - $_ + 1 ) );
    }

    my %ratio = statshash @ratio;
    my %depth = statshash @depth;
    my %order = statshash @order;

    no warnings;

    my @sorted =
      sort { $data->[$b]->{score} <=> $data->[$a]->{score} }
      map {
        my $ratio_std = ( $ratio[$_] - $ratio{mean} ) / ( $ratio{stddev} );
        my $depth_std = ( $depth[$_] - $depth{mean} ) / ( $depth{stddev} );
        my $order_std = ( $order[$_] - $order{mean} ) / ( $order{stddev} );
        $data->[$_]->{score}     = $ratio_std + $depth_std + $order_std;
        $data->[$_]->{ratio_std} = $ratio_std;
        $data->[$_]->{depth_std} = $depth_std;
        $data->[$_]->{order_std} = $order_std;
        $_;
      } ( 0 .. $i );

    $i = 0;
    for (@sorted) {
        $self->{ret}->{block}->[$i]->{contents} =
          $self->{enc_type}
          ? encode( $self->{enc_type}, $data->[$_]->{text} )
          : $data->[$_]->{text};
        $self->{ret}->{block}->[$i]->{score} =
          $self->{enc_type}
          ? encode( $self->{enc_type}, $data->[$_]->{score} )
          : $data->[$_]->{score};
        $i++;
        last if $i == $self->{ret_num};
    }
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
}

sub _walk_tree {
    my $self          = shift;
    my $node          = shift;
    my $node_hash_ref = shift;

    if ( ref $node ) {
        if ( $node->tag =~ /p|br|hr|tr|ul|li|ol|dl|dd/ ) {

            # print "\n";
            $node_hash_ref->{text} .= "\n";
        }
        if ( $node->tag eq 'a' ) {
            $node_hash_ref->{a_length} += bytes::length( $node->as_text );
        }
        if ( $node->tag eq 'option' ) {
            $node_hash_ref->{option_length} += bytes::length( $node->as_text );
        }
        $self->_walk_tree( $_, $node_hash_ref ) for $node->content_list();
    }
    else {
        $node_hash_ref->{text} .= $node . " ";
    }
}

1;

__END__

=head1 NAME

HTML::Feature - an extractor of feature sentence from HTML 

=head1 SYNOPSIS

    use strict;
    use HTML::Feature;

    my $f = HTML::Feature->new(
	enc_type => 'utf-8',
	ret_num => 10,
	max_bytes => 5000,
	min_bytes => 1
    );
    my $data = $f->extract( url => 'http://www.perl.com' );

    # print result data

    print $data->{title}, "\n";
    print $data->{description}, "\n";

    for(@{$data->{block}}){
        print $_->{score}, "\n";
        print $_->{contents}, "\n";
    }


=head1 DESCRIPTION

This module extracts some feature blocks from an HTML document. I do not adopt general technique such as "morphological analysis" in this module. 
By simpler statistics processing, this module will extract a feature blocks. So, it may be able to apply it in a language of any country easily.

=head1 METHODS

=over 4

=item new([options])

a object is made by using the options.

=item extract(url => $url | string => $string)

return feature blocks (references) with TITLE and DESCRIPTION.

=head1 OPTIONS

    # it is possible to set value to the constructor
    my $f = HTML::Feature->new(
        
	$self->{ret_num} = 1; 
	# number of return blocks (default is '1').
        
	$self->{max_bytes} = '5000'; 
	# The upper limit number of bytes of a node to analyze (default is '').
        
	$self->{min_bytes} = '10'; 
	# The bottom limit number (default is '').
        
	$self->{enc_type} = 'euc-jp'; 
	# An arbitrary character code, If there is not appointment in particular, I become the character code which an UTF-8 flag is with (default is '').
   );


=head1 SEE ALSO

L<HTML::TreeBuilder>,L<Statistics::Lite>,L<Encode::Detect>


=head1 AUTHOR

Takeshi Miki <miki@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 Takeshi Miki 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

