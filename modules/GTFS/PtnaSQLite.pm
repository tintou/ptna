package GTFS::PtnaSQLite;

use strict;
use JSON::PP ();

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


our @EXPORT_OK  = qw( setTimeZoneDate setPathToWork getRouteIdStatus getTripIdStatus getShapeIdStatus getGtfsRouteIdLink getGtfsTripIdLink getGtfsShapeIdLink getGtfsLinkToRoutes );

use DBI;


#############################################################################################
#
#
#
#############################################################################################

my %config               = ();
my %db_handle            = ();
my %list_separator       = ();
my %feed_of_open_db_file = ();


$config{'path-to-work'}   = '/osm/ptna/work';                 # location where to start looking for the SQLite
$config{'name-suffix'}    = '-ptna-gtfs-sqlite.db';           # name suffix of current SQLite db
$config{'date_time_zone'} = '';


my %gtfs_route_id_status_cache = ();
my %gtfs_trip_id_status_cache  = ();
my %gtfs_shape_id_status_cache = ();

#############################################################################################
#
#
#
#############################################################################################

sub setTimeZoneDate {
    my $timezone = shift || 'Europe/Berlin';

    my $dt = DateTime->now();

    $dt->set_time_zone( $timezone );

    $config{'date_time_zone'} = sprintf( "%04d%02d%02d", $dt->year, $dt->month, $dt->day );

    # printf STDERR "%s Set PtnaSQLite::\$config{'date_time_zone'} to '%s'\n", get_time(), $config{'date_time_zone'};
}


#############################################################################################
#
#
#
#############################################################################################

sub setPathToWork {
    my $pathtowork = shift || '/osm/ptna/work';

    $config{'path-to-work'} = $pathtowork;

    # printf STDERR "%s Set PtnaSQLite::\$config{'path-to-work'} to '%s'\n", get_time(), $config{'path-to-work'};
}


#############################################################################################
# the links to the GTFS data are returned as data, they are not translated and not formatted
#
# { 'what'    => 'route' | 'trip' | 'shape',
#   'status'  => 'valid' | 'past' | 'future' | 'previous' | 'missing' | 'no_shapes' | 'no_id' | 'no_db' | 'no_feed',
#   'feed', 'release_date', 'tag' (name of the key), 'id' (of the route, trip or shape), 'from', 'to' (validity) }
#
#
#############################################################################################

sub getGtfsLinkToRoutes {
    my $gtfs_feed      = shift;
    my $release_date   = shift || '';

    my $link = { 'feed' => $gtfs_feed, 'release_date' => $release_date, 'linked' => JSON::PP::false };

    eval {
        $link->{'linked'} = JSON::PP::true    if ( _AttachToGtfsSqliteDb($gtfs_feed,$release_date) );
    };
    warn sprintf( "getGtfsLinkToRoutes(%s,%s): %s",$gtfs_feed,$release_date,$@ ) if ( $@ );

    return $link;
}


#############################################################################################
#
#
#
#############################################################################################

my %status_function = ( 'route' => \&getRouteIdStatus, 'trip' => \&getTripIdStatus, 'shape' => \&getShapeIdStatus );

sub _getGtfsIdLink {
    my $what           = shift;
    my $gtfs_feed      = shift;
    my $release_date   = shift || '';
    my $id             = shift;
    my $tag_name       = shift || $what . '_id';

    my $link           = { 'what' => $what, 'status' => 'no_feed' };
    my $status_of      = $status_function{$what};

    eval {
        if ( _AttachToGtfsSqliteDb($gtfs_feed,$release_date) ) {

            $link = { 'what' => $what, 'status' => '', 'feed' => $gtfs_feed, 'release_date' => $release_date, 'tag' => $tag_name };

            if ( $id ) {
                $link->{'id'} = $id;

                my @IdStatus = $status_of->( $gtfs_feed, $release_date, $id );

                if ( $IdStatus[0] eq 'valid' || $IdStatus[0] eq 'past' || $IdStatus[0] eq 'future' ) {
                    $link->{'status'} = $IdStatus[0];
                    $link->{'from'}   = $IdStatus[1];
                    $link->{'to'}     = $IdStatus[2];
                } elsif ( $IdStatus[0] eq 'no shapes' ) {
                    $link->{'status'} = 'no_shapes';
                } else {
                    $link->{'status'} = 'missing';

                    if ( _AttachToGtfsSqliteDb($gtfs_feed,'previous') ) {
                        @IdStatus = $status_of->( $gtfs_feed, 'previous', $id );
                        if ( $IdStatus[0] eq 'valid' || $IdStatus[0] eq 'past' || $IdStatus[0] eq 'future' ) {
                            $link->{'status'}       = 'previous';
                            $link->{'release_date'} = 'previous';
                        }
                    }
                }
            } else {
                $link->{'status'} = 'no_id';
            }
        } else {
            $link = { 'what' => $what, 'status' => 'no_db', 'feed' => $gtfs_feed, 'release_date' => $release_date };
        }
    };
    warn sprintf( "getGtfs%sIdLink(%s,%s,%s): %s", ucfirst($what), $gtfs_feed, $release_date, defined($id) ? $id : '', $@ ) if ( $@ );

    return $link;
}


#############################################################################################
#
#
#
#############################################################################################

sub getGtfsRouteIdLink {
    return _getGtfsIdLink( 'route', @_[0..2], $_[4] );
}


#############################################################################################
#
#
#
#############################################################################################

sub getGtfsTripIdLink {
    return _getGtfsIdLink( 'trip', @_[0..2], $_[4] );
}


#############################################################################################
#
#
#
#############################################################################################

sub getGtfsShapeIdLink {
    return _getGtfsIdLink( 'shape', @_[0..2], $_[4] );
}


#############################################################################################
#
#
#
#############################################################################################

sub _AttachToGtfsSqliteDb {
    my $feed           = shift;
    my $release_date   = shift || '';

    my $name_prefix    = ( $release_date ) ? $feed . '-' . $release_date : $feed;

    my $db_file    = '';

    if ( $feed && $feed =~ m/^[a-zA-Z0-9_.-]+$/ ) {
        my @prefixparts = split( /-/, $feed );
        my $countrydir  = shift( @prefixparts );

        $db_file = $config{'path-to-work'} . '/' . $countrydir . '/' . $name_prefix . $config{'name-suffix'};

        if ( -f $db_file ) {
            if ( -l $db_file ) {
                $db_file = $config{'path-to-work'} . '/' . $countrydir . '/' . readlink( $db_file );
            }
        } else {
            my $subdir = shift( @prefixparts );

            $db_file = $config{'path-to-work'} . '/' . $countrydir . '/' . $subdir . '/' . $name_prefix . $config{'name-suffix'};

            if ( -l $db_file ) {
                $db_file = $config{'path-to-work'} . '/' . $countrydir . '/' . $subdir . '/' . readlink( $db_file );
            }
        }

        if ( -f $db_file && -s $db_file ) {
            if ( !$db_handle{$name_prefix} ) {
                if ( $feed_of_open_db_file{$db_file} ) {
                    my $existing_feed = $feed_of_open_db_file{$db_file};

                    if ( $db_handle{$existing_feed} ) {
                        $db_handle{$name_prefix} = $db_handle{$existing_feed};
                        $list_separator{$name_prefix} = $list_separator{$existing_feed};
                    }
                } else {
                    $db_handle{$name_prefix} = DBI->connect( "DBI:SQLite:dbname=$db_file", "", "", { AutoCommit => 0, RaiseError => 1, ReadOnly => 1 } );

                    $feed_of_open_db_file{$db_file} = $name_prefix;

                    $list_separator{$name_prefix} = '|';
                    my $sth = $db_handle{$name_prefix}->prepare( "SELECT * FROM ptna LIMIT 1;" );
                    $sth->execute();
                    my $hash_ref = $sth->fetchrow_hashref();
                    if ( exists($hash_ref->{'list_separator'}) && $hash_ref->{'list_separator'} ) {
                        $list_separator{$name_prefix} = $hash_ref->{'list_separator'};
                    }
                }
            }

            if ( $db_handle{$name_prefix} && $list_separator{$name_prefix} ) {
                return 1;
            } else {
                printf STDERR "%s DBI->connect(%s) failed: %s\n", get_time(), $db_file, $DBI::errstr;
            }
        }

    }

    return 0;
}


#############################################################################################
#
#
#
#############################################################################################

sub getRouteIdStatus {
    my $feed           = shift;
    my $release_date   = shift || '';
    my $route_id       = shift;

    my @ret_array = ( '', '', '', '' );

    my $name_prefix    = ( $release_date ) ? $feed . '-' . $release_date : $feed;

    if ( $name_prefix && defined($route_id) && $route_id ne '' ) {
        if ( defined($gtfs_route_id_status_cache{$name_prefix}) && defined($gtfs_route_id_status_cache{$name_prefix}{$route_id}) ) {
            @ret_array = @{$gtfs_route_id_status_cache{$name_prefix}{$route_id}};
        } else {
            eval {
                if ( _AttachToGtfsSqliteDb($feed,$release_date) ) {

                    my @row         = ();
                    my $today       = get_TimeZoneDate();

                    my $sth = $db_handle{$name_prefix}->prepare( "SELECT DISTINCT trip_id
                                                                FROM            trips
                                                                WHERE           trips.route_id=?;" );
                        $sth->execute( $route_id );

                    my $min_start = 20500101;
                    my $max_end   = 19700101;
                    my $tms       = 0;
                    my $tme       = 0;

                    while ( @row = $sth->fetchrow_array() ) {
                        if ( $row[0] ) {
                            ( $tms, $tme ) = _getStartEndDateOfIdenticalTrips( $feed, $release_date, $row[0] );

                            $min_start = ($tms < $min_start) ? $tms : $min_start;
                            $max_end   = ($tme > $max_end)   ? $tme : $max_end;
                        }
                    }
                    if ( $min_start != 20500101 && $max_end != 19700101 ) {
                        if  ( $today > $max_end ) {
                            @ret_array = ( 'past', expand_date($min_start), expand_date($max_end), '' );
                        } elsif ( $today < $min_start ) {
                            @ret_array = ( 'future', expand_date($min_start), expand_date($max_end), '' );
                        } else {
                            @ret_array = ( 'valid', expand_date($min_start), expand_date($max_end), '' );
                        }
                    }
                } else {
                    @ret_array = ( '', '', '', '' );
                }
            };
            warn sprintf( "getRouteIdStatus(%s,%s,%s,%s): %s",$feed,$release_date,$route_id,$@ ) if ( $@ );
            @{$gtfs_route_id_status_cache{$name_prefix}{$route_id}} = @ret_array;
        }
    } else {
        if ( defined($route_id) && $route_id ne '' ) {
            @ret_array = ( '', '', '', 'internal error' );
        } else {
            @ret_array = ( '', '', '', '' );
        }
    }

    return @ret_array;
}


#############################################################################################
#
#
#
#############################################################################################

sub getTripIdStatus {
    my $feed           = shift;
    my $release_date   = shift || '';
    my $trip_id        = shift;
    my $route_id       = shift || '';       # todo: if set, also check if trip_id belongs to route_id

    my @ret_array = ( '', '', '', '' );

    my $name_prefix    = ( $release_date ) ? $feed . '-' . $release_date : $feed;

    if ( $name_prefix && $trip_id ) {
        if ( defined($gtfs_trip_id_status_cache{$name_prefix}) && defined($gtfs_trip_id_status_cache{$name_prefix}{$trip_id}) ) {
            @ret_array = @{$gtfs_trip_id_status_cache{$name_prefix}{$trip_id}};
        } else {
            eval {
                if ( _AttachToGtfsSqliteDb($feed,$release_date) ) {

                    my @row         = ();
                    my $today       = get_TimeZoneDate();

                    my ( $min_start, $max_end ) = _getStartEndDateOfIdenticalTrips( $feed, $release_date, $trip_id );

                    if ( $min_start != 20500101 && $max_end != 19700101 ) {
                        if  ( $today > $max_end ) {
                            @ret_array = ( 'past', expand_date($min_start), expand_date($max_end), '' );
                        } elsif ( $today < $min_start ) {
                            @ret_array = ( 'future', expand_date($min_start), expand_date($max_end), '' );
                        } else {
                            @ret_array = ( 'valid', expand_date($min_start), expand_date($max_end), '' );
                        }
                    }
                } else {
                    @ret_array = ( '', '', '', '' );
                }
            };
            warn sprintf( "getTripIdStatus(%s,%s,%s,%s): %s",$feed,$release_date,$trip_id,$@ ) if ( $@ );
            @{$gtfs_trip_id_status_cache{$name_prefix}{$trip_id}} = @ret_array;
        }
    } else {
        if ( $trip_id ) {
            @ret_array = ( '', '', '', 'internal error' );
        } else {
            @ret_array = ( '', '', '', '' );
        }
    }

    return @ret_array;
}


#############################################################################################
#
#
#
#############################################################################################

sub getShapeIdStatus {
    my $feed           = shift;
    my $release_date   = shift || '';
    my $shape_id       = shift;
    my $route_id       = shift || '';       # todo: if set, also check if shape_id belongs to route_id
    my $trip_id        = shift || '';       # todo: if set, also check if shape_id belongs to trip_id

    my @ret_array = ( '', '', '', '' );

    my $name_prefix    = ( $release_date ) ? $feed . '-' . $release_date : $feed;

    if ( $name_prefix && $shape_id ) {
        if ( defined($gtfs_shape_id_status_cache{$name_prefix}) && defined($gtfs_shape_id_status_cache{$name_prefix}{$shape_id}) ) {
            @ret_array = @{$gtfs_shape_id_status_cache{$name_prefix}{$shape_id}};
        } else {
            eval {
                if ( _AttachToGtfsSqliteDb($feed,$release_date) ) {

                    my @row                 = ();
                    my $today               = get_TimeZoneDate();
                    my $trips_has_shape_id  = 0;


                    my $sth =  $db_handle{$name_prefix}->prepare( "PRAGMA table_info(trips);" );
                    $sth->execute();

                    while ( @row = $sth->fetchrow_array() ) {
                        if ( $row[1] && $row[1] eq 'shape_id' ) {
                            $trips_has_shape_id = 1;
                            last;
                        }
                    }

                    if ( $trips_has_shape_id ) {
                        $sth = $db_handle{$name_prefix}->prepare( "SELECT DISTINCT trip_id
                                                                FROM            trips
                                                                WHERE           shape_id=?;" );
                        $sth->execute( $shape_id );

                        my $min_start = 20500101;
                        my $max_end   = 19700101;
                        my $tms       = 0;
                        my $tme       = 0;
                        while ( @row = $sth->fetchrow_array() ) {
                            if ( $row[0] ) {
                                ( $tms, $tme ) = _getStartEndDateOfIdenticalTrips( $feed, $release_date, $row[0] );

                                $min_start = ($tms < $min_start) ? $tms : $min_start;
                                $max_end   = ($tme > $max_end)   ? $tme : $max_end;
                            }
                        }
                        if ( $min_start != 20500101 && $max_end != 19700101 ) {
                            if  ( $today > $max_end ) {
                                @ret_array = ( 'past', expand_date($min_start), expand_date($max_end), '' );
                            } elsif ( $today < $min_start ) {
                                @ret_array = ( 'future', expand_date($min_start), expand_date($max_end), '' );
                            } else {
                                @ret_array = ( 'valid', expand_date($min_start), expand_date($max_end), '' );
                            }
                        }
                    } else {
                        @ret_array = ( 'no shapes', '', '', '' );
                    }
                } else {
                    @ret_array = ( '', '', '', '' );
                }
            };
            warn sprintf( "getShapeIdStatus(%s,%s,%s,%s): %s",$feed,$release_date,$shape_id,$@ ) if ( $@ );
            @{$gtfs_shape_id_status_cache{$name_prefix}{$shape_id}} = @ret_array;
        }
    } else {
        if ( $shape_id ) {
            @ret_array = ( '', '', '', 'internal error' );
        } else {
            @ret_array = ( '', '', '', '' );
        }
    }

    return @ret_array;
}


#############################################################################################

sub _getStartEndDateOfIdenticalTrips {
    my $feed           = shift;
    my $release_date   = shift || '';
    my $trip_id        = shift;

    my $name_prefix    = ( $release_date ) ? $feed . '-' . $release_date : $feed;

    my $min_start_date = 20500101;
    my $max_end_date   = 19700101;

    my @row                     = ();
    my $hash_ref                = undef;
    my $db_has_ptna_trips       = 0;
    my %service_ids             = ();
    my $where_clause            = '';
    my $has_list_service_ids    = 0;

    if ( $name_prefix && $trip_id && $db_handle{$name_prefix} ) {

        my $representative_trip_id = '';

        my $sth =  $db_handle{$name_prefix}->prepare( "SELECT name FROM sqlite_master WHERE type='table' AND name='ptna_trips';" );
           $sth->execute();

        while ( @row = $sth->fetchrow_array() ) {
            if ( $row[0] && $row[0] eq 'ptna_trips' ) {
                $db_has_ptna_trips = 1;
                last;
            }
        }

        if ( $db_has_ptna_trips ) {

            for ( my $i = 0; $i < 2 && $representative_trip_id eq ''; $i++ ) {
                if ( $i == 0 ) {
                    $sth = $db_handle{$name_prefix}->prepare( "SELECT DISTINCT *
                                                               FROM            ptna_trips
                                                               WHERE           trip_id=?"   );
                    $sth->execute( $trip_id );
                } else {
                    $sth = $db_handle{$name_prefix}->prepare( "SELECT DISTINCT *
                                                               FROM            ptna_trips
                                                               WHERE           list_trip_ids LIKE ? OR
                                                                               list_trip_ids LIKE ? OR
                                                                               list_trip_ids LIKE ?"   );
                    $sth->execute( $trip_id.$list_separator{$name_prefix}.'%', '%'.$list_separator{$name_prefix}.$trip_id.$list_separator{$name_prefix}.'%', '%'.$list_separator{$name_prefix}.$trip_id );
                }

                while ( $hash_ref = $sth->fetchrow_hashref() ) {
                    if ( $hash_ref->{'trip_id'} )  {
                        $representative_trip_id =$hash_ref->{'trip_id'};
                    }
                    if ( $hash_ref->{'list_service_ids'} ) {
                        $has_list_service_ids  = 1;
                        my $this_list_separator = $list_separator{$name_prefix} eq '|' ? '\\'.$list_separator{$name_prefix} : $list_separator{$name_prefix};
                        my @array_service_ids = split( $this_list_separator, $hash_ref->{'list_service_ids'} );

                        if ( scalar( @array_service_ids ) > 990 ) {
                            printf STDERR "_getStartEndDateOfIdenticalTrips(%s,%s,%s) number of service ids = %d\n", $feed, $release_date, $trip_id, scalar( @array_service_ids );
                            splice( @array_service_ids, 990 );
                        }

                        map { $service_ids{$_} = 1; } @array_service_ids;

                        $where_clause = 'service_id=' . join( '', map{ '? OR service_id=' } keys ( %service_ids ) );
                        $where_clause =~ s/ OR service_id=$//;

                        my $sql = sprintf( "SELECT start_date,end_date
                                            FROM   calendar
                                            WHERE  %s;", $where_clause );

                        $sth = $db_handle{$name_prefix}->prepare( $sql );
                        $sth->execute( keys ( %service_ids ) );

                        while ( @row=$sth->fetchrow_array() ) {
                            if ( $row[0] < $min_start_date ) {
                                $min_start_date = $row[0];
                            }
                            if ( $row[1] > $max_end_date ) {
                                $max_end_date   = $row[1];
                            }
                        }
                    }
                }
            }
        }

        if ( $representative_trip_id && $has_list_service_ids == 0 ) {
            $sth = $db_handle{$name_prefix}->prepare( "SELECT start_date,end_date
                                                       FROM   calendar
                                                       JOIN   trips ON trips.service_id = calendar.service_id
                                                       WHERE  trip_id=?;" );
            $sth->execute( $representative_trip_id );

            while ( @row=$sth->fetchrow_array() ) {
                if ( $row[0] < $min_start_date ) {
                    $min_start_date = $row[0];
                }
                if ( $row[1] > $max_end_date ) {
                    $max_end_date   = $row[1];
                }
            }
        }
    }

    return ( $min_start_date, $max_end_date );
}


#############################################################################################

sub get_time {

    my ($sec,$min,$hour,$day,$month,$year) = localtime();

    return sprintf( "%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $month+1, $day, $hour, $min, $sec );
}


#############################################################################################

sub get_TimeZoneDate {

    # printf STDERR "%s Using PtnaSQLite::\$config{'date_time_zone'} == '%s'\n", get_time(), $config{'date_time_zone'};

    return $config{'date_time_zone'};
}


#############################################################################################

sub expand_date {

    my $date = shift;

    $date =~ s/^(\d\d\d\d)(\d\d)(\d\d)$/\1-\2-\3/;

    return $date;
}


1;
