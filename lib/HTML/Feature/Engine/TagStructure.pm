package HTML::Feature::Engine::TagStructure;
use strict;
use warnings;
use base qw(HTML::Feature::Engine);
use HTML::TreeBuilder;
use Statistics::Lite qw(statshash);

sub run{
    my $self = shift;
    my $c = shift;
    $self->_tag_cleaning($c);
    $self->_score($c);
    return $self;
} 

sub _tag_cleaning {
    my $self = shift;
    my $c = shift;
    return unless $c->{html};
    # preprocessing
    $c->{html} =~ s{<!-.*?->}{}xmsg;
    $c->{html} =~ s{<script[^>]*>.*?<\/script>}{}xmgs;
    $c->{html} =~ s{&nbsp;}{ }xmg;
    $c->{html} =~ s{&quot;}{\'}xmg;
    $c->{html} =~ s{\r\n}{\n}xmg;
    $c->{html} =~ s{^\s*(.+)$}{$1}xmg;
    $c->{html} =~ s{^\t*(.+)$}{$1}xmg;
    # control code ( 0x00 - 0x1F, and 0x7F on ascii)
    for ( 0 .. 31 ) {
        my $control_code = '\x' . sprintf( "%x", $_ );
        $c->{html} =~ s{$control_code}{}xmg;
    }
    $c->{html} =~ s{\x7f}{}xmg;
}

sub _score {
    my $self = shift;
    my $c = shift;
    my $root = HTML::TreeBuilder->new;
    $root->parse( $c->{html} );

    my $data;

    if ( my $title = $root->find("title") ) {
        $self->{title} = $title->as_text;
    }

    if ( my $desc = $root->look_down( _tag => 'meta', name => 'description' ) )
    {
        my $string = $desc->attr('content');
        $string =~ s{<br>}{}xms;
        $self->{desc} = $string;
    }

    my $i = 0;
    my @ratio;
    my @depth;
    my @order;
    for my $node ( $root->look_down( "_tag", qr/body|center|td|div/i ) ) {

        my $html_length = bytes::length( $node->as_HTML );
        my $text        = $node->as_text;
        my $text_length = bytes::length($text);
        my $text_ration = $text_length / ( $html_length + 0.001 );

        next
          if (  $c->{max_bytes}
            and $c->{max_bytes} =~ /^[\d]+$/
            && $text_length > $c->{max_bytes} );
        next
          if (  $c->{min_bytes}
            and $c->{min_bytes} =~ /^[\d]+$/
            and $text_length < $c->{min_bytes} );

        my $a_count       = 0;
        my $a_length      = 0;
        my $option_count  = 0;
        my $option_length = 0;
        my %node_hash;

        $self->_walk_tree( $node, \%node_hash );

        $node_hash{a_length}      ||= 0;
        $node_hash{option_length} ||= 0;
        $node_hash{text}          ||= $text;

        next if $node_hash{text} !~ /[^ ]+/;

        $data->[$i]->{text} = $node_hash{text};

        push( @ratio,
            ( $text_length - $node_hash{a_length} - $node_hash{option_length} )
              * $text_ration );
        push( @depth, $node->depth() );

        $i++;
    }

    for ( 0 .. $i ) {
        push( @order, log( $i - $_ + 1 ) );
    }

    my %ratio = statshash @ratio;
    my %depth = statshash @depth;
    my %order = statshash @order;

    # avoid memory leak
    $root->delete();

    no warnings;

    my @sorted =
      sort { $data->[$b]->{score} <=> $data->[$a]->{score} }
      map {

        my $ratio_std =
          ( $ratio[$_] - $ratio{mean} ) / ( $ratio{stddev} + 0.001 );
        my $depth_std =
          ( $depth[$_] - $depth{mean} ) / ( $depth{stddev} + 0.001 );
        my $order_std =
          ( $order[$_] - $order{mean} ) / ( $order{stddev} + 0.001 );

        $data->[$_]->{score} = $ratio_std + $depth_std + $order_std;
        $_;
      } ( 0 .. $i );
    $data->[ $sorted[0] ]->{text} =~ s/ $//s;

    #for(@sorted){
    #    print $data->[$_]->{text};
    #    print "\n", "-" x 30, "\n";
    #}
    $self->{text} = $data->[ $sorted[0] ]->{text};

    if ( $c->{enc_type} ) {
        $self->{title} = Encode::encode( $c->{enc_type}, $self->{title} );
        $self->{desc}  = Encode::encode( $c->{enc_type}, $self->{desc} );
        $self->{text}  = Encode::encode( $c->{enc_type}, $self->{text} );
    }

}

sub _walk_tree {
    my $self          = shift;
    my $node          = shift;
    my $node_hash_ref = shift;

    if ( ref $node ) {
        if ( $node->tag =~ /p|br|hr|tr|ul|li|ol|dl|dd/ ) {
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

HTML::Feature::Engine::TagStructure - default Engine

=head1 SYNOPSIS

    use HTML::Feature;
    my $result = HTML::Feature->new()->parse($url);
    # this module is called on backend as default engine

=head1 METHODS

=head2 new()

=head2 run()

=cut
