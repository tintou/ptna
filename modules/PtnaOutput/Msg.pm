package PtnaOutput::Msg;

#############################################################################################
#
# Messages: text which is not translated or formatted by the analysis but by the output stage.
#
# The analysis builds messages with the functions below. A message is a small data structure,
# it knows the (untranslated) msgid, the arguments and the typed values (foreign text,
# links to OSM objects) which are part of it. The output stage (PtnaOutput::Html, ...) calls
# render() with a set of handlers which tell how to translate and how to format those parts.
#
# Message hash references (blessed into this package) have a 'k' (kind):
#
#   tr          'id', 'plural', 'n'      translatable text: gettext() or ngettext()
#   fmt         'fmt', 'args'            sprintf( fmt, args ), 'fmt' is a plain string or a message
#   cat         'parts'                  concatenation (the '.' operator of messages)
#   join        'sep', 'items'           join()
#   foreign     'text'                   a value taken from OSM (e.g. a name), not translated
#   text        'text'                   plain text which has to be escaped by the output stage
#   anchor      'id', 'text'             link to a section of the page
#   relation    'link'                   link to a relation, see relation_link() in PtnaOutput::Html
#   way         'link'
#   node        'link'
#   inject      'id', 'kv'               link to inject tags into a relation using JOSM
#
# Anything which is not a message is plain text and is used as it is.
#
# Messages overload '.', so that 'text' . message . 'text' stays a message. Where a message is
# used in any other way (e.g. as a hash key or in a regular expression) it is rendered with the
# default handlers, i.e. translated at that moment. Set PTNA_MSG_TRACE to list those places.
#
#############################################################################################

use strict;
use warnings;

use Exporter;
use base qw (Exporter);

use utf8;

use Encode;
use Scalar::Util qw( blessed );
use Locale::gettext qw();

our @EXPORT_OK = qw( gettext ngettext msg jointext mkey unkey foreign text_msg anchor_msg relation_msg way_msg node_msg gtfs_msg gtfs_status_msg gtfs_compare_msg gtfs_scores_msg inject_msg issue_msg tags listed list_msg render to_data is_msg );

use overload
    '.'         => \&_concat,
    '""'        => \&_stringify,
    'bool'      => sub { 1 },
    'fallback'  => 1;


#############################################################################################

my $MORE_FORMAT = gettext( "%s: %s and %d more ..." );   # so that xgettext finds it

my %KEYED;
sub mkey {
    my ($m) = @_;
    my $k = "$m";
    $KEYED{$k} = $m if is_msg($m);
    return $k;
}

sub unkey {
    my ($k) = @_;
    return exists($KEYED{$k}) ? $KEYED{$k} : $k;
}

sub is_msg {
    my $v = shift;
    return blessed( $v ) && $v->isa( __PACKAGE__ );
}


#############################################################################################

sub _new {
    my %self = @_;
    return bless( \%self, __PACKAGE__ );
}


#############################################################################################

sub gettext {
    my $id = shift;
    return _new( 'k' => 'tr', 'id' => $id );
}


#############################################################################################

sub ngettext {
    my ( $id, $plural, $n ) = @_;
    return _new( 'k' => 'tr', 'id' => $id, 'plural' => $plural, 'n' => $n );
}


#############################################################################################
#
# like sprintf(), the result is a plain string as long as there is nothing to be translated
#
#############################################################################################

sub msg {
    my $fmt  = shift;
    my @args = @_;

    if ( !is_msg( $fmt ) && !grep { is_msg( $_ ); } @args ) {
        return sprintf( $fmt, @args );
    }
    if ( is_msg( $fmt ) && $fmt->{'k'} eq 'issue' && !$fmt->{'args'} ) {
        return _new( 'k' => 'issue', 'code' => $fmt->{'code'}, 'n' => $fmt->{'n'}, 'args' => \@args );
    }
    return _new( 'k' => 'fmt', 'fmt' => $fmt, 'args' => \@args );
}


#############################################################################################

sub jointext {
    my $sep   = shift;
    my @items = @_;

    if ( !is_msg( $sep ) && !grep { is_msg( $_ ); } @items ) {
        return join( $sep, @items );
    }
    return _new( 'k' => 'join', 'sep' => $sep, 'items' => \@items );
}


#############################################################################################

sub issue_msg {
    my ( $code, $n, $args ) = @_;
    return _new( 'k' => 'issue', 'code' => $code, 'n' => $n, ( $args ? ( 'args' => $args ) : () ) );
}


#############################################################################################

#
# a message about a list of objects: "head: object, object, ... and N more ..."
#
#############################################################################################

sub listed {
    my ( $head, $items, $more ) = @_;
    return _new( 'k' => 'listed', 'head' => $head, 'items' => $items, 'more' => $more );
}


#############################################################################################

#
# a list of values; the separator is chosen by the renderer from the style name
#
#############################################################################################

my %LIST_SEPARATORS = (
    'comma'     => sub { return ', '; },
    'or'        => sub { return ' ' . gettext( "or" ) . ' '; },
    'or_ref'    => sub { return gettext( "' or 'ref'='" ); },
    'role_or'   => sub { return "', 'role' = '"; },
);

sub list_msg {
    my ( $style, @items ) = @_;
    die "PtnaOutput::Msg: unknown list style '$style'\n"    unless ( exists( $LIST_SEPARATORS{$style} ) );
    return _new( 'k' => 'list', 'style' => $style, 'items' => \@items );
}


#############################################################################################

sub foreign {
    return _new( 'k' => 'foreign', 'text' => shift );
}


#############################################################################################

sub tags {
    my @kv = @_;

    return _new( 'k' => 'tags', 'kv' => \@kv );
}


#############################################################################################

sub text_msg {
    return _new( 'k' => 'text', 'text' => shift );
}


#############################################################################################

sub anchor_msg {
    my ( $id, $text ) = @_;
    return _new( 'k' => 'anchor', 'id' => $id, 'text' => $text );
}


#############################################################################################

sub relation_msg {
    return _new( 'k' => 'relation', 'link' => shift );
}


#############################################################################################

sub way_msg {
    return _new( 'k' => 'way', 'link' => shift );
}


#############################################################################################

sub node_msg {
    return _new( 'k' => 'node', 'link' => shift );
}


#############################################################################################

#
# references to GTFS data: the link to the GTFS object, the description of its status, the link to
# the comparison with the OSM relation and the scores of the CSV based comparison;
# the object is the plain data structure which is documented in PtnaOutput::Json
#
#############################################################################################

sub gtfs_msg {
    return _new( 'k' => 'gtfs', 'link' => shift );
}

sub gtfs_status_msg {
    return _new( 'k' => 'gtfs_status', 'link' => shift );
}

sub gtfs_compare_msg {
    return _new( 'k' => 'gtfs_compare', 'link' => shift );
}

sub gtfs_scores_msg {
    return _new( 'k' => 'gtfs_scores', 'link' => shift );
}


#############################################################################################

sub inject_msg {
    my $id = shift;
    return _new( 'k' => 'inject', 'id' => $id, 'kv' => [ @_ ] );
}


#############################################################################################

sub _concat {
    my ( $a, $b, $swapped ) = @_;
    my @parts = $swapped ? ( $b, $a ) : ( $a, $b );

    return _new( 'k' => 'cat', 'parts' => [ map { ( is_msg( $_ ) && $_->{'k'} eq 'cat' ) ? @{$_->{'parts'}} : ( defined( $_ ) ? $_ : '' ); } @parts ] );
}


#############################################################################################

sub render {
    my $v = shift;
    my $h = shift;

    return ( defined( $v ) ? $v : '' )      unless ( is_msg( $v ) );

    my $k = $v->{'k'};

    if ( $k eq 'fmt' ) {
        return sprintf( render( $v->{'fmt'}, $h ), map { render( $_, $h ); } @{$v->{'args'}} );
    } elsif ( $k eq 'cat' ) {
        return join( '', map { render( $_, $h ); } @{$v->{'parts'}} );
    } elsif ( $k eq 'join' ) {
        return join( render( $v->{'sep'}, $h ), map { render( $_, $h ); } @{$v->{'items'}} );
    } elsif ( $k eq 'tr' ) {
        return $h->{'tr'}->( $v->{'id'}, $v->{'plural'}, $v->{'n'} );
    } elsif ( $k eq 'issue' ) {
        require PtnaOutput::Issues;
        my $e = PtnaOutput::Issues::entry( $v->{'code'} );
        my $text = exists( $e->{'plain'} ) ? $e->{'plain'} : $h->{'tr'}->( $e->{'id'}, $e->{'plural'}, $v->{'n'} );
        return $v->{'args'} ? sprintf( $text, map { render( $_, $h ); } @{$v->{'args'}} ) : $text;
    } elsif ( $k eq 'list' ) {
        return join( render( $LIST_SEPARATORS{$v->{'style'}}->(), $h ), map { render( $_, $h ); } @{$v->{'items'}} );
    } elsif ( $k eq 'listed' ) {
        my $list = join( ', ', map { render( $_, $h ); } @{$v->{'items'}} );
        return defined( $v->{'more'} ) ? sprintf( $h->{'tr'}->( $MORE_FORMAT->{'id'} ), render( $v->{'head'}, $h ), $list, $v->{'more'} ) : sprintf( '%s: %s', render( $v->{'head'}, $h ), $list );
    } elsif ( $k eq 'tags' ) {
        my @kv = map { render( $_, $h ); } @{$v->{'kv'}};
        my @out;
        push( @out, sprintf( "'%s'='%s'", splice( @kv, 0, 2 ) ) )    while ( @kv );
        return join( ', ', @out );
    } elsif ( $k eq 'foreign' || $k eq 'text' ) {
        return $h->{$k}->( render( $v->{'text'}, $h ) );
    } elsif ( $k eq 'anchor' ) {
        return $h->{'anchor'}->( $v->{'id'}, render( $v->{'text'}, $h ) );
    } elsif ( $k eq 'inject' ) {
        return $h->{'inject'}->( $v->{'id'}, @{$v->{'kv'}} );
    }
    return $h->{$k}->( $v->{'link'} );
}


#############################################################################################
#
# the raw structure of a message for machine-readable output: nothing is translated or formatted
#
#############################################################################################

# the arguments of an issue are known by the issue: plain values and lists of key/value pairs for tags
sub issue_arg {
    my $a = shift;

    if ( is_msg( $a ) ) {
        return to_data( $a->{'text'} )                                    if ( $a->{'k'} eq 'foreign' || $a->{'k'} eq 'text' );
        return to_data( $a )->{'tags'}                                    if ( $a->{'k'} eq 'tags' );
    }
    return to_data( $a );
}

sub to_data {
    my $v = shift;

    if ( ref( $v ) eq 'ARRAY' ) {
        return [ map { to_data( $_ ); } @{$v} ];
    } elsif ( ref( $v ) eq 'HASH' && !is_msg( $v ) ) {
        return { map { $_ => to_data( $v->{$_} ); } keys( %{$v} ) };
    } elsif ( !is_msg( $v ) ) {
        return $v;
    }

    my $k = $v->{'k'};
    my %d = ( 'kind' => $k );

    if ( $k eq 'tr' ) {
        $d{'msgid'}  = $v->{'id'};
        $d{'plural'} = $v->{'plural'}   if ( defined( $v->{'plural'} ) );
        $d{'n'}      = $v->{'n'}        if ( defined( $v->{'n'} ) );
    } elsif ( $k eq 'fmt' ) {
        $d{'format'} = to_data( $v->{'fmt'} );
        $d{'args'}   = to_data( $v->{'args'} );
    } elsif ( $k eq 'cat' ) {
        $d{'parts'}  = to_data( $v->{'parts'} );
    } elsif ( $k eq 'join' ) {
        $d{'separator'} = to_data( $v->{'sep'} );
        $d{'items'}     = to_data( $v->{'items'} );
    } elsif ( $k eq 'list' ) {
        $d{'style'}  = $v->{'style'};
        $d{'items'}  = to_data( $v->{'items'} );
    } elsif ( $k eq 'listed' ) {
        # an issue about a list of objects is an issue which has 'items' and 'more'
        my $head = $v->{'head'};
        $head    = $head->{'text'}    if ( is_msg( $head ) && $head->{'k'} eq 'foreign' && is_msg( $head->{'text'} ) );
        if ( is_msg( $head ) && $head->{'k'} eq 'issue' ) {
            my $d  = to_data( $head );
            $d->{'items'} = to_data( $v->{'items'} );
            $d->{'more'}  = $v->{'more'}     if ( defined( $v->{'more'} ) );
            return $d;
        }
        $d{'head'}   = to_data( $v->{'head'} );
        $d{'items'}  = to_data( $v->{'items'} );
        $d{'more'}   = $v->{'more'}     if ( defined( $v->{'more'} ) );
    } elsif ( $k eq 'issue' ) {
        $d{'code'}   = $v->{'code'};
        $d{'n'}      = $v->{'n'}                    if ( defined( $v->{'n'} ) );
        $d{'args'}   = [ map { issue_arg( $_ ); } @{$v->{'args'}} ]    if ( $v->{'args'} );
    } elsif ( $k eq 'tags' ) {
        my @kv = @{$v->{'kv'}};
        $d{'tags'}   = [];
        push( @{$d{'tags'}}, { 'key' => to_data( shift( @kv ) ), 'value' => to_data( shift( @kv ) ) } )    while ( @kv );
    } elsif ( $k eq 'foreign' || $k eq 'text' ) {
        $d{'value'}  = to_data( $v->{'text'} );
    } elsif ( $k eq 'anchor' ) {
        $d{'id'}     = $v->{'id'};
        $d{'text'}   = to_data( $v->{'text'} );
    } elsif ( $k eq 'inject' ) {
        $d{'relation'} = $v->{'id'};
        $d{'tags'}     = to_data( $v->{'kv'} );
    } else {
        $d{'object'} = to_data( $v->{'link'} );
    }
    return \%d;
}


#############################################################################################
#
# default handlers: plain text, translated with the current locale
#
#############################################################################################

my %default_handlers = (
    'tr'        => sub {
                        my ( $id, $plural, $n ) = @_;
                        return decode( 'utf8', defined( $plural ) ? Locale::gettext::ngettext( $id, $plural, $n ) : Locale::gettext::gettext( $id ) );
                   },
    'foreign'   => sub { return $_[0]; },
    'text'      => sub { return $_[0]; },
    'anchor'    => sub { return $_[1]; },
    'relation'  => sub { return $_[0]->{'id'}; },
    'way'       => sub { return $_[0]->{'id'}; },
    'node'      => sub { return $_[0]->{'id'}; },
    'gtfs'          => sub { return $_[0]->{'id'} // $_[0]->{'feed'} // ''; },
    'gtfs_status'   => sub { return $_[0]->{'status'}; },
    'gtfs_compare'  => sub { return ''; },
    'gtfs_scores'   => sub { return ''; },
    'inject'    => sub { return ''; },
);


#############################################################################################

sub default_handlers {
    return \%default_handlers;
}


#############################################################################################

sub _stringify {
    my $self = shift;

    if ( $ENV{'PTNA_MSG_TRACE'} ) {
        my ( undef, $file, $line ) = caller( 0 );
        printf STDERR "PtnaOutput::Msg: message used as string at %s line %s\n", $file, $line;
    }
    return render( $self, \%default_handlers );
}

1;
