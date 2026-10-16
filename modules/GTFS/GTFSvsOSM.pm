package GTFS::GTFSvsOSM;

use strict;

use POSIX;

use DateTime;

use utf8;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use Encode;

use Exporter;
use base qw (Exporter);
use Data::Dumper;
use Time::HiRes;
use Unicode::Normalize;
use Time::HiRes;

use OSM::Data     qw( %META %NODES %WAYS %RELATIONS );
use OSM::Geo;
use GTFS::PtnaSQLite;

our @EXPORT_OK  = qw( Init Summary );

my $debug       = undef;
my $verbose     = undef;

my @check_against_gtfs_tasks                   = ();
my $duration_check_against_gtfs_tasks          = 0;

my %mismatch_percent_to_color= (    # // colour if actual value is greater or equal number
                                    30 => '#fe4000',
                                    20 => '#f17a00',
                                    10 => '#d7a700',
                                    2  => '#aecd00',
                                    0  => '#6aef00'
                               );


#############################################################################################

sub Init {
    my %hash   = @_;

    $debug     = $hash{'debug'};
    $verbose   = $hash{'verbose'};
}


#############################################################################################

sub getCSVbasedScores {
    my $feed             = shift || '';
    my $release_date     = shift || '';
    my $route_id         = shift || '';
    my $ref_relation_ids = shift || '';

    my $start_time    = Time::HiRes::time();
    my $duration      = 0;

    my $scores               = undef;
    my $working_release_date = undef;

    printf STDERR "%s getCSVbasedScores('%s','%s','%s','%s')\n", get_time(), $feed, $release_date, $route_id, $ref_relation_ids ? join( "', '",@{$ref_relation_ids}) : '';

    if ( $feed && $route_id && $ref_relation_ids ) {

        # currently works only for single feed, release_date and route_id in CSV

        if ( $feed !~ m/;/ && $release_date !~ m/;/ && $route_id !~ m/;/ ) {

            my @RouteIdStatus = GTFS::PtnaSQLite::getRouteIdStatus( $feed, $release_date, $route_id );

            if ( $release_date ne 'previous' && $RouteIdStatus[0] ne 'valid' && $RouteIdStatus[0] ne 'past' && $RouteIdStatus[0] ne 'future' ) {
                # not found in latest or named feed, try "previous" one

                @RouteIdStatus = GTFS::PtnaSQLite::getRouteIdStatus( $feed, 'previous', $route_id );

                if ( $RouteIdStatus[0] eq 'valid' || $RouteIdStatus[0] eq 'past' || $RouteIdStatus[0] eq 'future' ) {
                    $working_release_date = 'previous';
                }
            } else {
                $working_release_date = $release_date;
            }

            # we found a matching GTFS feed and the GTFS route is valid
            if ( defined($working_release_date) ) {
                $scores = { 'feed' => $feed, 'release_date' => $working_release_date, 'route_id' => $route_id };
            }
        }
    }

    $duration                           = Time::HiRes::time() - $start_time;
    $duration_check_against_gtfs_tasks += $duration;

    printf STDERR "%s getCSVbasedScores() returns %s, took %0.9f seconds\n", get_time(), $scores ? 'scores' : 'nothing', $duration;

    return $scores;
}


#############################################################################################

sub Summary {
    printf STDERR "%s total duration of 'check-against-gtfs' tasks = %.9f seconds\n", get_time(), $duration_check_against_gtfs_tasks;
    if ( $debug ) {
        foreach my $item ( @check_against_gtfs_tasks ) {
            printf STDERR "%s function = '%s', param1 = '%s', param2 = '%s', param3 = '%s', param4 = '%s', param5 = '%s', returns = '%s'\n",
                           get_time(),
                              $item->{'function'},
                                               $item->{'param1'} || '',
                                                              $item->{'param2'} || '',
                                                                             $item->{'param3'} || '',
                                                                                            $item->{'param4'} || '',
                                                                                                           $item->{'param5'},
                                                                                                                          $item->{'returns'} || '';
        }
    }
}


#############################################################################################

sub get_time {

    my ($sec,$min,$hour,$day,$month,$year) = localtime();

    return sprintf( "%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $month+1, $day, $hour, $min, $sec );
}

1;
