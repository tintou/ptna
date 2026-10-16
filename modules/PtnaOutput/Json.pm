package PtnaOutput::Json;

#############################################################################################
#
# JSON writer for the PTNA document model.
#
# The JSON contains the raw structure which is also handed to the HTML renderer: nothing is
# translated or formatted, that is up to the consumer. The structure is described by the
# JSON Schema doc/ptna-analysis.schema.json.
#
#############################################################################################

use strict;
use warnings;

use Exporter;
use base qw (Exporter);

use JSON::PP ();
use PtnaOutput::Msg qw();

our @EXPORT_OK = qw( to_json write_file );

our $FORMAT_VERSION = 1;


#############################################################################################

sub to_json {
    my $doc  = shift;
    # everything but the meta data and the routes list is a topic, a key of its own
    my $data = PtnaOutput::Msg::to_data( { %{$doc},
                                           'format'  => 'ptna-analysis',
                                           'version' => $FORMAT_VERSION + 0,
                                           'meta'    => $doc->{'meta'}  || {},
                                           'routes'  => $doc->{'routes'} || [],
                                         } );
    drop_cell_kinds( $data );
    return JSON::PP->new->utf8->canonical->pretty->allow_nonref->encode( $data );
}


# the entries of the 'issues' and 'notes' cells are issues by definition: no 'kind' needed
sub drop_cell_kinds {
    my $v = shift;

    if ( ref( $v ) eq 'ARRAY' ) {
        drop_cell_kinds( $_ )    foreach ( @{$v} );
    } elsif ( ref( $v ) eq 'HASH' ) {
        if ( ref( $v->{'cells'} ) eq 'HASH' ) {
            foreach my $column ( 'issues', 'notes' ) {
                next    unless ( ref( $v->{'cells'}->{$column} ) eq 'ARRAY' );
                foreach my $entry ( @{$v->{'cells'}->{$column}} ) {
                    delete( $entry->{'kind'} )    if ( ref( $entry ) eq 'HASH' && ($entry->{'kind'} || '') eq 'issue' );
                }
            }
        }
        drop_cell_kinds( $_ )    foreach ( values( %{$v} ) );
    }
}


#############################################################################################

sub write_file {
    my $doc  = shift;
    my $file = shift;

    open( my $fh, '>', $file ) or die "PtnaOutput::Json: cannot write '$file': $!\n";
    binmode( $fh );
    print $fh to_json( $doc );
    close( $fh );
}

1;
