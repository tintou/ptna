#!/usr/bin/perl

use warnings;
use strict;
use JSON::PP ();

BEGIN { my $PATH = $0; $PATH =~ s|bin/[^/]*$|modules|; unshift( @INC, $PATH ); }

####################################################################################################################
#
#
#
####################################################################################################################

use POSIX;

use utf8;
binmode STDIN,  ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use Locale::gettext qw();       # 'gettext()' will be overwritten in this file (at the end), so don't import from module into our name space

use Getopt::Long;
use OSM::XML            qw( parse );
use OSM::Data           qw( %META %NODES %WAYS %RELATIONS );
use OSM::Geo            qw( Init PlatformToNodeDistance ConvertMetersToFeet isNodeInsidePolygon NumberOfPointsInsidePolygon Summary );
use RoutesList;
use GTFS::GTFSvsOSM     qw( Init Summary );
use PtnaOutput::Html    qw( html_escape wiki2html );
use PtnaOutput::Json    qw();
use PtnaOutput::Issues qw( issue note detail );
use PtnaOutput::Msg     qw( gettext ngettext msg listed list_msg tags jointext mkey unkey foreign text_msg anchor_msg relation_msg way_msg node_msg gtfs_msg gtfs_status_msg gtfs_compare_msg gtfs_scores_msg inject_msg );
use GTFS::PtnaSQLite    qw( setTimeZoneDate setPathToWork getRouteIdStatus getTripIdStatus getShapeIdStatus getGtfsRouteIdLink getGtfsTripIdLink getGtfsShapeIdLink getGtfsLinkToRoutes );
use Data::Dumper;
use Time::Local         qw ( timelocal );
use Time::HiRes;
use Encode;
use URI::Escape         qw ( uri_unescape );


####################################################################################################################
#
# Some OSM specific stuff, settings
#
####################################################################################################################

my @supported_route_types                   = ( 'train', 'subway', 'light_rail', 'tram', 'trolleybus', 'bus', 'ferry', 'monorail', 'aerialway', 'funicular', 'share_taxi' );
my @well_known_other_route_types            = ( 'bicycle', 'mtb', 'hiking', 'road', 'foot', 'inline_skates', 'canoe', 'detour', 'fitness_trail', 'horse', 'motorboat', 'nordic_walking', 'pipeline', 'piste', 'power', 'running', 'ski', 'snowmobile', 'cycling' , 'historic', 'motorcycle', 'riding' );
my @well_known_network_types                = ( 'international', 'national', 'regional', 'local', 'icn', 'ncn', 'rcn', 'lcn', 'iwn', 'nwn', 'rwn', 'lwn', 'road' );
my @well_known_other_types                  = ( 'restriction', 'enforcement', 'destination_sign' );
my @lifecycle_prefixes                      = ( 'proposed', 'planned', 'construction', 'disused', 'abandoned', 'ruins', 'demolished', 'razed', 'removed', 'destroyed', 'was' );

my %transport_type_uses_way_type = ( 'train'     => { 'railway'   => [ 'rail',   'light_rail', 'tram', 'narrow_gauge', 'preserved' ] },
                                     'subway'    => { 'railway'   => [ 'subway', 'light_rail', 'tram' ] },
                                     'tram'      => { 'railway'   => [ 'tram',   'rail',       'light_rail', 'narrow_gauge', 'subway' ] },
                                     'monorail'  => { 'railway'   => [ 'monorail'  ] },
                                     'funicular' => { 'railway'   => [ 'funicular' ] },
                                     'ferry'     => { 'route'     => [ 'ferry'     ] },
                                     'aerialway' => { 'aerialway' => [ 'cable_car',     'gondola',        'mixed_lift',   'chair_lift' ] },
                                     'bus'       => { 'highway'   => [ 'motorway',      'motorway_link',  'trunk',        'trunk_link',    'primary',      'primary_link',
                                                                       'secondary',     'secondary_link', 'tertiary',     'tertiary_link', 'unclassified', 'residential',
                                                                       'service',       'track',          'footway',      'cycleway',      'path',         'pedestrian',
                                                                       'living_street', 'road',           'bus_guideway', 'busway',        'construction'
                                                                     ]
                                                    },
                                   );
   $transport_type_uses_way_type{'coach'}       = $transport_type_uses_way_type{'bus'};
   $transport_type_uses_way_type{'share_taxi'}  = $transport_type_uses_way_type{'bus'};
   $transport_type_uses_way_type{'trolleybus'}  = $transport_type_uses_way_type{'bus'};
   $transport_type_uses_way_type{'light_rail'}  = $transport_type_uses_way_type{'train'};


my %transport_type_to_restriction_type = ( 'trolleybus' => 'bus',
                                           'coach'      => 'bus'
                                         );

my %max_allowed_platform_distances     = ( 'train'      => 30,
                                           'light_rail' => 30,
                                           'subway'     => 30,
                                           'tram'       => 30,
                                           'monorail'   => 30,
                                           'funicular'  => 30,
                                           'ferry'      => 30,
                                           'aerialway'  => 30,
                                           'bus'        => 30,
                                           'coach'      => 30,
                                           'share_taxi' => 30,
                                           'trolleybus' => 30
                                        );

my %deprecated_gtfs_terms              = ( 'id'          => '',
                                           'name'        => '',
                                           'dataset_id'  => '',
                                           'short_name'  => '',
                                           'long_name'   => '',
                                           'description' => '',
                                           'addr'        => ''
                                         );

####################################################################################################################
#
# Handling options from command line
#
####################################################################################################################

my $opt_language                    = undef;
my $opt_json_file                   = undef;
my $opt_test                        = undef;
my $verbose                         = undef;
my $debug                           = undef;
my $osm_xml_file                    = undef;
my $routes_file                     = undef;
my $relaxed_begin_end_for           = undef;
my $network_guid                    = undef;
my $network_long_regex              = undef;
my $network_short_regex             = undef;
my $no_additional_navigation        = undef;
my $nopre                           = undef;
my $operator_regex                  = undef;
my $allow_coach                     = undef;
my $check_access                    = undef;
my $check_against_gtfs              = undef;
my $check_bus_stop                  = undef;
my $check_dates                     = undef;
my $check_from_to                   = undef;
my $check_gtfs                      = undef;
my $check_motorway_link             = undef;
my $check_name                      = undef;
my $check_name_relaxed              = undef;
my $check_osm_separator             = undef;
my $check_platform                  = undef;
my $check_roundabouts               = undef;
my $check_route_ref                 = undef;
my $check_sequence                  = undef;
my $check_service_type              = undef;
my $check_stop_position             = undef;
my $check_version                   = undef;
my $check_via                       = undef;
my $check_way_type                  = undef;
my @exclude_if_key_value_opt        = ();
my $expect_network_long             = undef;
my $expect_network_long_as          = undef;
my $expect_network_long_for         = undef;
my $expect_network_short            = undef;
my $expect_network_short_as         = undef;
my $expect_network_short_for        = undef;
my $inherit_tags                    = undef;
my $opt_gtfs_feed                   = undef;
my $link_gtfs                       = undef;
my $multiple_ref_type_entries       = "analyze";
my $path_to_work_dir                = '/osm/ptna/work';
my $ptv1_compatibility              = "no";
my $roundtrip_distance              = 50;
my $show_gtfs                       = undef;
my $show_operators                  = undef;
my $strict_network                  = undef;
my $strict_operator                 = undef;
my $table_show_also                 = undef;
my $max_error                       = undef;
my $help                            = undef;
my $man_page                        = undef;
my $positive_notes                  = undef;
my $csv_separator                   = ';';
my $or_separator                    = '|';                  # used to separate several 'ref' values in CSV entry "43|E43;bus;;;;"
my $ref_separator                   = '/';                  # used to separate several 'ref' values in CSV entry "602/50;bus;;;;" for 'ref' from different 'network' (ref:xxx=602 and ref:yyy=50)
my $coloured_sketchline             = undef;
my $opt_timezone                    = "Europe/Berlin";      # local server time
my $page_title                      = undef;


GetOptions( 'help'                          =>  \$help,                         # -h or --help                      help
            'man'                           =>  \$man_page,                     # --man                             manual pages
            'language=s'                    =>  \$opt_language,                 # --language=de                     I18N
            'json-file=s'                   =>  \$opt_json_file,                # --json-file=FILE                  additionally write the raw (untranslated) result as JSON
            'verbose'                       =>  \$verbose,                      # --verbose
            'debug'                         =>  \$debug,                        # --debug
            'allow-coach'                   =>  \$allow_coach,                  # --allow-coach                     allow 'coach' als valid routetype
            'check-access'                  =>  \$check_access,                 # --check-access                    check for access restrictions on highways
            'check-against-gtfs=s'          =>  \$check_against_gtfs,           # --check-against-gtfs              check against GTFS data using 'gtfs:*' tags in relation (=tags) or using CVS data in 'routes_file' (=csv) or both (=tags,csv)
            'check-bus-stop'                =>  \$check_bus_stop,               # --check-bus-stop                  check for strict highway=bus_stop on nodes only
            'check-dates'                   =>  \$check_dates,                  # --check-dates                     check dates to follo ISO format: YYYY-MM-DD
            'check-from-to:s'               =>  \$check_from_to,                # --check-from-to                   check 'from' and 'to' against corresponding 'name' of platforms
            'check-gtfs'                    =>  \$check_gtfs,                   # --check-gtfs                      check "gtfs:*" tags for validity/uniqueness/...
            'check-motorway-link'           =>  \$check_motorway_link,          # --check-motorway-link             check for motorway_link followed/preceeded by motorway or trunk
            'check-name'                    =>  \$check_name,                   # --check-name                      check for strict name conventions (name='... ref: from => to'
            'check-name-relaxed'            =>  \$check_name_relaxed,           # --check-name-relaxed              check for relaxed name conventions (name='... ref: from => to'
            'check-osm-separator'           =>  \$check_osm_separator,          # --check-osm-separator             check separator for '; ' (w/ blank) and ',' (comma instead of semi-colon)
            'check-platform'                =>  \$check_platform,               # --check-platform                  check for bus=yes, tram=yes, ... on platforms
            'check-roundabouts'             =>  \$check_roundabouts,            # --check-roundabouts               check for roundabouts being included completely
            'check-route-ref'               =>  \$check_route_ref,              # --check-route-ref                 check 'route_ref' tag on highway=bus_stop and public_transport=platform
            'check-sequence'                =>  \$check_sequence,               # --check-sequence                  check for correct sequence of stops, platforms and ways
            'check-service-type'            =>  \$check_service_type,           # --check-service-type              check for routes: highway=service and correct service=* type?
            'check-stop-position'           =>  \$check_stop_position,          # --check-stop-position             check for bus=yes, tram=yes, ... on (stop_positions
            'check-version'                 =>  \$check_version,                # --check-version                   check for PTv2 on route_masters, ...
            'check-via:s'                   =>  \$check_via,                    # --check-via                       check 'via' against corresponding 'name' of platforms
            'check-way-type'                =>  \$check_way_type,               # --check-way-type                  check for routes: do vehicles use the right way type
            'coloured-sketchline'           =>  \$coloured_sketchline,          # --coloured-sketchline             force SketchLine to print coloured icons
            'exclude-if-key-value=s@'       =>  \@exclude_if_key_value_opt,     # --exclude-if-key-vallue gtfs:feed=DE-BY-MVV exclude all relations with this key=valeu pair
            'expect-network-long'           =>  \$expect_network_long,          # --expect-network-long             note if 'network' is not long form in general
            'expect-network-long-as:s'      =>  \$expect_network_long_as,       # --expect-network-long-as="Münchner Verkehrs- und Tarifverbund|Biberger Bürgerbus"
            'expect-network-long-for:s'     =>  \$expect_network_long_for,      # --expect-network-long-for="MVV|BBB"         note if 'network' is not long form for ...
            'expect-network-short'          =>  \$expect_network_short,         # --expect-network-short            note if 'network' is not short form in general
            'expect-network-short-as:s'     =>  \$expect_network_short_as,      # --expect-network-short-as='BOB'
            'expect-network-short-for:s'    =>  \$expect_network_short_for,     # --expect-network-short-for='Bayerische Oberlandbahn'        note if 'network' is not short form for ...
            'gtfs-feed=s'                   =>  \$opt_gtfs_feed,                # --gtfs-feed='DE-BY-MVV'
            'inherit-tags'                  =>  \$inherit_tags,                 # --inherit-tags
            'link-gtfs'                     =>  \$link_gtfs,                    # --link-gtfs                       create a link to GTFS-Analysis for "gtfs:*" tags
            'routes-file=s'                 =>  \$routes_file,                  # --routes-file=zzz                 CSV file with a list of routes of the of the network
            'max-error=i'                   =>  \$max_error,                    # --max-error=10                    limit number of templates printed for identical error messages
            'multiple-ref-type-entries=s'   =>  \$multiple_ref_type_entries,    # --multiple-ref-type-entries=analyze|allow    how to handle multiple "ref;type" in routes-file
            'network-guid=s'                =>  \$network_guid,                 # --network-guid='DE-BY-MVV'
            'network-long-regex:s'          =>  \$network_long_regex,           # --network-long-regex='Münchner Verkehrs- und Tarifverbund|Grünwald|Bayerische Oberlandbahn'
            'network-short-regex:s'         =>  \$network_short_regex,          # --network-short-regex='MVV|BOB'
            'no-additional-navigation'      =>  \$no_additional_navigation,     # --no-additional-navigation
            'nopre'                         =>  \$nopre,                        # --nopre                           CSV data read from GitHub does not include <pre> ... </pre>
            'operator-regex:s'              =>  \$operator_regex,               # --operator-regex='MVG|Münchner'
            'positive-notes'                =>  \$positive_notes,               # --positive-notes                  print positive information for notes, if e.g. something is fulfilled
            'ptv1-compatibility=s'          =>  \$ptv1_compatibility,           # --ptv1-compatibility=no|show|allow    how to handle "highway=bus_stop" in PTv2
            'relaxed-begin-end-for:s'       =>  \$relaxed_begin_end_for,        # --relaxed-begin-end-for=...       for train/tram/light_rail: first/last stop position does not have to be on first/last node of way, but within first/last way
            'osm-xml-file=s'                =>  \$osm_xml_file,                 # --osm-xml-file=yyy                XML output of Overpass APU query
            'path-to-work-dir=s'            =>  \$path_to_work_dir,             # --path-to-work-dir=abc            XML output of Overpass APU query
            'separator=s'                   =>  \$csv_separator,                # --separator=';'                   separator in the CSV file
            'or-separator=s'                =>  \$or_separator,                 # --or-separator='|'                separator in the CSV file inside 'ref' values to allow multiple values
            'ref-separator=s'               =>  \$ref_separator,                # --ref-separator='/'               separator in the CSV file inside 'ref' values to show cooperations
            'roundtrip-distance=i'          =>  \$roundtrip_distance,           # --roundtrip-distance=0            if 'roundtrip'='yes' is set on route relation and start and end stops are not the same, start and end must be not more far away than xx metres
            'show-gtfs'                     =>  \$show_gtfs,                    # --show-gtfs                       print positive information for "gtfs:*" tags
            'show-operators'                =>  \$show_operators,               # --show-operators                  print list of found operators
            'strict-network'                =>  \$strict_network,               # --strict-network                  do not consider empty network tags
            'strict-operator'               =>  \$strict_operator,              # --strict-operator                 do not consider empty operator tags
            'table-show-also=s'             =>  \$table_show_also,              # --table-show-also="from,via,to"   show also their values in columns in the list of 'psotive' routes
            'test'                          =>  \$opt_test,                     # --test                            to test the SW
            'timezone:s'                    =>  \$opt_timezone,                 # --timezone="Europe/Berlin"        the time zone, the analysis is running for
            'title=s'                       =>  \$page_title,                   # --title=...                       Title for the HTML page
          );

$page_title                 = decode( 'utf8', $page_title )                  if ( $page_title                );
$opt_gtfs_feed              = decode( 'utf8', $opt_gtfs_feed )               if ( $opt_gtfs_feed             );
$network_guid               = decode( 'utf8', $network_guid )                if ( $network_guid              );
$network_long_regex         = decode( 'utf8', $network_long_regex )          if ( $network_long_regex        );
$network_short_regex        = decode( 'utf8', $network_short_regex )         if ( $network_short_regex       );
$operator_regex             = decode( 'utf8', $operator_regex )              if ( $operator_regex            );
$expect_network_long_as     = decode( 'utf8', $expect_network_long_as )      if ( $expect_network_long_as    );
$expect_network_long_for    = decode( 'utf8', $expect_network_long_for )     if ( $expect_network_long_for   );
$expect_network_short_as    = decode( 'utf8', $expect_network_short_as )     if ( $expect_network_short_as   );
$expect_network_short_for   = decode( 'utf8', $expect_network_short_for )    if ( $expect_network_short_for  );


if ( $opt_language ) {
    my $PATH = $0;
    $PATH =~ s|bin/[^/]*$|locale|;
    printf STDERR "%s\n", gettext("Language test");
    $ENV{'LANGUAGE'} = $opt_language;
    Locale::gettext::setlocale( LC_MESSAGES, '' );
    Locale::gettext::bindtextdomain( 'ptna', $PATH );
    Locale::gettext::textdomain( "ptna" );
    printf STDERR "%s\n", gettext("Language test");
}

if ( $check_against_gtfs ) {
    $check_gtfs = 1;
}

if ( $check_name_relaxed ) {
    $check_name = 1;
}

if ( $check_service_type ) {
    $check_way_type = 1;
}

if ( defined($check_from_to) && $check_from_to eq '' ) {
    $check_from_to = 'exact';
}

if ( defined($check_via) && $check_via eq '' ) {
    $check_via = 'exact';
}

if ( $csv_separator ) {
    if ( length($csv_separator) > 1 ) {
        printf STDERR "%s ptna-routes.pl: wrong value for option: '--separator' = '%s' - setting it to '--separator' = ';'\n", get_time(), $csv_separator;
        $csv_separator = ';'
    }
    $csv_separator = '\\' . $csv_separator;
}

if ( $or_separator ) {
    if ( length($or_separator) > 1 ) {
        printf STDERR "%s ptna-routes.pl: wrong value for option: '--or-separator' = '%s' - setting it to '--or-separator' = '|'\n", get_time(), $or_separator;
        $or_separator = '|';
    }
    $or_separator = '\\' . $or_separator;
}

if ( $ref_separator ) {
    if ( length($ref_separator) > 1 ) {
        printf STDERR "%s ptna-routes.pl: wrong value for option: '--ref-separator' = '%s' - setting it to '--ref-separator' = '/'\n", get_time(), $ref_separator;
        $ref_separator = '/';
    }
    $ref_separator = '\\' . $ref_separator;
}

if ( $allow_coach ) {
    push( @supported_route_types, 'coach' );
}

if ( $multiple_ref_type_entries ne 'analyze' && $multiple_ref_type_entries ne 'allow' ) {
    printf STDERR "%s ptna-routes.pl: wrong value for option: '--multiple_ref_type_entries' = '%s' - setting it to '--multiple_ref_type_entries' = 'analyze'\n", get_time(), $multiple_ref_type_entries;
    $multiple_ref_type_entries = 'analyze';
}

if ( $ptv1_compatibility ne 'no' && $ptv1_compatibility ne 'allow' && $ptv1_compatibility ne 'show' ) {
    printf STDERR "%s ptna-routes.pl: wrong value for option: '--ptv1_compatibility' = '%s' - setting it to '--ptv1_compatibility' = 'no'\n", get_time(), $ptv1_compatibility;
    $ptv1_compatibility = 'no';
}

my %excluded_key_value_relations    = ();


if ( $verbose ) {
    printf STDERR "%s ptna-routes.pl -v\n", get_time();
    printf STDERR "%20s--title='%s'\n",                    ' ', $page_title                 ? $page_title   : '';
    printf STDERR "%20s--timezone='%s'\n",                 ' ', $opt_timezone               ? $opt_timezone : '';
    printf STDERR "%20s--network-guid='%s'\n",             ' ', $network_guid               ? $network_guid : '';
    printf STDERR "%20s--language='%s'\n",                 ' ', $opt_language               ? $opt_language : 'en';
    printf STDERR "%20s--allow-coach='%s'\n",              ' ', $allow_coach                ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-access='%s'\n",             ' ', $check_access               ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-against-gtfs='%s'\n",       ' ', $check_against_gtfs         ? $check_against_gtfs          : '';
    printf STDERR "%20s--check-bus-stop='%s'\n",           ' ', $check_bus_stop             ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-dates='%s'\n",              ' ', $check_dates                ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-from-to='%s'\n",            ' ', $check_from_to              ? $check_from_to               : 'OFF';
    printf STDERR "%20s--check-gtfs='%s'\n",               ' ', $check_gtfs                 ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-motorway-link='%s'\n",      ' ', $check_motorway_link        ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-name='%s'\n",               ' ', $check_name                 ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-name-relaxed='%s'\n",       ' ', $check_name_relaxed         ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-osm-separator='%s'\n",      ' ', $check_osm_separator        ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-platform='%s'\n",           ' ', $check_platform             ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-roundabouts='%s'\n",        ' ', $check_roundabouts          ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-route-ref='%s'\n",          ' ', $check_route_ref            ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-sequence='%s'\n",           ' ', $check_sequence             ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-service-type='%s'\n",       ' ', $check_service_type         ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-stop-position='%s'\n",      ' ', $check_stop_position        ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-version='%s'\n",            ' ', $check_version              ? 'ON'          : 'OFF';
    printf STDERR "%20s--check-via='%s'\n",                ' ', $check_via                  ? $check_via    : 'OFF';
    printf STDERR "%20s--check-way-type='%s'\n",           ' ', $check_way_type             ? 'ON'          : 'OFF';
    printf STDERR "%20s--coloured-sketchline='%s'\n",      ' ', $coloured_sketchline        ? 'ON'          : 'OFF';
    if ( scalar(@exclude_if_key_value_opt)) {
        my $key   = undef;
        my $value = undef;
        foreach my $key_value ( sort(@exclude_if_key_value_opt) ) {
            printf STDERR "%20s--exclude-if-key-value=%s (1)\n", ' ', $key_value    if ( $debug );
            if ( $key_value ) {
                $key_value =~ s/^"(.*)"$/$1/;
                $key_value =~ s/^'(.*)'$/$1/;
                if ( $key_value =~ m/^(.+?)=(.+)$/ ) {
                    $key   = $1;
                    $value = uri_unescape( $2 );
                    printf STDERR "%20s--exclude-if-key-value='%s=%s'\n", ' ', $key, $value;
                    $excluded_key_value_relations{$key}{$value} = {};
                    printf STDERR "\$excluded_key_value_relations{%s}{%s} = {}\n", $key, $value           if ( $debug );
                } else {
                    printf STDERR "%20s--exclude-if-key-value='%s' (3)\n", ' ', $key_value;
                    printf STDERR "Error: missing value for key '%s'\n", $key_value;
                }
            } else {
                printf STDERR "%20s--exclude-if-key-value='' (4)\n", ' ';
            }
        }
    } else {
        printf STDERR "%20s--exclude-if-key-value\n", ' ';
    }
    printf STDERR "%20s--expect-network-long='%s'\n",      ' ', $expect_network_long        ? 'ON'          : 'OFF';
    printf STDERR "%20s--expect-network-long-as='%s'\n",   ' ', $expect_network_long_as     ? $expect_network_long_as      : '';
    printf STDERR "%20s--expect-network-long-for='%s'\n",  ' ', $expect_network_long_for    ? $expect_network_long_for     : '';
    printf STDERR "%20s--expect-network-short='%s'\n",     ' ', $expect_network_short       ? 'ON'          : 'OFF';
    printf STDERR "%20s--expect-network-short-as='%s'\n",  ' ', $expect_network_short_as    ? $expect_network_short_as     : '';
    printf STDERR "%20s--expect-network-short-for='%s'\n", ' ', $expect_network_short_for   ? $expect_network_short_for    : '';
    printf STDERR "%20s--gtfs-feed='%s'\n",                ' ', $opt_gtfs_feed              ? $opt_gtfs_feed : '';
    printf STDERR "%20s--inherit-tags='%s'\n",             ' ', $inherit_tags               ? 'ON'          : 'OFF';
    printf STDERR "%20s--link-gtfs='%s'\n",                ' ', $link_gtfs                  ? 'ON'          : 'OFF';
    printf STDERR "%20s--max-error='%s'\n",                ' ', $max_error                  ? $max_error                   : '';
    printf STDERR "%20s--multiple-ref-type-entries='%s'\n",' ', $multiple_ref_type_entries  ? $multiple_ref_type_entries   : '';
    printf STDERR "%20s--network-long-regex='%s'\n",       ' ', $network_long_regex         ? $network_long_regex          : '';
    printf STDERR "%20s--network-short-regex='%s'\n",      ' ', $network_short_regex        ? $network_short_regex         : '';
    printf STDERR "%20s--no-additional-navigation='%s'\n", ' ', $no_additional_navigation   ? 'ON'          : 'OFF';
    printf STDERR "%20s--nopre='%s'\n",                    ' ', $nopre                      ? 'ON'          : 'OFF';
    printf STDERR "%20s--operator-regex='%s'\n",           ' ', $operator_regex             ? $operator_regex              : '';
    printf STDERR "%20s--positive-notes='%s'\n",           ' ', $positive_notes             ? 'ON'          : 'OFF';
    printf STDERR "%20s--ptv1-compatibility='%s'\n",       ' ', $ptv1_compatibility         ? $ptv1_compatibility          : '';
    printf STDERR "%20s--relaxed-begin-end-for='%s'\n",    ' ', $relaxed_begin_end_for      ? $relaxed_begin_end_for       : '';
    printf STDERR "%20s--roundtrip-distance='%d'\n",       ' ', $roundtrip_distance         ? $roundtrip_distance          : 0;
    printf STDERR "%20s--show-gtfs='%s'\n",                ' ', $show_gtfs                  ? 'ON'          : 'OFF';
    printf STDERR "%20s--show-operators='%s'\n",           ' ', $show_operators             ? 'ON'          : 'OFF';
    printf STDERR "%20s--strict-network='%s'\n",           ' ', $strict_network             ? 'ON'          : 'OFF';
    printf STDERR "%20s--strict-operator='%s'\n",          ' ', $strict_operator            ? 'ON'          : 'OFF';
    printf STDERR "%20s--table-show-also='%s'\n",          ' ', $table_show_also            ? $table_show_also             : '';
    printf STDERR "%20s--separator='%s'\n",                ' ', $csv_separator              ? $csv_separator               : '';
    printf STDERR "%20s--or-separator='%s'\n",             ' ', $or_separator               ? $or_separator                : '';
    printf STDERR "%20s--ref-separator='%s'\n",            ' ', $ref_separator              ? $ref_separator               : '';
    printf STDERR "%20s--routes-file='%s'\n",              ' ', decode('utf8', $routes_file )       if ( $routes_file                 );
    printf STDERR "%20s--osm-xml-file='%s'\n",             ' ', decode('utf8', $osm_xml_file )      if ( $osm_xml_file                );
    printf STDERR "%20s--path-to-work-dir='%s'\n",         ' ', decode('utf8', $path_to_work_dir )  if ( $path_to_work_dir            );
}

GTFS::PtnaSQLite::setTimeZoneDate( $opt_timezone );
GTFS::PtnaSQLite::setPathToWork( $path_to_work_dir );


####################################################################################################################
#
# Some PTNA internal stuff
#
####################################################################################################################

my $xml_has_meta            = 0;        # does the XML file include META information?
my $xml_has_relations       = 0;        # does the XML file include any relations? If not, we will exit
my $xml_has_ways            = 0;        # does the XML file include any ways, then we can make a big analysis
my $xml_has_nodes           = 0;        # does the XML file include any nodes, then we can make a big analysis

my @RouteList                               = ();
my %have_seen_well_known_other_route_types  = ();
my %have_seen_well_known_network_types      = ();
my %have_seen_well_known_other_types        = ();

my %PT_relations_with_ref   = ();       # includes "positive" (the ones we are looking for) as well as "negative" (the other ones) route/route_master relations and "skip"ed relations (where 'network' or 'operator' does not fit)
my %PT_relations_without_ref= ();       # includes any route/route_master relations without 'ref' tag
my %platform_multipolygon_relations         = ();       # includes type=multipolygon, public_transport=platform  multipolygone relations
my %suspicious_relations    = ();       # strange relations with suspicious tags, a simple list of Relation-IDs, more details can befound with $RELATIONS{rel-id}
my %route_ways              = ();       # all ways  of the XML file that build the route : equals to %WAYS - %platform_ways
my %platform_ways           = ();       # all ways  of the XML file that are platforms (tag: public_transport=platform)
my %platform_nodes          = ();       # all nodes of the XML file that are platforms (tag: public_transport=platform)
my %stop_nodes              = ();       # all nodes of the XML file that are stops (tag: public_transport=stop_position)
my %used_networks           = ();       # 'network' values that did match
my %added_networks          = ();       # 'network' values where the 'network'of their route_master matched
my %unused_networks         = ();       # 'network' values that did not match
my %seen_operators          = ();       # 'operator' values found
my %unused_operators        = ();       # 'operator' values that did not match but 'network' values did match
my %gtfs_relation_info_from = ();       # Relations reference to GTFS feed information using $gtfs_relation_info_from{feed-name}{feed_info_from}{release_date}{release_date_from}{relarionID} = 1;
my %gtfs_csv_info_from      = ();       # CSV data  reference to GTFS feed information using $gtfs_csv_info_from{feed-name}{release_date} = ( feed_info_from, release_info_from );
my %conditional_access      = ();       # e.g. key: "'access:conditional'='no @ (2025 Jun 30-2025 Aug 10)'" refers to way_id refers to relation_id, value = 1 or !exists

my $relation_ptr            = undef;    # a pointer in Perl to a relation structure
my $relation_id             = undef;    # the OSM ID of a relation
my $way_id                  = undef;    # the OSM ID of a way
my $node_id                 = undef;    # the OSM ID of a node
my $tag                     = undef;
my $ref                     = undef;    # the value of "ref" tag of an OSM object (usually the "ref" tag of a route relation
my $route_type              = undef;    # the value of "route_master" or "route" of a relation
my $operator                = undef;    # the value of "operator" of relation or in CSV file
my $member                  = undef;
my $node                    = undef;
my $entry                   = undef;
my $type                    = undef;
my $relation_index                  = 0;
my $route_master_relation_index     = 0;    # counts the number of relation members in a 'route_master' which do not have 'role' ~ 'platform' (should be equal to $relation_index')
my $route_relation_index            = 0;    # counts the number of relation members in a 'route' which are not 'platforms' (should be zero)
my $way_index                       = 0;    # counts the number of all way members
my $route_highway_index             = 0;    # counts the number of ways members in a route which do not have 'role' ~ 'platform'
my $node_index                      = 0;    # counts the number of node members
my $role_platform_index             = 0;    # counts the number of members which have 'role' '^platform.*'
my $role_stop_index                 = 0;    # counts the number of members which have 'role' '^platform.*'
my $osm_base                        = '';
my $areas                           = '';


OSM::Geo::Init( 'debug' => $debug, 'verbose' => $verbose );

if ( $check_against_gtfs ) {
    GTFS::GTFSvsOSM::Init( 'debug' => $debug, 'verbose' => $verbose );
}

my %column_name             = ( 'ref'               => gettext('Line (ref=)'),
                                'relation'          => gettext('Relation (id=)'),
                                'relations'         => gettext('Relations'),                 # comma separated list of relation-IDs
                                'name'              => gettext('Name (name=)'),
                                'number'            => gettext('Number'),
                                'network'           => gettext('Network (network=)'),
                                'operator'          => gettext('Operator (operator=)'),
                                'from'              => gettext('From (from=)'),
                                'via'               => gettext('Via (via=)'),
                                'to'                => gettext('To (to=)'),
                                'issues'            => gettext('Errors'),
                                'notes'             => gettext('Notes'),
                                'type'              => gettext('Type (type=)'),
                                'life-cycle-prefix' => 'prefix:route(_master)',
                                'route_type'        => gettext('Vehicle (route(_master)=)'),
                                'PTv'               => gettext('PTv'),
                                'CSV-Comment'       => gettext('Comment'),
                                'CSV-From'          => gettext('From'),
                                'CSV-To'            => gettext('To'),
                                'CSV-Operator'      => gettext('Operator'),
                                'gtfs_feed'         => gettext('GTFS feed'),
                                'date'              => gettext('Date'),
                                'feed_from'         => gettext('GTFS feed from'),
                                'date_from'         => gettext('Date from'),
                                'conditional_access'=> gettext('Conditional Access'),
                                'ways'              => gettext('Ways')
                              );

my %colour_table            = ( 'black'                 => '#000000',
                                'gray'                  => '#808080',
                                'grey'                  => '#808080',
                                'maroon'                => '#800000',
                                'olive'                 => '#808000',
                                'green'                 => '#008000',
                                'teal'                  => '#008080',
                                'navy'                  => '#000080',
                                'purple'                => '#800080',
                                'white'                 => '#FFFFFF',
                                'silver'                => '#c0c0c0',
                                'red'                   => '#FF0000',
                                'yellow'                => '#FFFF00',
                                'lime'                  => '#00FF00',
                                'aqua'                  => '#00FFFF',
                                'cyan'                  => '#00FFFF',
                                'blue'                  => '#0000FF',
                                'fuchsia'               => '#FF00FF',
                                'magenta'               => '#FF00FF',
                                'aliceblue'             => '#F0F8FF',
                                'antiquewhite'          => '#FAEBD7',
                                'aqua'                  => '#00FFFF',
                                'aquamarine'            => '#7FFFD4',
                                'azure'                 => '#F0FFFF',
                                'beige'                 => '#F5F5DC',
                                'bisque'                => '#FFE4C4',
                                'black'                 => '#000000',
                                'blanchedalmond'        => '#FFEBCD',
                                'blue'                  => '#0000FF',
                                'blueviolet'            => '#8A2BE2',
                                'brown'                 => '#A52A2A',
                                'burlywood'             => '#DEB887',
                                'cadetblue'             => '#5F9EA0',
                                'chartreuse'            => '#7FFF00',
                                'chocolate'             => '#D2691E',
                                'coral'                 => '#FF7F50',
                                'cornflowerblue'        => '#6495ED',
                                'cornsilk'              => '#FFF8DC',
                                'crimson'               => '#DC143C',
                                'cyan'                  => '#00FFFF',
                                'darkblue'              => '#00008B',
                                'darkcyan'              => '#008B8B',
                                'darkgoldenrod'         => '#B8860B',
                                'darkgray'              => '#A9A9A9',
                                'darkgrey'              => '#A9A9A9',
                                'darkgreen'             => '#006400',
                                'darkkhaki'             => '#BDB76B',
                                'darkmagenta'           => '#8B008B',
                                'darkolivegreen'        => '#556B2F',
                                'darkorange'            => '#FF8C00',
                                'darkorchid'            => '#9932CC',
                                'darkred'               => '#8B0000',
                                'darksalmon'            => '#E9967A',
                                'darkseagreen'          => '#8FBC8F',
                                'darkslateblue'         => '#483D8B',
                                'darkslategray'         => '#2F4F4F',
                                'darkslategrey'         => '#2F4F4F',
                                'darkturquoise'         => '#00CED1',
                                'darkviolet'            => '#9400D3',
                                'deeppink'              => '#FF1493',
                                'deepskyblue'           => '#00BFFF',
                                'dimgray'               => '#696969',
                                'dimgrey'               => '#696969',
                                'dodgerblue'            => '#1E90FF',
                                'firebrick'             => '#B22222',
                                'floralwhite'           => '#FFFAF0',
                                'forestgreen'           => '#228B22',
                                'fuchsia'               => '#FF00FF',
                                'gainsboro'             => '#DCDCDC',
                                'ghostWhite'            => '#F8F8FF',
                                'gold'                  => '#FFD700',
                                'goldenrod'             => '#DAA520',
                                'gray'                  => '#808080',
                                'grey'                  => '#808080',
                                'green'                 => '#008000',
                                'greenyellow'           => '#ADFF2F',
                                'honeydew'              => '#F0FFF0',
                                'hotpink'               => '#FF69B4',
                                'indianred'             => '#CD5C5C',
                                'indigo'                => '#4B0082',
                                'ivory'                 => '#FFFFF0',
                                'khaki'                 => '#F0E68C',
                                'lavender'              => '#E6E6FA',
                                'lavenderblush'         => '#FFF0F5',
                                'lawngreen'             => '#7CFC00',
                                'lemonchiffon'          => '#FFFACD',
                                'lightblue'             => '#ADD8E6',
                                'lightcoral'            => '#F08080',
                                'lightcyan'             => '#E0FFFF',
                                'lightgoldenrodyellow'  => '#FAFAD2',
                                'lightgray'             => '#D3D3D3',
                                'lightgrey'             => '#D3D3D3',
                                'lightgreen'            => '#90EE90',
                                'lightpink'             => '#FFB6C1',
                                'lightsalmon'           => '#FFA07A',
                                'lightseagreen'         => '#20B2AA',
                                'lightskyblue'          => '#87CEFA',
                                'lightslategray'        => '#778899',
                                'lightslategrey'        => '#778899',
                                'lightsteelblue'        => '#B0C4DE',
                                'lightyellow'           => '#FFFFE0',
                                'lime'                  => '#00FF00',
                                'limegreen'             => '#32CD32',
                                'linen'                 => '#FAF0E6',
                                'magenta'               => '#FF00FF',
                                'maroon'                => '#800000',
                                'mediumaquamarine'      => '#66CDAA',
                                'mediumblue'            => '#0000CD',
                                'mediumorchid'          => '#BA55D3',
                                'mediumpurple'          => '#9370D8',
                                'mediumseagreen'        => '#3CB371',
                                'mediumslateblue'       => '#7B68EE',
                                'mediumspringgreen'     => '#00FA9A',
                                'mediumturquoise'       => '#48D1CC',
                                'mediumvioletred'       => '#C71585',
                                'midnightblue'          => '#191970',
                                'mintcream'             => '#F5FFFA',
                                'mistyrose'             => '#FFE4E1',
                                'moccasin'              => '#FFE4B5',
                                'navajowhite'           => '#FFDEAD',
                                'navy'                  => '#000080',
                                'oldlace'               => '#FDF5E6',
                                'olive'                 => '#808000',
                                'olivedrab'             => '#6B8E23',
                                'orange'                => '#FFA500',
                                'orangered'             => '#FF4500',
                                'orchid'                => '#DA70D6',
                                'palegoldenrod'         => '#EEE8AA',
                                'palegreen'             => '#98FB98',
                                'paleturquoise'         => '#AFEEEE',
                                'palevioletred'         => '#D87093',
                                'papayawhip'            => '#FFEFD5',
                                'peachpuff'             => '#FFDAB9',
                                'peru'                  => '#CD853F',
                                'pink'                  => '#FFC0CB',
                                'plum'                  => '#DDA0DD',
                                'powderblue'            => '#B0E0E6',
                                'purple'                => '#800080',
                                'red'                   => '#FF0000',
                                'rosybrown'             => '#BC8F8F',
                                'royalblue'             => '#4169E1',
                                'saddlebrown'           => '#8B4513',
                                'salmon'                => '#FA8072',
                                'sandybrown'            => '#F4A460',
                                'seagreen'              => '#2E8B57',
                                'seashell'              => '#FFF5EE',
                                'sienna'                => '#A0522D',
                                'silver'                => '#C0C0C0',
                                'skyblue'               => '#87CEEB',
                                'slateblue'             => '#6A5ACD',
                                'slategray'             => '#708090',
                                'slategrey'             => '#708090',
                                'snow'                  => '#FFFAFA',
                                'springgreen'           => '#00FF7F',
                                'steelblue'             => '#4682B4',
                                'tan'                   => '#D2B48C',
                                'teal'                  => '#008080',
                                'thistle'               => '#D8BFD8',
                                'tomato'                => '#FF6347',
                                'turquoise'             => '#40E0D0',
                                'violet'                => '#EE82EE',
                                'wheat'                 => '#F5DEB3',
                                'white'                 => '#FFFFFF',
                                'whitesmoke'            => '#F5F5F5',
                                'yellow'                => '#FFFF00',
                                'yellowgreen'           => '#9ACD32'
                              );


#############################################################################################
#
# read the file which contains the lines of interest, CSV style file, first column corresponds to "ref", those are the "refs of interest"
#
#############################################################################################

if ( $routes_file ) {

    printf STDERR "%s Reading %s\n", get_time(), decode('utf8', $routes_file )                  if ( $verbose );

    my $ReadError = RoutesList::ReadRoutes( 'file'                   => $routes_file,
                                            'analyze'                => $multiple_ref_type_entries,
                                            'csv-separator'          => $csv_separator,
                                            'or-separator'           => $or_separator,
                                            'supported_route_types'  => \@supported_route_types,
                                            'verbose'                => $verbose,
                                            'debug'                  => $debug,
                                            'nopre'                  => $nopre
                                          );

    if ( $ReadError ) {

        printf STDERR "%s %s\n", get_time(), $ReadError;

    } else {

        @RouteList = RoutesList::GetRoutesList();

        printf STDERR "%s %s read\n", get_time(), decode('utf8', $routes_file )                 if ( $verbose );
    }

}


#############################################################################################
#
# secondly read the XML file with the OSM information (might take a while)
#
#############################################################################################

if ( $osm_xml_file ) {

    printf STDERR "%s Reading %s\n", get_time(), decode('utf8', $osm_xml_file )                                         if ( $verbose );

    my $ret = parse( 'data' => $osm_xml_file, 'debug' => $debug, 'verbose' => $verbose );

    if ( $ret ) {
        printf STDERR "%s %s read\n", get_time(), decode('utf8', $osm_xml_file )                                        if ( $verbose );
        $xml_has_meta       = 1  if ( scalar(keys(%META))      );
        $xml_has_relations  = 1  if ( scalar(keys(%RELATIONS)) );
        $xml_has_ways       = 1  if ( scalar(keys(%WAYS))      );
        $xml_has_nodes      = 1  if ( scalar(keys(%NODES))     );
    } else {
        printf STDERR "%s %s read failed with return code %s\n", get_time(), decode('utf8', $osm_xml_file ), $ret       if ( $verbose );
    }
}

if ( $xml_has_relations == 0 ) {
    printf STDERR "No relations found in XML file %s\n", decode('utf8', $osm_xml_file );
}


#############################################################################################
#
# now analyze the XML data
#
# 1. the meta information of the data: when has this been extracted from the DB
#
#############################################################################################

if ( $xml_has_meta ) {
    if ( $META{'osm_base'} ) {
        $osm_base = $META{'osm_base'};
    }
    if ( $META{'areas'} ) {
        $areas = $META{'areas'};
    }
    $osm_base =~ s/T/ /g;
    $osm_base =~ s/Z/ UTC/g;
    $areas    =~ s/T/ /g;
    $areas    =~ s/Z/ UTC/g;
}

if ( $debug   ) {
    printf STDERR "OSM-Base : %s\n", $osm_base;
    printf STDERR "Areas    : %s\n", $areas;
}


#############################################################################################
#
# analyze the main part of the XML data
#
# 1. the relation information
#
# 2. way information
#
# 3. node information
#
# XML data for relations will be converted into own structure, additional data will be created also, so that analysis is more easier
#
#############################################################################################

my $status                                      = undef;        # can be: 'keep', 'skip', 'keep positive' or 'keep negative'
my $section                                     = undef;        # can be: 'positive', 'negative', 'skip', 'suspicious' or something else
my $number_of_relations                         = 0;
my $number_of_route_relations                   = 0;
my $number_of_platform_multipolygon_relations   = 0;
my $number_of_positive_relations                = 0;
my $number_of_unassigned_relations              = 0;
my $number_of_negative_relations                = 0;
my $number_of_life_cycle_prefix_relations       = 0;
my $number_of_suspicious_relations              = 0;
my $number_of_excluded_relations                = 0;
my $number_of_relations_without_ref             = 0;
my $number_of_ways                              = 0;
my $number_of_routeways                         = 0;
my $number_of_platformways                      = 0;
my $number_of_nodes                             = 0;
my $number_of_platformnodes                     = 0;
my $number_of_stop_positions                    = 0;
my $number_of_used_networks                     = 0;
my $number_of_unused_networks                   = 0;

#
# there are relations, so lets convert them
#

printf STDERR "%s Converting relations\n", get_time()       if ( $verbose );

foreach $relation_id ( sort ( keys ( %RELATIONS ) ) ) {

    $number_of_relations++;

    if ( exists($RELATIONS{$relation_id}->{'tag'}->{'type'}) ) {

        $type = $RELATIONS{$relation_id}->{'tag'}->{'type'};
        #
        # first analyze route_master and route relations
        #
        if ( $type eq 'route_master' || $type eq 'route' ) {

            $relation_ptr         = undef;
            $route_type           = undef;

            $RELATIONS{$relation_id}->{'type_key'}    = 'type';
            $RELATIONS{$relation_id}->{'type_value'}  = $type;

            if ( exists($RELATIONS{$relation_id}->{'tag'}->{$type}) ) {
                if ( $type =~ m/route_master$/ ) {
                    $RELATIONS{$relation_id}->{'route_master_type_key'}    = $type;
                    $RELATIONS{$relation_id}->{'route_master_type_value'}  = $RELATIONS{$relation_id}->{'tag'}->{$type};
                    $route_type   = $RELATIONS{$relation_id}->{'tag'}->{$type};
                    printf STDERR "%s Set short-cut key   \$RELATIONS{%s}->{'route_master_type_key'}   = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'route_master_type_key'}      if ( $debug );
                    printf STDERR "%s Set short-cut value \$RELATIONS{%s}->{'route_master_type_value'} = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'route_master_type_value'}    if ( $debug );
                } else {
                    $RELATIONS{$relation_id}->{'route_type_key'}    = $type;
                    $RELATIONS{$relation_id}->{'route_type_value'}  = $RELATIONS{$relation_id}->{'tag'}->{$type};
                    $route_type   = $RELATIONS{$relation_id}->{'tag'}->{$type};
                    printf STDERR "%s Set short-cut key   \$RELATIONS{%s}->{'route_type_key'}   = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'route_type_key'}      if ( $debug );
                    printf STDERR "%s Set short-cut value \$RELATIONS{%s}->{'route_type_value'} = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'route_type_value'}    if ( $debug );
                }
            } else {
                foreach my $key ( keys( %{$RELATIONS{$relation_id}->{'tag'}} ) ) {
                    if ( $key =~ m/^[^:]+:(route_master|route)$/ ) {
                        if ( $key =~ m/route_master$/ ) {
                            $RELATIONS{$relation_id}->{'life-cycle-prefix'} = $key;
                            $RELATIONS{$relation_id}->{'route_master_type_key'}    = $key;
                            $RELATIONS{$relation_id}->{'route_master_type_value'}  = $RELATIONS{$relation_id}->{'tag'}->{$key};
                            $route_type = $RELATIONS{$relation_id}->{'tag'}->{$key};
                            printf STDERR "%s Set short-cut       \$RELATIONS{%s}->{'life-cycle-prefix'}        = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'life-cycle-prefix'}          if ( $debug );
                            printf STDERR "%s Set short-cut key   \$RELATIONS{%s}->{'route_master_type_key'}    = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'route_master_type_key'}      if ( $debug );
                            printf STDERR "%s Set short-cut value \$RELATIONS{%s}->{'route_master_type_value'}  = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'route_master_type_value'}    if ( $debug );
                        } else {
                            $RELATIONS{$relation_id}->{'life-cycle-prefix'} = $key;
                            $RELATIONS{$relation_id}->{'route_type_key'}    = $key;
                            $RELATIONS{$relation_id}->{'route_type_value'}  = $RELATIONS{$relation_id}->{'tag'}->{$key};
                            $route_type = $RELATIONS{$relation_id}->{'tag'}->{$key};
                            printf STDERR "%s Set short-cut       \$RELATIONS{%s}->{'life-cycle-prefix'} = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'life-cycle-prefix'}   if ( $debug );
                            printf STDERR "%s Set short-cut key   \$RELATIONS{%s}->{'route_type_key'}    = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'route_type_key'}      if ( $debug );
                            printf STDERR "%s Set short-cut value \$RELATIONS{%s}->{'route_type_value'}  = '%s'\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'route_type_value'}    if ( $debug );
                        }
                        last;
                    }
                }
            }

            if ( $route_type ) {
                $number_of_route_relations++;

                $relation_ptr = $RELATIONS{$relation_id};

                if ( exists($RELATIONS{$relation_id}->{'tag'}->{'ref'}) ) {
                    $ref    = $RELATIONS{$relation_id}->{'tag'}->{'ref'};

                    $status = 'keep';

                    # match_exclude() returns either "keep" or "exclude"
                    # "exclude" returned if relation matches with --exclude-if-key=value option
                    if ( $status =~ m/keep/ ) { $status = match_exclude( $relation_id ); }

                    # match_route_type() returns either "keep" or "suspicious" or "skip"
                    # is this route_type of general interest? 'hiking', 'bicycle', ... routes are not of interest here
                    # "keep"        route_type matches exactly the supported route types            m/^'type'$/
                    # "suspicious"  route_type does not exactly match the supported route types     m/'type'/               (typo, ...?)
                    # "other"       route_type is not a well known route  type                      "coach", ...
                    # "well_known"  route_type is a well known route type                           "bicycle", "mtb", "hiking", "road", ...
                    #
                    if ( $status =~ m/keep/ ) { $status = match_route_type( $route_type ); }
                    printf STDERR "%-15s: ref=%s\ttype=%s\troute_type=%s\tRelation: %d\n", $status, $ref, $type, $route_type, $relation_id   if ( $debug );

                    # match_network() returns either "keep long" or "keep short" or "skip"
                    #
                    if ( $status =~ m/keep/ ) { $status = match_network(  $relation_ptr->{'tag'}->{'network'} ); }

                    if ( $status =~ m/keep/ ) {
                        # match_operator() returns either "keep" or "skip"
                        #
                        $status = match_operator( $relation_ptr->{'tag'}->{'operator'} );

                        if ( $status =~ m/keep/ ) {
                            if ( $RELATIONS{$relation_id}->{'tag'}->{'network'} ) {
                                $used_networks{$relation_ptr->{'tag'}->{'network'}}->{$relation_id} = 1;
                            }
                            else {
                                $used_networks{'__unset_network__'}->{$relation_id} = 1;
                            }
                        } else {
                            if ( $RELATIONS{$relation_id}->{'tag'}->{'operator'} ) {
                                $unused_operators{$relation_ptr->{'tag'}->{'operator'}}{$relation_id} = 1;
                            }
                            else {
                                $unused_operators{'__unset_operator__'}->{$relation_id} = 1;
                            }
                        }
                    } elsif ( $status ne 'well_known' ) {
                        if ( $RELATIONS{$relation_id}->{'tag'}->{'network'} ) {
                            $unused_networks{$relation_ptr->{'tag'}->{'network'}}{$relation_id} = 1;
                        }
                        else {
                            $unused_networks{'__unset_network__'}->{$relation_id} = 1;
                        }
                    }

                    # match_ref_and_pt_type() returns "keep positive", "keep negative", "skip"
                    # "keep positive"   if $ref and $type match the %ref_type_of_interest (list of lines from CSV file)
                    # "keep negative"   if $ref and $type do not match
                    # "skip"            if $ref and $type are not set
                    #
                    if ( $status =~ m/keep/ ) { $status = match_ref_and_pt_type( $ref, $route_type ); }

                    if ( $debug ) {
                        printf STDERR "%-15s: ref=%s", $status, $ref;
                        printf STDERR "\ttype=%s", $type;
                        printf STDERR "\troute_type=%s", $route_type;
                        printf STDERR "\tnetwork=%s", ($relation_ptr->{'tag'}->{'network'} || '');
                        printf STDERR "\toperator=%s", ($relation_ptr->{'tag'}->{'operator'} || '');
                        printf STDERR "\tRelation: %d\n", $relation_id;
                    }

                    $section = undef;
                    if ( $status =~ m/(positive|negative)/ ) {
                        if ( $RELATIONS{$relation_id}->{'life-cycle-prefix'} ) {
                            $section = 'life-cycle-prefix';
                        } else {
                            $section = $1;
                        }
                    } elsif ( $status =~ m/(skip|other|suspicious|well_known|exclude)/ ) {
                        $section = $1;
                    }

                    if ( $section ) {
                        if ( $section eq 'positive' || $section eq 'negative' || $section eq 'life-cycle-prefix' ) {
                            my $ue_ref = $ref;
                            $PT_relations_with_ref{$section}->{$ue_ref}->{$type}->{$route_type}->{$relation_id} = $relation_ptr;
                        } elsif ( $section eq 'other' || $section eq 'suspicious' ) {
                            $suspicious_relations{$relation_id} = 1;
                        }
                    } elsif ( $verbose ) {
                        printf STDERR "%s Section mismatch 'status' = '%s'\n", get_time(), $status;
                    }
                } else {
                    $status = match_route_type( $route_type );
                    printf STDERR "%-15s: ref=undef\ttype=%s\troute_type=%s\tRelation: %d\n", $status, $type, $route_type, $relation_id   if ( $debug );

                    if ( $status eq 'keep' || $status eq 'suspicious' ) {
                        # only supported route types or their typos must have 'ref' set

                        $PT_relations_without_ref{$route_type}->{$relation_id} = $relation_ptr;

                        # match_network() returns either "keep long" or "keep short" or "skip"
                        #
                        my $status = match_network( $relation_ptr->{'tag'}->{'network'} );
                        if ( $status =~ m/keep/ ) {
                            # match_operator() returns either "keep" or "skip"
                            #
                            $status = match_operator( $relation_ptr->{'tag'}->{'operator'} );

                            if ( $status =~ m/keep/ ) {
                                if ( $relation_ptr->{'tag'}->{'network'} ) {
                                    $used_networks{$relation_ptr->{'tag'}->{'network'}}->{$relation_id} = 1;
                                }
                                else {
                                    $used_networks{'__unset_network__'}->{$relation_id} = 1;
                                }
                            } else {
                                if ( $relation_ptr->{'tag'}->{'operator'} ) {
                                    $unused_operators{$relation_ptr->{'tag'}->{'operator'}}{$relation_id} = 1;
                                }
                                else {
                                    $unused_operators{'__unset_operator__'}->{$relation_id} = 1;
                                }
                            }
                        } else {
                            if ( $relation_ptr->{'tag'}->{'network'} ) {
                                $unused_networks{$relation_ptr->{'tag'}->{'network'}}->{$relation_id} = 1;
                            } else {
                                $unused_networks{'__unset_network__'}->{$relation_id} = 1;
                            }
                        }
                        if ( $status eq 'suspicious' ) {
                            $suspicious_relations{$relation_id} = 1;
                        }
                    } else {
                        if ( $status eq 'other' ) {
                            # at least all others (except well_known) shall also be reported as 'suspicious'
                            $suspicious_relations{$relation_id} = 1;
                        }
                    }
                }

                if ( $relation_ptr ) {

                    @{$relation_ptr->{'relation'}}              = ();
                    @{$relation_ptr->{'route_master_relation'}} = ();
                    @{$relation_ptr->{'route_relation'}}        = ();
                    @{$relation_ptr->{'way'}}                   = ();
                    @{$relation_ptr->{'route_highway'}}         = ();
                    @{$relation_ptr->{'node'}}                  = ();
                    @{$relation_ptr->{'role_platform'}}         = ();
                    @{$relation_ptr->{'role_stop'}}             = ();
                    @{$relation_ptr->{'__issues__'}}            = ();
                    @{$relation_ptr->{'__notes__'}}             = ();
                    @{$relation_ptr->{'__GTFS__'}}              = ();
                    $relation_ptr->{'gtfs_keys'}                = ();
                    $relation_ptr->{'gtfs-scores'}              = { 'route_master' => (), 'route' => () };
                    $relation_ptr->{'__sort_name__'} = $relation_id     unless ( $relation_ptr->{'__sort_name__'} );        # will be set to "rel_ID_of_route_master - member_index"  for route relations having a parent route_master
                    $relation_ptr->{'__printed__'}   = 0;
                    $relation_index                  = 0;   # counts the number of members which are relations (any relation: 'route' or with 'role' = 'platform', ...
                    $route_master_relation_index     = 0;   # counts the number of relation members in a 'route_master' which do not have 'role' ~ 'platform' (should be equal to $relation_index')
                    $route_relation_index            = 0;   # counts the number of relation members in a 'route' which do not have 'role' ~ 'platform' (should be zero)
                    $way_index                       = 0;   # counts the number of all way members
                    $route_highway_index             = 0;   # counts the number of ways members in a route which do not have 'role' ~ 'platform', i.e. those ways a bus really uses
                    $node_index                      = 0;   # counts the number of node members
                    $role_platform_index             = 0;   # counts the number of members which have 'role' '^platform.*'
                    $role_stop_index                 = 0;   # counts the number of members which have 'role' '^stop.*'
                    foreach my $key ( keys(%{$relation_ptr->{'tag'}}) ) {
                        if ( $key =~ m/^gtfs/ ) {
                            $relation_ptr->{'gtfs_keys'}->{$key} = $relation_ptr->{'tag'}->{$key};
                        }
                    }
                    foreach $member ( @{$relation_ptr->{'members'}} ) {
                        if ( $member->{'type'} ) {
                            if ( $member->{'type'} eq 'relation' ) {
                                ${$relation_ptr->{'relation'}}[$relation_index]->{'ref'}  = $member->{'ref'};
                                ${$relation_ptr->{'relation'}}[$relation_index]->{'role'} = $member->{'role'};
                                $relation_index++;
                                if ( $type             eq 'route_master'     &&
                                     $member->{'role'} !~ m/^platform/    ) {
                                    ${$relation_ptr->{'route_master_relation'}}[$route_master_relation_index]->{'ref'}  = $member->{'ref'};
                                    ${$relation_ptr->{'route_master_relation'}}[$route_master_relation_index]->{'role'} = $member->{'role'};
                                    $route_master_relation_index++;
                                    $RELATIONS{$member->{'ref'}}->{'member_of_route_master'}->{$relation_id} = 1;
                                    $RELATIONS{$member->{'ref'}}->{'__sort_name__'}                         = msg( "%s - %04d", $relation_id, $route_master_relation_index );
                                    printf STDERR "Relation %s: member of %s has index %d --> __sort_name__ = %s\n", $member->{'ref'}, $relation_id, $route_master_relation_index, $RELATIONS{$member->{'ref'}}->{'__sort_name__'}    if ( $debug );
                                } elsif ( $type        eq 'route'     &&
                                    $member->{'role'} !~ m/^platform/    ) {
                                    ${$relation_ptr->{'route_relation'}}[$route_relation_index]->{'ref'}  = $member->{'ref'};
                                    ${$relation_ptr->{'route_relation'}}[$route_relation_index]->{'role'} = $member->{'role'};
                                    $route_relation_index++;
                                }
                            } elsif ( $member->{'type'} eq 'way' ) {
                                ${$relation_ptr->{'way'}}[$way_index]->{'ref'}  = $member->{'ref'};
                                ${$relation_ptr->{'way'}}[$way_index]->{'role'} = $member->{'role'};
                                $way_index++;
                                if ( $type             eq 'route'     &&
                                     $member->{'role'} !~ m/^platform/    ) {
                                    ${$relation_ptr->{'route_highway'}}[$route_highway_index]->{'ref'}  = $member->{'ref'};
                                    ${$relation_ptr->{'route_highway'}}[$route_highway_index]->{'role'} = $member->{'role'};
                                    $route_highway_index++;
                                }
                            } elsif ( $member->{'type'} eq 'node' ) {
                                ${$relation_ptr->{'node'}}[$node_index]->{'ref'}  = $member->{'ref'};
                                ${$relation_ptr->{'node'}}[$node_index]->{'role'} = $member->{'role'};
                                $node_index++;
                            }

                            if ( $member->{'role'} ) {
                                if ( $member->{'role'} =~ m/^platform/ ) {
                                    ${$relation_ptr->{'role_platform'}}[$role_platform_index]->{'type'} = $member->{'type'};
                                    ${$relation_ptr->{'role_platform'}}[$role_platform_index]->{'ref'}  = $member->{'ref'};
                                    ${$relation_ptr->{'role_platform'}}[$role_platform_index]->{'role'} = $member->{'role'};
                                    $role_platform_index++;
                                } elsif ( $member->{'role'} =~ m/^stop/ ) {
                                    ${$relation_ptr->{'role_stop'}}[$role_stop_index]->{'type'} = $member->{'type'};
                                    ${$relation_ptr->{'role_stop'}}[$role_stop_index]->{'ref'}  = $member->{'ref'};
                                    ${$relation_ptr->{'role_stop'}}[$role_stop_index]->{'role'} = $member->{'role'};
                                    $role_stop_index++;
                                }
                            }
                        }
                    }
                    if ( $show_operators ) {
                        if ( $relation_ptr->{'tag'}->{'operator'} ) {
                            $seen_operators{$relation_ptr->{'tag'}->{'operator'}}{$relation_id} = 1;
                        }
                        else {
                            $seen_operators{'__unset_operator__'}->{$relation_id} = 1;
                        }
                    }
                } elsif ( $verbose ) {
                    ; #printf STDERR "%s relation_ptr not set for relation id %s\n", get_time(), $relation_id;
                }
            } else {
                #printf STDERR "%s Suspicious: unset '%s' for relation id %s\n", get_time(), $type, $relation_id;
                $suspicious_relations{$relation_id} = 1;
            }
        } elsif ( $type eq 'multipolygon' ) {
            #
            # analyze multipolygon relations
            #
            if ( $RELATIONS{$relation_id}->{'tag'}->{'public_transport'}               &&
                 $RELATIONS{$relation_id}->{'tag'}->{'public_transport'} eq 'platform'    ) {
                $platform_multipolygon_relations{$relation_id} = $RELATIONS{$relation_id};
            } else {
                #printf STDERR "%s Suspicious: wrong type=multipolygon (not public_transport=platform) for relation id %s\n", get_time(), $relation_id;
                $suspicious_relations{$relation_id} = 1;
            }
        } elsif ($type eq 'public_transport' ) {
            #
            # analyze public_transport relations (stop_area, stop_area_group), not of interest though for the moment
            #
            if ( $RELATIONS{$relation_id}->{'tag'}->{'public_transport'}                  &&
                 $RELATIONS{$relation_id}->{'tag'}->{'public_transport'} =~ m/^stop_area/    ) {
                ;
            } else {
                #printf STDERR "%s Suspicious: wrong type=public_transport (not public_transport=stop_area) for relation id %s\n", get_time(), $relation_id;
                $suspicious_relations{$relation_id} = 1;
            }
        } elsif ($type eq 'network' ) {
            #
            # collect network relations (collection of public_transport relations), not of interest though for the moment and against the rule (relations are not categories)
            #
            my $well_known = undef;
            if ( $RELATIONS{$relation_id}->{'tag'}->{'network'} ) {
                my $network = $RELATIONS{$relation_id}->{'tag'}->{'network'};
                foreach my $nt ( @well_known_network_types )
                {
                    if ( $network eq $nt ) {
                        printf STDERR "%s Skipping well known network type: %s\n", get_time(), $network       if ( $debug );
                        $have_seen_well_known_network_types{$network} = 1;
                        $well_known = $network;
                        last;
                    }
                }
            }
            if ( !defined($well_known) ) {
                $suspicious_relations{$relation_id} = 1;
            }
        } else {
            #printf STDERR "%s Suspicious: unhandled type '%s' for relation id %s\n", get_time(), $type, $relation_id;
            my $well_known = undef;
            foreach my $ot ( @well_known_other_types )
            {
                if ( $type eq $ot ) {
                    printf STDERR "%s Skipping well known other type: %s\n", get_time(), $type       if ( $debug );
                    $have_seen_well_known_other_types{$type} = 1;
                    $well_known = $type;
                    last;
                }
            }
            if ( !defined($well_known) ) {
                $suspicious_relations{$relation_id} = 1;
            }
        }
    } else {
        #printf STDERR "%s Suspicious: unset 'type' for relation id %s\n", get_time(), $relation_id;
        $suspicious_relations{$relation_id} = 1;
    }
}

$number_of_positive_relations               = scalar( keys ( %{$PT_relations_with_ref{'positive'}} ) );
$number_of_negative_relations               = scalar( keys ( %{$PT_relations_with_ref{'negative'}} ) );
$number_of_life_cycle_prefix_relations      = scalar( keys ( %{$PT_relations_with_ref{'life-cycle-prefix'}} ) );
$number_of_suspicious_relations             = scalar( keys ( %suspicious_relations ) );
$number_of_platform_multipolygon_relations  = scalar( keys ( %platform_multipolygon_relations ) );
$number_of_relations_without_ref            = scalar( keys ( %PT_relations_without_ref ) );

if ( $verbose ) {
    printf STDERR "%s Relations converted: %d, route_relations: %d, platform_mp_relations: %d, positive: %d, negative: %d, life-cycle-prefix: %d, w/o ref: %d, suspicious: %d, excluded: %d\n",
                   get_time(),
                   $number_of_relations,
                   $number_of_route_relations,
                   $number_of_platform_multipolygon_relations,
                   $number_of_positive_relations,
                   $number_of_negative_relations,
                   $number_of_life_cycle_prefix_relations,
                   $number_of_relations_without_ref,
                   $number_of_suspicious_relations,
                   $number_of_excluded_relations;
}


#############################################################################################
#
# if there are ways, lets convert them
#
#############################################################################################

if ( $xml_has_ways ) {
    printf STDERR "%s Converting ways\n", get_time()       if ( $verbose );

    foreach $way_id ( keys ( %WAYS ) ) {

        $number_of_ways++;

        $WAYS{$way_id}->{'first_node'} = ${$WAYS{$way_id}->{'chain'}}[0];
        $WAYS{$way_id}->{'last_node'}  = ${$WAYS{$way_id}->{'chain'}}[$#{$WAYS{$way_id}->{'chain'}}];

        #
        # lets categorize the way as member or route or platform or ...
        #
        if ( exists($WAYS{$way_id}->{'tag'}->{'public_transport'})       &&
             $WAYS{$way_id}->{'tag'}->{'public_transport'} eq 'platform'    ) {
            $platform_ways{$way_id} = $WAYS{$way_id};
            $number_of_platformways++;
            $platform_ways{$way_id}->{'is_area'}   = 1 if ( $platform_ways{$way_id}->{'tag'}->{'area'} && $platform_ways{$way_id}->{'tag'}->{'area'} eq 'yes' );
            #printf STDERR "WAYS{%s} is a platform\n", $way_id;
        } else { #if ( ($WAYS{$way_id}->{'tag'}->{'highway'}                &&
               #  $WAYS{$way_id}->{'tag'}->{'highway'} ne 'platform')                               ||
               # ($WAYS{$way_id}->{'tag'}->{'railway'}                &&
               #  $WAYS{$way_id}->{'tag'}->{'railway'} =~ m/^rail|tram|subway|construction|razed$/) ||
               # ($WAYS{$way_id}->{'tag'}->{'route'}                  &&
               #  $WAYS{$way_id}->{'tag'}->{'route'} =~ m/^ferry$/)                                     ) {
            $route_ways{$way_id} = $WAYS{$way_id};
            $number_of_routeways++;
            if ( $WAYS{$way_id}->{'first_node'} && $WAYS{$way_id}->{'last_node'} && $WAYS{$way_id}->{'first_node'}  == $WAYS{$way_id}->{'last_node'} ) {
                $WAYS{$way_id}->{'is_roundabout'} = 1;
            }
            #printf STDERR "WAYS{%s} is a highway\n", $way_id;
        } #else {
        #    printf STDERR "Unmatched way type for way: %s\n", $way_id;
        #}

        map { $NODES{$_}->{'member_of_way'}->{$way_id} = 1 if ( exists($NODES{$_}) ); } @{$WAYS{$way_id}->{'chain'}};
    }

    if ( $verbose ) {
        printf STDERR "%s Ways converted: %d, route_ways: %d, platform_ways: %d\n",
                       get_time(), $number_of_ways, $number_of_routeways, $number_of_platformways;
    }
}


#############################################################################################
#
# if there are nodes, lets convert them
#
#############################################################################################

if ( $xml_has_nodes ) {
    printf STDERR "%s Converting nodes\n", get_time()       if ( $verbose );

    foreach $node_id ( keys ( %NODES ) ) {

        $number_of_nodes++;

        #
        # lets categorize the node as stop_position or platform or ...
        #
        if ( $NODES{$node_id} && exists($NODES{$node_id}->{'id'}) && exists($NODES{$node_id}->{'lat'}) && exists($NODES{$node_id}->{'lon'})) {
            if ( $NODES{$node_id}->{'tag'}->{'public_transport'}                    &&
                $NODES{$node_id}->{'tag'}->{'public_transport'} eq 'platform'    ) {
                $platform_nodes{$node_id} = $NODES{$node_id};
                $number_of_platformnodes++;
            } elsif ( $NODES{$node_id}->{'tag'}->{'public_transport'}                    &&
                    $NODES{$node_id}->{'tag'}->{'public_transport'} eq 'stop_position'    ) {
                $stop_nodes{$node_id} = $NODES{$node_id};
                $number_of_stop_positions++;
            } else {
                ; # printf STDERR "Other type for node: %s\n", $node_id if ( $debug );
            }
        }
    }

    if ( $verbose ) {
        printf STDERR "%s Nodes converted: %d, platform_nodes: %d, stop_positions: %d\n",
                       get_time(), $number_of_nodes, $number_of_platformnodes, $number_of_stop_positions;
    }
}


#############################################################################################
#
# output section begins here
#
#############################################################################################

printInitialHeader( $page_title, $osm_base, $areas  );


#############################################################################################
#
# now we print the list of all lines according to the list given by a CSV file
#
#############################################################################################

printf STDERR "%s Printing positives\n", get_time()       if ( $verbose );
$number_of_positive_relations = 0;

if ( scalar( @RouteList ) ) {

    $section = 'positive';

    my $table_headers_printed           = 0;
    my @list_of_matching_relation_ids   = ();
    my $number_of_matching_entries      = 0;
    my $CheckNetwork                    = '';

    my @start_columns                   = ( 'name', 'type', 'relation' );
    my @show_also_columns               = ();
    my @end_columns                     = ( 'PTv', 'issues', 'notes'   );

    if ( $table_show_also ) {
        my %columns_hash                    = ();
        map { $columns_hash{$_} = 1; } ( @start_columns, @end_columns );
        map { push(@show_also_columns,$_) unless ( $columns_hash{$_} ) } split(',', $table_show_also );
    }

    printTableInitialization( @start_columns, @show_also_columns, @end_columns );

    foreach my $entryref ( @RouteList ) {

        #printf STDERR "Entry: type = %s\n", $entryref->{'type'};

        if ( exists($entryref->{'type'}) && $entryref->{'type'} eq 'route' ) {

            printf STDERR "    ref = %s, ref-or-list = '%s', ref-and-list = '%s', route = %s, comment = %s, from = %s, to = %s, operator = %s, gtfs-feed = %s, gtfs-route_id = %s, gtfs-release-date = %s\n", $entryref->{'ref'}, jointext( ', ', @{$entryref->{'ref-or-list'}} ), jointext( ', ', @{$entryref->{'ref-and-list'}} ), $entryref->{'route'}, $entryref->{'comment'}, $entryref->{'from'}, $entryref->{'to'}, $entryref->{'operator'}, $entryref->{'gtfs-feed'}, $entryref->{'gtfs-route-id'}, $entryref->{'gtfs-release-date'}  if ( $debug );

            if ( $table_headers_printed == 0 ) {
                printTableHeader();
                $table_headers_printed++;
            }

            @list_of_matching_relation_ids = SearchMatchingRelations(   'SearchListRef'             =>  $PT_relations_with_ref{$section},
                                                                        'EntryRef'                  =>  $entryref,
                                                                     );

            $number_of_matching_entries = scalar @list_of_matching_relation_ids;

            if ( $number_of_matching_entries ) {

                for ( my $i=0; $i < $number_of_matching_entries; $i++ ) {
                    $relation_id  = $list_of_matching_relation_ids[$i];
                    $relation_ptr = $RELATIONS{$relation_id};

                    printf STDERR "%s Found: Relation-ID %s, Type: %s, Ref: %s, RouteType: %s\n", get_time(), $relation_id, $RELATIONS{$relation_id}->{'tag'}->{'type'}, $RELATIONS{$relation_id}->{'tag'}->{'ref'}, $RELATIONS{$relation_id}->{'tag'}->{$RELATIONS{$relation_id}->{'tag'}->{'type'}}    if ( $debug );

                    if ( $i == 0 ) {
                        my $gtfs_csv_based_scores = undef;

                        if ( $check_against_gtfs && $check_against_gtfs =~ m/csv/ && $entryref->{'gtfs-feed'} && $entryref->{'gtfs-route-id'} ) {
                            $gtfs_csv_based_scores = GTFS::GTFSvsOSM::getCSVbasedScores( $entryref->{'gtfs-feed'},
                                                                                                $entryref->{'gtfs-release-date'},
                                                                                                $entryref->{'gtfs-route-id'},
                                                                                                \@list_of_matching_relation_ids
                                                                                              );
                        }

                        printTableSubHeader( 'ref-or-list'       => $entryref->{'ref-or-list'},              # is a pointer to an array: ('23') or also ('43', 'E43') for multiple 'ref' values
                                             'network'           => $relation_ptr->{'tag'}->{'network'},     # take 'network' value from first relation, undef outside this for-loop
                                             'operator'          => $relation_ptr->{'tag'}->{'operator'},    # take 'operator' value from first relation, undef outside this for-loop
                                             'pt_type'           => $entryref->{'route'},
                                             'colour'            => $relation_ptr->{'tag'}->{'colour'},      # take 'colour' value from first relation, undef outside this for-loop
                                             'colour:text'       => $relation_ptr->{'tag'}->{'colour:text'}, # take 'colour:text' value from first relation, undef outside this for-loop
                                             'CSV-Comment'       => $entryref->{'comment'},
                                             'CSV-From'          => $entryref->{'from'},
                                             'CSV-From-List'     => $entryref->{'from-list'},
                                             'CSV-To'            => $entryref->{'to'},
                                             'CSV-To-List'       => $entryref->{'to-list'},
                                             'CSV-Operator'      => $entryref->{'operator'},
                                             'GTFS-Feed'         => $entryref->{'gtfs-feed'},
                                             'GTFS-Route-Id'     => $entryref->{'gtfs-route-id'},
                                             'GTFS-Release-Date' => $entryref->{'gtfs-release-date'},
                                             'GTFS-Scores'       => $gtfs_csv_based_scores,
                                             'relation'          => $relation_id
                                           );
                    }

                    @{$relation_ptr->{'__issues__'}} = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
                    @{$relation_ptr->{'__notes__'}}  = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
                    @{$relation_ptr->{'__GTFS__'}}   = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)

                    $status = analyze_environment( \@list_of_matching_relation_ids, $entryref->{'ref-or-list'}, $relation_ptr->{'tag'}->{'type'}, $entryref->{'route'}, $relation_id );

                    $status = analyze_relation( $relation_ptr, $relation_id, $entryref );

                    printTableLine( 'ref'           =>    $relation_ptr->{'tag'}->{'ref'},
                                    'relation'      =>    $relation_id,
                                    'type'          =>    $relation_ptr->{'tag'}->{'type'},
                                    'route_type'    =>    $entryref->{'route'},
                                    'name'          =>    $relation_ptr->{'tag'}->{'name'},
                                    'network'       =>    $relation_ptr->{'tag'}->{'network'},
                                    'operator'      =>    $relation_ptr->{'tag'}->{'operator'},
                                    'from'          =>    $relation_ptr->{'tag'}->{'from'},
                                    'via'           =>    $relation_ptr->{'tag'}->{'via'},
                                    'to'            =>    $relation_ptr->{'tag'}->{'to'},
                                    'PTv'           =>    $relation_ptr->{'tag'}->{'public_transport:version'},
                                    'issues'        =>    $relation_ptr->{'__issues__'},
                                    'notes'         =>    $relation_ptr->{'__notes__'}
                                  );
                    $relation_ptr->{'__printed__'}++;
                    $number_of_positive_relations++;

                    $CheckNetwork = $relation_ptr->{'tag'}->{'network'} || '__unset_network__';
                    if ( exists($unused_networks{$CheckNetwork}) && exists($unused_networks{$CheckNetwork}->{$relation_id}) ) {
                        delete( $unused_networks{$CheckNetwork}->{$relation_id} );
                        $added_networks{$CheckNetwork}->{$relation_id} = 0;
                    }
                }
            } else {
                #
                # we do not have a line which fits the requested 'ref' and 'route_type' combination
                #
                printTableSubHeader( 'ref-or-list'       => $entryref->{'ref-or-list'},
                                     'pt_type'           => $entryref->{'route'},
                                     'CSV-Comment'       => $entryref->{'comment'},
                                     'CSV-From'          => $entryref->{'from'},
                                     'CSV-From-List'     => $entryref->{'from-list'},
                                     'CSV-To'            => $entryref->{'to'},
                                     'CSV-To-List'       => $entryref->{'to-list'},
                                     'CSV-Operator'      => $entryref->{'operator'},
                                     'GTFS-Feed'         => $entryref->{'gtfs-feed'},
                                     'GTFS-Route-Id'     => $entryref->{'gtfs-route-id'},
                                     'GTFS-Release-Date' => $entryref->{'gtfs-release-date'},
                                   );


                if ( $entryref->{'ref-or-list'} ) {
                    printTableLine( 'issues' => issue('route.not_in_data_ref', list_msg('or_ref',@{$entryref->{'ref-or-list'}}), $entryref->{'route'}) );
                } else {
                    printTableLine( 'issues' => issue('route.not_in_data_ref', '???', $entryref->{'route'}) );
                }
            }
        } elsif ( exists($entryref->{'type'}) && $entryref->{'type'} eq 'header' ) {
            printf STDERR "    header = %s\n", $entryref->{'header'}        if ( $debug );
            printTableFooter()                                              if ( $table_headers_printed );
            $table_headers_printed = 0;
            printHeader( $entryref->{'header'}, $entryref->{'level'} );
        } elsif ( exists($entryref->{'type'}) && $entryref->{'type'} eq 'text' ) {
            printf STDERR "    text = %s\n", $entryref->{'text'}            if ( $debug );
            printTableFooter()                                              if ( $table_headers_printed );
            $table_headers_printed = 0;
            printText( $entryref->{'text'} );
        } elsif ( exists($entryref->{'type'}) && $entryref->{'type'} eq 'reserved' ) {
            printf STDERR "    reserved = %s\n", $entryref->{'reserved'}    if ( $debug );
            printTableFooter()                                              if ( $table_headers_printed );
            $table_headers_printed = 0;
            printText( '' );
            printText( $entryref->{'reserved'} );
            printText( '' );
        } elsif ( exists($entryref->{'type'}) && $entryref->{'type'} eq 'ignore' ) {
            printf STDERR "%s %s\n", get_time(), $entryref->{'ignore'};
        } elsif ( exists($entryref->{'type'}) && $entryref->{'type'} eq 'error' ) {
            printf STDERR "    error = %s\n", $entryref->{'error'}          if ( $debug );
            if ( $table_headers_printed == 0 ) {
                printTableHeader();
                $table_headers_printed++;
            }
            printTableSubHeader( 'ref' => $entryref->{'ref'} );
            printTableLine( 'issues' => $entryref->{'error'} );
        } else {
            printf STDERR "%s Internal error: ref and route_type not set in CSV file. %d\n", get_time(), $entryref->{'NR'};
        }
    }

    printTableFooter()  if ( $table_headers_printed );

    printFooter();

}

printf STDERR "%s Printed positives: %d\n", get_time(), $number_of_positive_relations       if ( $verbose );


#############################################################################################
#
# now we print the list of all unassigned relations/lines that could not be associated correctly (multiple entries for same ref/type values and ...)
#
#############################################################################################

printf STDERR "%s Printing unassigned\n", get_time()       if ( $verbose );
$number_of_unassigned_relations = 0;

if ( scalar( @RouteList ) ) {

    $section = 'positive';

    my $CheckNetwork = '';
    my @relation_ids = ();

    foreach $ref ( sort( keys( %{$PT_relations_with_ref{$section}} ) ) ) {
        foreach $type ( reverse ( sort( keys( %{$PT_relations_with_ref{$section}->{$ref}} ) ) ) ) {
            foreach $route_type ( sort( keys( %{$PT_relations_with_ref{$section}->{$ref}->{$type}} ) ) ) {
                foreach $relation_id ( sort( keys( %{$PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}} ) ) ) {
                    if ( $PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}->{$relation_id}->{'__printed__'} < 1 ) {
                        push( @relation_ids, $relation_id );
                    }
                }
            }
        }
    }

    if ( scalar(@relation_ids) ) {

        my @columns = ( 'ref', 'relation', 'type', 'route_type', 'name', 'network', 'operator', 'from', 'via', 'to', 'PTv', 'issues', 'notes' );

        printTableInitialization( @columns );

        # xgettext: This section will list all routes which could not be clearly assigned because the combination of "ref;type" appears more than once and information like 'operator', 'from' and 'to' is missing
        printTopic( 'unassigned' );
        printTableHeader();

        foreach $relation_id ( @relation_ids ) {
            $relation_ptr = $RELATIONS{$relation_id};

            @{$relation_ptr->{'__issues__'}} = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
            @{$relation_ptr->{'__notes__'}}  = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
            @{$relation_ptr->{'__GTFS__'}}   = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)

            $status = analyze_relation( $relation_ptr, $relation_id );

            printTableLine( 'ref'           =>    $relation_ptr->{'tag'}->{'ref'},
                            'relation'      =>    $relation_id,
                            'type'          =>    $relation_ptr->{'tag'}->{'type'},
                            'route_type'    =>    $relation_ptr->{'tag'}->{$relation_ptr->{'tag'}->{'type'}},
                            'name'          =>    $relation_ptr->{'tag'}->{'name'},
                            'network'       =>    $relation_ptr->{'tag'}->{'network'},
                            'operator'      =>    $relation_ptr->{'tag'}->{'operator'},
                            'from'          =>    $relation_ptr->{'tag'}->{'from'},
                            'via'           =>    $relation_ptr->{'tag'}->{'via'},
                            'to'            =>    $relation_ptr->{'tag'}->{'to'},
                            'PTv'           =>    $relation_ptr->{'tag'}->{'public_transport:version'},
                            'issues'        =>    $relation_ptr->{'__issues__'},
                            'notes'         =>    $relation_ptr->{'__notes__'}
                          );
            $number_of_unassigned_relations++;

            $CheckNetwork = $relation_ptr->{'tag'}->{'network'} || '__unset_network__';
            if ( exists($unused_networks{$CheckNetwork}) && exists($unused_networks{$CheckNetwork}->{$relation_id}) ) {
                delete( $unused_networks{$CheckNetwork}->{$relation_id} );
                $added_networks{$CheckNetwork}->{$relation_id} = 0;
            }
        }

        printTableFooter();

    }
}

printf STDERR "%s Printed unassigned: %d\n", get_time(), $number_of_unassigned_relations       if ( $verbose );


#############################################################################################
#
# now we print the list of all remainig relations/lines that could not be associated or when there was no csv file
#
#############################################################################################

printf STDERR "%s Printing others\n", get_time()       if ( $verbose );
$number_of_negative_relations = 0;

my @line_refs = ();

$section = 'negative';
@line_refs = sort( keys( %{$PT_relations_with_ref{$section}} ) );

if ( scalar(@line_refs) ) {
    my $route_type_lines = 0;
    my $CheckNetwork     = '';

    my @columns = ( 'ref', 'relation', 'type', 'name', 'network', 'operator', 'from', 'via', 'to', 'PTv', 'issues', 'notes' );

    printTableInitialization( @columns );

    printTopic( 'lines' );


    foreach $route_type ( @supported_route_types ) {

        $route_type_lines = 0;
        foreach $ref ( @line_refs ) {
            foreach $type ( 'route_master', 'route' ) {
                $route_type_lines += scalar(keys(%{$PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}}));
            }
        }
        if ( $route_type_lines ) {
            printRouteType( $route_type );
            printTableHeader();
            foreach $ref ( @line_refs ) {
                foreach $type ( 'route_master', 'route' ) {
                    foreach $relation_id ( sort( { $PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}->{$a}->{'__sort_name__'} cmp
                                                   $PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}->{$b}->{'__sort_name__'}     }
                                                 keys(%{$PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}})) ) {
                        $relation_ptr = $PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}->{$relation_id};

                        @{$relation_ptr->{'__issues__'}} = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
                        @{$relation_ptr->{'__notes__'}}  = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
                        @{$relation_ptr->{'__GTFS__'}}   = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)

                        $status = analyze_relation( $relation_ptr, $relation_id );

                        printTableLine( 'ref'           =>    $relation_ptr->{'tag'}->{'ref'},
                                        'relation'      =>    $relation_id,
                                        'type'          =>    $type,
                                        'route_type'    =>    $route_type,
                                        'name'          =>    $relation_ptr->{'tag'}->{'name'},
                                        'network'       =>    $relation_ptr->{'tag'}->{'network'},
                                        'operator'      =>    $relation_ptr->{'tag'}->{'operator'},
                                        'from'          =>    $relation_ptr->{'tag'}->{'from'},
                                        'via'           =>    $relation_ptr->{'tag'}->{'via'},
                                        'to'            =>    $relation_ptr->{'tag'}->{'to'},
                                        'PTv'           =>    $relation_ptr->{'tag'}->{'public_transport:version'},
                                        'issues'        =>    $relation_ptr->{'__issues__'},
                                        'notes'         =>    $relation_ptr->{'__notes__'}
                                      );
                        $number_of_negative_relations++;

                        $CheckNetwork = $relation_ptr->{'tag'}->{'network'} || '__unset_network__';
                        if ( exists($unused_networks{$CheckNetwork}) && exists($unused_networks{$CheckNetwork}->{$relation_id}) ) {
                            delete( $unused_networks{$CheckNetwork}->{$relation_id} );
                            $added_networks{$CheckNetwork}->{$relation_id} = 0;
                        }
                    }
                }
            }
            printTableFooter();
        }
    }
}

printf STDERR "%s Printed others: %d\n", get_time(), $number_of_negative_relations       if ( $verbose );


#############################################################################################
#
# now we print the routes/route-masters having no 'ref'
#
#############################################################################################

printf STDERR "%s Printing those w/o 'ref'\n", get_time()       if ( $verbose );
$number_of_relations_without_ref = 0;
$section = 'no-ref';

my @route_types = sort( keys( %PT_relations_without_ref ) );

if ( scalar(@route_types) ) {

    my @columns = ( 'relation', 'type', 'name', 'network', 'operator', 'from', 'via', 'to', 'PTv', 'issues', 'notes' );

    printTableInitialization( @columns );

    printTopic( 'lines_without_ref' );

    foreach $route_type ( @route_types ) {
        printRouteType( $route_type );
        printTableHeader();
        foreach $relation_id ( sort( { $PT_relations_without_ref{$route_type}->{$a}->{'__sort_name__'} cmp
                                       $PT_relations_without_ref{$route_type}->{$b}->{'__sort_name__'}     }
                                     keys(%{$PT_relations_without_ref{$route_type}})) ) {
            $relation_ptr = $PT_relations_without_ref{$route_type}->{$relation_id};

            @{$relation_ptr->{'__issues__'}} = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
            @{$relation_ptr->{'__notes__'}}  = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
            @{$relation_ptr->{'__GTFS__'}}   = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)

            $status = analyze_relation( $relation_ptr, $relation_id );

            printTableLine( 'relation'      =>    $relation_id,
                            'type'          =>    $relation_ptr->{'tag'}->{'type'},
                            'route_type'    =>    $route_type,
                            'name'          =>    $relation_ptr->{'tag'}->{'name'},
                            'network'       =>    $relation_ptr->{'tag'}->{'network'},
                            'operator'      =>    $relation_ptr->{'tag'}->{'operator'},
                            'from'          =>    $relation_ptr->{'tag'}->{'from'},
                            'via'           =>    $relation_ptr->{'tag'}->{'via'},
                            'to'            =>    $relation_ptr->{'tag'}->{'to'},
                            'PTv'           =>    $relation_ptr->{'tag'}->{'public_transport:version'},
                            'issues'        =>    $relation_ptr->{'__issues__'},
                            'notes'         =>    $relation_ptr->{'__notes__'}
                          );
            $number_of_relations_without_ref++;
        }
        printTableFooter();
    }
}

printf STDERR "%s Printed those w/o 'ref': %d\n", get_time(), $number_of_relations_without_ref       if ( $verbose );


#############################################################################################
#
# now we print the list of all relations/lines that have a life-cycle prefix: '*:route_master' or '*:route'
#
#############################################################################################

printf STDERR "%s Printing those with life-cycle prefix\n", get_time()       if ( $verbose );
$number_of_life_cycle_prefix_relations = 0;

@line_refs = ();

$section = 'life-cycle-prefix';
@line_refs = sort( keys( %{$PT_relations_with_ref{$section}} ) );

if ( scalar(@line_refs) ) {
    my $route_type_lines = 0;
    my $CheckNetwork     = '';

    my @columns = ( 'ref', 'relation', 'type', 'life-cycle-prefix', 'name', 'network', 'operator', 'from', 'via', 'to', 'PTv', 'issues', 'notes' );

    printTableInitialization( @columns );

    printTopic( 'life_cycle_prefix' );


    foreach $route_type ( @supported_route_types ) {

        $route_type_lines = 0;
        foreach $ref ( @line_refs ) {
            foreach $type ( 'route_master', 'route' ) {
                $route_type_lines += scalar(keys(%{$PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}}));
            }
        }
        if ( $route_type_lines ) {
            printRouteType( $route_type );
            printTableHeader();
            foreach $ref ( @line_refs ) {
                foreach $type ( 'route_master', 'route' ) {
                    foreach $relation_id ( sort( { $PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}->{$a}->{'__sort_name__'} cmp
                                                   $PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}->{$b}->{'__sort_name__'}     }
                                                 keys(%{$PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}})) ) {
                        $relation_ptr = $PT_relations_with_ref{$section}->{$ref}->{$type}->{$route_type}->{$relation_id};

                        @{$relation_ptr->{'__issues__'}} = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
                        @{$relation_ptr->{'__notes__'}}  = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)
                        @{$relation_ptr->{'__GTFS__'}}   = ();  # just in case that this route has already been analyzed before (--multiple-ref-type-enries=allow)

                        $status = analyze_relation( $relation_ptr, $relation_id );

                        printTableLine( 'ref'               =>    $relation_ptr->{'tag'}->{'ref'},
                                        'relation'          =>    $relation_id,
                                        'type'              =>    $type,
                                        'life-cycle-prefix' =>    $relation_ptr->{'life-cycle-prefix'},
                                        'route_type'        =>    $route_type,
                                        'name'              =>    $relation_ptr->{'tag'}->{'name'},
                                        'network'           =>    $relation_ptr->{'tag'}->{'network'},
                                        'operator'          =>    $relation_ptr->{'tag'}->{'operator'},
                                        'from'              =>    $relation_ptr->{'tag'}->{'from'},
                                        'via'               =>    $relation_ptr->{'tag'}->{'via'},
                                        'to'                =>    $relation_ptr->{'tag'}->{'to'},
                                        'PTv'               =>    $relation_ptr->{'tag'}->{'public_transport:version'},
                                        'issues'            =>    $relation_ptr->{'__issues__'},
                                        'notes'             =>    $relation_ptr->{'__notes__'}
                                      );
                        $number_of_life_cycle_prefix_relations++;

                        $CheckNetwork = $relation_ptr->{'tag'}->{'network'} || '__unset_network__';
                        if ( exists($unused_networks{$CheckNetwork}) && exists($unused_networks{$CheckNetwork}->{$relation_id}) ) {
                            delete( $unused_networks{$CheckNetwork}->{$relation_id} );
                            $added_networks{$CheckNetwork}->{$relation_id} = 0;
                        }
                    }
                }
            }
            printTableFooter();
        }
    }
}

printf STDERR "%s Printed those with life-cycle prefix: %d\n", get_time(), $number_of_life_cycle_prefix_relations       if ( $verbose );


#############################################################################################
#
# now we print the list of explicitely excluded relations
#
#############################################################################################

printf STDERR "%s Printing excluded relations\n", get_time()       if ( $verbose );

if ( scalar(keys(%excluded_key_value_relations)) ) {

    printTopic( 'excluded' );

    printExcludedRelations();
}

printf STDERR "%s Printed excluded relations\n", get_time()       if ( $verbose );


#############################################################################################
#
# now we print the list of all suspicious relations
#
#############################################################################################

printf STDERR "%s Printing suspicious\n", get_time()       if ( $verbose );

my @suspicious_relations       = sort( keys( %suspicious_relations ) );
my @print_suspicious_relations = ();
my @skip_suspicious_relations  = ();

if ( scalar(@suspicious_relations) ) {

    my $print_it = 0;

    foreach $relation_id ( @suspicious_relations ) {
        $relation_ptr = $RELATIONS{$relation_id};
        foreach my $tag ( keys ( %{$relation_ptr->{'tag'}} ) ) {
            $print_it     = 0;
            if ( $tag =~ m/^(platform|ref|local_ref|from|via|to|gtfs|ref_trips|route_ref|public_transport)$/i ) {
                $print_it = 1;
                last;
            } elsif (  $tag =~ m/type|boundary/i && $relation_ptr->{'tag'}->{$tag} =~ m/route|public_transport|platform|network/i ) {
                $print_it = 1;
                last;
            } elsif ( $tag =~ m/route/i ) {
                foreach my $supported ( @supported_route_types ) {
                    if ( $relation_ptr->{'tag'}->{$tag} =~ m/$supported/i ) {
                        $print_it = 1;
                        last;
                    }
                    last if ( $print_it );
                }
            } elsif ( $tag !~ m/name|fixme|comment|note|description|inscription/i && $relation_ptr->{'tag'}->{$tag} =~ m/route|stop_position|platform|stop_area|bus_stop/i ) {
                $print_it = 1;
                last;
            }
        }

        if ( $print_it ) {
            push( @print_suspicious_relations, $relation_id );
        } else {
            push( @skip_suspicious_relations, $relation_id );
        }
    }

    if ( scalar(@print_suspicious_relations) ) {

        printTableInitialization( 'relation', 'type', 'route_type', 'ref', 'name', 'network', 'operator', 'from', 'via', 'to', 'PTv', 'public_transport' );
        $section = 'suspicious';

        printTopic( 'morerelations' );

        printHintSuspiciousRelations();

        printTableHeader();

        foreach $relation_id ( @print_suspicious_relations ) {
            $relation_ptr = $RELATIONS{$relation_id};

            printTableLine( 'relation'          =>    $relation_id,
                            'type'              =>    getRelationType( $relation_ptr ),
                            'route_type'        =>    getRelationRouteType( $relation_ptr ),
                            'ref'               =>    $relation_ptr->{'tag'}->{'ref'},
                            'name'              =>    ( $relation_ptr->{'tag'}->{'name'} ) ? $relation_ptr->{'tag'}->{'name'} : ($opt_language && $relation_ptr->{'tag'}->{'name:'.$opt_language}) ? "'name:".$opt_language."' = '".$relation_ptr->{'tag'}->{'name:'.$opt_language}."'" : '',
                            'network'           =>    $relation_ptr->{'tag'}->{'network'},
                            'operator'          =>    $relation_ptr->{'tag'}->{'operator'},
                            'from'              =>    $relation_ptr->{'tag'}->{'from'},
                            'via'               =>    $relation_ptr->{'tag'}->{'via'},
                            'to'                =>    $relation_ptr->{'tag'}->{'to'},
                            'PTv'               =>    $relation_ptr->{'tag'}->{'public_transport:version'},
                            'public_transport'  =>    $relation_ptr->{'tag'}->{'public_transport'},
                        );
        }
    }
    printTableFooter();

    if  ( scalar(@skip_suspicious_relations) ) {
        printf STDERR "%s Not printed suspicious relations: %s\n", get_time(), jointext(' ',@skip_suspicious_relations);
    }
}

printf STDERR "%s Printed suspicious: %d out of %d candidates\n", get_time(), scalar(@print_suspicious_relations), scalar(@suspicious_relations)       if ( $verbose );


#############################################################################################
#
# now we print the list of all network values
#
#############################################################################################

printf STDERR "%s Printing network details\n", get_time()       if ( $verbose );

if ( scalar(keys(%used_networks)) || scalar(keys(%added_networks)) || scalar(keys(%unused_networks)) ) {

    printTopic( 'networkdetails' );

    if ( $network_long_regex || $network_short_regex ) {
        printHintNetworks();
    }

    printHintUsedNetworks();

    printHintAddedNetworks();

    printHintUnusedNetworks();
}

printf STDERR "%s Printed network details\n", get_time()       if ( $verbose );


#############################################################################################
#
# now we print the list of all operator values
#
#############################################################################################

if ( $show_operators ) {
    printf STDERR "%s Printing operator details\n", get_time()       if ( $verbose );

    if ( scalar(keys(%seen_operators)) ) {

        printTopic( 'operatordetails' );

        printHintSeenOperators();
    }

    printf STDERR "%s Printed operator details\n", get_time()       if ( $verbose );
}


#############################################################################################
#
# now we print the list of all referenced GTFS feeds
#
#############################################################################################

printf STDERR "%s Printing GTFS details\n", get_time()       if ( $verbose );

if ( scalar(keys(%gtfs_relation_info_from)) || scalar(keys(%gtfs_csv_info_from)) ) {

    printTopic( 'gtfsreferences' );

    printGtfsReferences();
}

printf STDERR "%s Printed GTFS details\n", get_time()       if ( $verbose );


#############################################################################################
#
# now we print the list conditional access tags
#
#############################################################################################

printf STDERR "%s Printing conditional access details\n", get_time()       if ( $verbose );

if ( scalar(keys(%conditional_access)) ) {

    printTopic( 'conditional_on_ways' );

    printConditionalAccessOnWays();
}

printf STDERR "%s Printed conditional access details\n", get_time()       if ( $verbose );


#############################################################################################
#
# Did we print anything
#
#############################################################################################


if ( $xml_has_relations == 0 ) {
    printRoutesList();
    printText( "No route relations found!");
}


#############################################################################################

printFinalFooter();

OSM::Geo::Summary();

if ( $check_against_gtfs ) {
    GTFS::GTFSvsOSM::Summary();
}

printf STDERR "%s Done ...\n", get_time()       if ( $verbose );


#############################################################################################

sub match_exclude {
    my $relation_id = shift;

    if ( $relation_ptr && defined($RELATIONS{$relation_id}) && defined($RELATIONS{$relation_id}->{'tag'}) ) {
        printf STDERR "Checking relation %s for 'exclude'\n", $relation_id       if ( $debug );
        foreach my $key ( keys( %excluded_key_value_relations ) ) {
            printf STDERR "Checking relation %s for key = %s\n", $relation_id, $key      if ( $debug );
            if ( defined($RELATIONS{$relation_id}->{'tag'}->{$key}) ) {
                foreach my $value (keys(%{$excluded_key_value_relations{$key}})) {
                    printf STDERR "Checking relation %s for key = %s and value = %s\n", $relation_id, $key, $value       if ( $debug );
                    if ( $RELATIONS{$relation_id}->{'tag'}->{$key} eq $value ) {
                        printf STDERR "Checking relation %s for key = %s and value = %s to be excluded\n", $relation_id, $key, $value       if ( $debug );
                        $excluded_key_value_relations{$key}{$value}{$relation_id} = 1;
                        return 'exclude';
                    }
                }
            }
        }
    } else {
        if ( $relation_id ) {
            if ( exists($RELATIONS{$relation_id}) ) {
                printf STDERR "%s Do not exclude realtion: %s - %s\n", get_time(), $relation_id, 'relation has no tags'      if ( $debug );
            } else {
                printf STDERR "%s Do not exclude realtion: %s - %s\n", get_time(), $relation_id, 'relation not found'      if ( $debug );
            }
        } else {
            printf STDERR "%s Do not exclude realtion: %s\n", get_time(), 'relation_id is not defined'      if ( $debug );
        }
    }

    return 'keep';
}


#############################################################################################

sub match_route_type {
    my $route_type = shift;
    my $rt         = undef;

    if ( $route_type ) {
        foreach my $rt ( @supported_route_types )
        {
            if ( $route_type eq $rt ) {
                printf STDERR "%s Keeping route type: %s\n", get_time(), $route_type       if ( $debug );
                return 'keep';
            } elsif ( $route_type =~ m/\Q$rt\E/ ) {
                printf STDERR "%s Suspicious route type: %s\n", get_time(), $route_type    if ( $debug );
                return 'suspicious';
            }
        }
        foreach my $rt ( @well_known_other_route_types )
        {
            if ( $route_type eq $rt ) {
                printf STDERR "%s Skipping well known other route type: %s\n", get_time(), $route_type       if ( $debug );
                $have_seen_well_known_other_route_types{$route_type} = 1;
                return 'well_known';
            }
        }
    }

    printf STDERR "%s Finally other route type: %s\n", get_time(), $route_type       if ( $debug );

    return 'other';
}


#############################################################################################

sub match_network {
    my $network = shift;

    if ( $network ) {
        if ( $network_long_regex || $network_short_regex ) {
            my $network_with = ';' . $network . ';';        # we match only with sourrounding ';', i.e. 'DB InterCity' does not match network='DB InterCityExpress'
                                                            # i.e. "Sénar Bus" does not match "Seine Sénar Bus"
            if ( $network_short_regex ) {
                foreach my $short_value ( split('\|',$network_short_regex) ) {
                    if ( $network_with =~ m/[;,]\s*(\Q$short_value\E)\s*[;,]\s*/ ) {
                        return 'keep short';
                    }
                }
            }
            if ( $network_long_regex ) {
                foreach my $long_value ( split('\|',$network_long_regex) ) {
                    if ( $network_with =~ m/[;,]\s*(\Q$long_value\E)\s*[;,]\s*/ ) {
                        return 'keep long';
                    }
                }
            }
            printf STDERR "%s Skipping network: %s\n", get_time(), $network        if ( $debug );
            return 'skip';
        }
    } else {
        if ( $strict_network ) {
            printf STDERR "%s Skipping unset network\n", get_time()                   if ( $debug );
            return 'skip';
        }
    }

    return 'keep';
}


#############################################################################################

sub match_operator {
    my $operator = shift;

    if ( $operator ) {
        if ( $operator_regex ) {
            if ( $operator !~ m/$operator_regex/   ) {
                printf STDERR "%s Skipping operator: %s\n", get_time(), $operator        if ( $debug );
                return 'skip';
            }
        }
    } else {
        if ( $strict_operator ) {
            printf STDERR "%s Skipping unset operator\n", get_time()                   if ( $debug );
            return 'skip';
        }
    }

    return 'keep';
}


#############################################################################################

sub match_ref_and_pt_type {
    my $ref             = shift;
    my $pt_type         = shift;

    if ( $ref ne '' && $pt_type ) {
        return 'keep positive'      if ( RoutesList::RefTypeCount( $ref, $pt_type ) );
    } else {
        printf STDERR "%s Skipping unset ref or unset type: %s/%s\n", get_time()        if ( $verbose );
        return 'skip';
    }
    printf STDERR "%s Keeping negative ref/type: %s/%s\n", get_time(), $ref, $pt_type   if ( $debug );
    return 'keep negative';
}


#############################################################################################
#
# return a list of matching route and route-master relations
#
#############################################################################################


sub SearchMatchingRelations {
    my %hash                        = ( @_ );

    my $SearchListRef               = $hash{'SearchListRef'};
    my $EntryRef                    = $hash{'EntryRef'};

    my $ExpRef                      = $EntryRef->{'ref'};
    my $ExpRefOrList                = $EntryRef->{'ref-or-list'};
    my $ExpRouteType                = $EntryRef->{'route'}                            || '';
    my $RelRef                      = undef;
    my $RelRouteType                = undef;
    my $RelOperator                 = undef;
    my $RelFrom                     = undef;
    my $RelTo                       = undef;
    my $RelVia                      = undef;
    my $RelColour                   = undef;
    my $match                       = undef;

    my @return_list                 = ();

    my %selected_route_masters      = ();
    my %selected_routes             = ();

    my @ExpRefOrArray               = ();
    my %ExpRefHash                  = ();

    if ( $ExpRefOrList ) {
        @ExpRefOrArray = @{$ExpRefOrList};
    } elsif ( $ExpRef || $ExpRef eq '0' ) {
        push( @ExpRefOrArray, $ExpRef );
    }

    map { $ExpRefHash{$_} = 1; } @ExpRefOrArray;

    if ( $SearchListRef ) {

        if ( scalar @ExpRefOrArray && $ExpRouteType ) {

            foreach my $ExpRefPart ( @ExpRefOrArray ) {

                my $relations_for_this_route_type = scalar(keys(%{$SearchListRef->{$ExpRefPart}->{'route_master'}->{$ExpRouteType}})) +
                                                    scalar(keys(%{$SearchListRef->{$ExpRefPart}->{'route'}->{$ExpRouteType}}));
                if ( $relations_for_this_route_type ) {

                    foreach my $type ( 'route', 'route_master' ) {
                        #
                        # check 'route' first
                        # so that in case of a need to check 'from' and 'to', 'route_master' can rely on 'route' information.
                        # i.e. if 'route' is selected, then it's 'route_master' also?
                        #
                        if ( $SearchListRef->{$ExpRefPart}->{$type} && $SearchListRef->{$ExpRefPart}->{$type}->{$ExpRouteType} ) {

                            foreach my $rel_id ( keys( %{$SearchListRef->{$ExpRefPart}->{$type}->{$ExpRouteType}} ) ) {

                                $RelRef         = defined($RELATIONS{$rel_id}->{'tag'}->{'ref'}) ? $RELATIONS{$rel_id}->{'tag'}->{'ref'} : '';
                                if ( $type eq 'route_master' ) {
                                    $RelRouteType   = $RELATIONS{$rel_id}->{'route_master_type_value'} || '';
                                } else {
                                    $RelRouteType   = $RELATIONS{$rel_id}->{'route_type_value'} || '';
                                }
                                $RelOperator    = $RELATIONS{$rel_id}->{'tag'}->{'operator'}         || '';
                                $RelFrom        = $RELATIONS{$rel_id}->{'tag'}->{'from'}             || '';
                                $RelTo          = $RELATIONS{$rel_id}->{'tag'}->{'to'}               || '';
                                $RelVia         = $RELATIONS{$rel_id}->{'tag'}->{'via'}              || '';
                                $RelColour      = $RELATIONS{$rel_id}->{'tag'}->{'colour'}           || '';

                                printf STDERR "%s Checking %s relation %s, 'ref' %s and 'operator' %s \n", get_time(), $type, $rel_id, $ExpRefPart, $RelOperator    if ( $debug );

                                $match  = RoutesList::RelationMatchesExpected(  'rel-id'                      => $rel_id,
                                                                                'rel-ref'                     => $RelRef,
                                                                                'rel-route-type'              => $RelRouteType,
                                                                                'rel-operator'                => $RelOperator,
                                                                                'rel-from'                    => $RelFrom,
                                                                                'rel-to'                      => $RelTo,
                                                                                'rel-via'                     => $RelVia,
                                                                                'rel-colour'                  => $RelColour,
                                                                                'EntryRef'                    => $EntryRef,
                                                                                'multiple_ref_type_entries'   => $multiple_ref_type_entries,
                                                                             );
                                printf STDERR "%s Checking == %s\n", get_time(), $match     if ( $debug );

                                if ( !$match ) {
                                    if ( $type eq 'route_master' ) {

                                        # route_masters usually don't have 'from' or 'to' set: let's try something different in case we don't have a direct match

                                        printf STDERR "%s Route-Master w/o values: %s\n", get_time(), $rel_id   if ( $debug );

                                        foreach my $member_rel_ref ( @{$RELATIONS{$rel_id}->{'route_master_relation'}} ) {
                                            printf STDERR "%s Route-Master w/o values: %s - check Member %s\n", get_time(), $rel_id, $member_rel_ref->{'ref'}   if ( $debug );
                                            if ( $selected_routes{$member_rel_ref->{'ref'}} ) {
                                                # member route has been selected, from and/or to match, so let's assume, the route_master matches as well
                                                $match = 1;
                                                last;
                                            }
                                        }
                                    }
                                }
                                if ( $match ) {
                                    if ( $type eq 'route_master' ) {
                                        $selected_route_masters{$rel_id} = 1;
                                    } else {
                                        $selected_routes{$rel_id} = 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    } else {
        printf STDERR "%s SearchMatchingRelations(): no Search List specified\n", get_time();
    }

    foreach my $rel_id ( keys( %selected_routes ) ) {

        # route_masters of selected routes also match, but check some basic settings first

        foreach my $route_master_rel_id ( keys ( %{$RELATIONS{$rel_id}->{'member_of_route_master'}} ) ) {
            printf STDERR "%s Route-Master Relations of selected Routes also match: %s - Master %s\n", get_time(), $rel_id, $route_master_rel_id   if ( $debug );
            if ( !exists($selected_route_masters{$route_master_rel_id})                           &&
                 $RELATIONS{$route_master_rel_id}                                                 &&
                 $RELATIONS{$route_master_rel_id}->{'tag'}                                        &&
                 $RELATIONS{$route_master_rel_id}->{'tag'}->{'type'}                              &&
                 $RELATIONS{$route_master_rel_id}->{'tag'}->{'type'}  eq 'route_master'           &&
                 $RELATIONS{$route_master_rel_id}->{'route_master_type_value'}                    &&
                 $RELATIONS{$route_master_rel_id}->{'route_master_type_value'} eq $ExpRouteType   &&
                 exists($RELATIONS{$route_master_rel_id}->{'tag'}->{'ref'})                       &&
                 $RELATIONS{$route_master_rel_id}->{'tag'}->{'ref'} ne ''                         &&
                 $ExpRefHash{$RELATIONS{$route_master_rel_id}->{'tag'}->{'ref'}}                      ) {
                printf STDERR "Add route_master %s of route %s\n", $route_master_rel_id, $rel_id   if ( $debug );
                $selected_route_masters{$route_master_rel_id} = 1;
            }
        }
    }
    foreach my $rel_id ( keys( %selected_route_masters ) ) {

        # members of selected route_masters also match, but check some basic settings first

        foreach my $member_rel_ref ( @{$RELATIONS{$rel_id}->{'route_master_relation'}} ) {
            printf STDERR "%s Relations of selected Route-Master also match: %s - Member %s\n", get_time(), $rel_id, $member_rel_ref->{'ref'}   if ( $debug );
            if ( !exists($selected_routes{$member_rel_ref->{'ref'}})                         &&
                 $RELATIONS{$member_rel_ref->{'ref'}}                                        &&
                 $RELATIONS{$member_rel_ref->{'ref'}}->{'tag'}                               &&
                 $RELATIONS{$member_rel_ref->{'ref'}}->{'tag'}->{'type'}                     &&
                 $RELATIONS{$member_rel_ref->{'ref'}}->{'tag'}->{'type'}    eq 'route'       &&
                 $RELATIONS{$member_rel_ref->{'ref'}}->{'route_type_value'}                  &&
                 $RELATIONS{$member_rel_ref->{'ref'}}->{'route_type_value'} eq $ExpRouteType &&
                 exists($RELATIONS{$member_rel_ref->{'ref'}}->{'tag'}->{'ref'})              &&
                 $RELATIONS{$member_rel_ref->{'ref'}}->{'tag'}->{'ref'} ne ''                &&
                 $ExpRefHash{$RELATIONS{$member_rel_ref->{'ref'}}->{'tag'}->{'ref'}}            ) {
                printf STDERR "Add member route %s of route_master %s\n", $member_rel_ref->{'ref'}, $rel_id   if ( $debug );
                $selected_routes{$member_rel_ref->{'ref'}} = 1;
            }
        }
    }

    map { push( @return_list, $_ ); } sort( { $RELATIONS{$a}->{'__sort_name__'} cmp $RELATIONS{$b}->{'__sort_name__'} } keys( %selected_route_masters ) );
    map { push( @return_list, $_ ); } sort( { $RELATIONS{$a}->{'__sort_name__'} cmp $RELATIONS{$b}->{'__sort_name__'} } keys( %selected_routes        ) );

    if ( $debug ) {
        map { printf STDERR "SearchMatchingRelations: Rel-ID = %s, type = %s, ref = %s, name = %s\n",
                                                               $_,
                                                                          $RELATIONS{$_}->{'tag'}->{'type'},
                                                                                    $RELATIONS{$_}->{'tag'}->{'ref'},
                                                                                                $RELATIONS{$_}->{'tag'}->{'name'};
            } sort( { $RELATIONS{$a}->{'__sort_name__'} cmp $RELATIONS{$b}->{'__sort_name__'} } keys( %selected_route_masters ) );
        map { printf STDERR "SearchMatchingRelations: Rel-ID = %s, type = %s, ref = %s, name = %s\n",
                                                               $_,
                                                                          $RELATIONS{$_}->{'tag'}->{'type'},
                                                                                    $RELATIONS{$_}->{'tag'}->{'ref'},
                                                                                                ($RELATIONS{$_}->{'tag'}->{'name'} || '');
            } sort( { $RELATIONS{$a}->{'__sort_name__'} cmp $RELATIONS{$b}->{'__sort_name__'} } keys( %selected_routes ) );
    }

    return ( @return_list );
}


#############################################################################################

sub analyze_environment {
    my $matching_ref    = shift;
    my $ref_or_list     = shift;
    my $type            = shift;
    my $route_type      = shift;
    my $relation_id     = shift;
    my $return_code     = 0;

    my $relation_ptr    = undef;
    my $env_ref         = undef;
    my %environment     = ();
    my $temptype        = undef;
    my $temproutetype   = undef;


    if ( $matching_ref && $ref_or_list && $type && $route_type && $relation_id ) {

        foreach my $relid ( @{$matching_ref} ) {
            $temptype       = $RELATIONS{$relid}->{'tag'}->{'type'};
            if ( $temptype =~ m/route_master$/ ) {
                $temproutetype  = $RELATIONS{$relid}->{'route_master_type_value'};
            } else {
                $temproutetype  = $RELATIONS{$relid}->{'route_type_value'};
           }
            $environment{'dummy'}->{$temptype}->{$temproutetype}->{$relid} = $RELATIONS{$relid};
        }
        $env_ref = $environment{'dummy'};

        $relation_ptr = $env_ref->{$type}->{$route_type}->{$relation_id};

        if ( $relation_ptr ) {

            if ( $type =~ m/route_master$/ ) {
                $return_code = analyze_route_master_environment( $env_ref, $ref_or_list, $type, $route_type, $relation_id );
            } elsif ( $type =~ m/route$/) {
                $return_code = analyze_route_environment( $env_ref, $ref_or_list, $type, $route_type, $relation_id );
            }
        }
    }

    return $return_code;
}


#############################################################################################

sub analyze_route_master_environment {
    my $env_ref         = shift;
    my $ref_or_list     = shift;
    my $type            = shift;
    my $route_type      = shift;
    my $relation_id     = shift;
    my $return_code     = 0;

    my $relation_ptr            = undef;
    my $number_of_route_masters = 0;
    my $number_of_routes        = 0;
    my $number_of_my_routes     = 0;
    my %my_routes               = ();
    my %allowed_refs            = ();
    my $masters_ref             = undef;
    my $members_ref             = undef;
    my $route_master_network    = undef;

    if ( $env_ref && $ref_or_list && $type && $type =~ m/route_master$/ && $route_type && $relation_id ) {

        # do we have more than one route_master here for this "ref_or_list" and "route_type"?
        $number_of_route_masters    = scalar( keys( %{$env_ref->{'route_master'}->{$route_type}} ) );

        # how many routes do we have at all for this "ref_or_list" and "route_type"?
        $number_of_routes           = scalar( keys( %{$env_ref->{'route'}->{$route_type}} ) );

        # reference to this relation, the route_master under examination
        $relation_ptr               = $env_ref->{'route_master'}->{$route_type}->{$relation_id};

        # if this is a route_master and PTv2 is set, then
        # 1. check route_master_relation number against number of 'route' relations below this ref_ref with same route_type (same number?)
        # 2. check 'route' relations and their 'relation_id' against the member list (do all 'route' members actually exist?)

        if ( $number_of_route_masters > 1 ) {
            #
            # that's OK if they belong to different 'network' ('network' has to be set though)
            # that's OK if they belong to same 'network' but are operated by different 'operator' ('operator' has to be set though)
            #
            my %networks            = ();
            my %operators           = ();
            my $num_of_networks     = 0;
            my $num_of_operators    = 0;
            my $temp_relation_ptr   = undef;
            foreach my $rel_id ( keys( %{$env_ref->{'route_master'}->{$route_type}} ) ) {
                $temp_relation_ptr = $env_ref->{'route_master'}->{$route_type}->{$rel_id};

                # how many routes are members of this route_master?
                $number_of_my_routes        += scalar( @{$temp_relation_ptr->{'route_master_relation'}} );

                foreach my $member_ref ( @{$temp_relation_ptr->{'route_master_relation'}} ) {
                    $my_routes{$member_ref->{'ref'}} = 1;
                }

                if ( $temp_relation_ptr->{'tag'}->{'network'} ) {
                    $networks{$temp_relation_ptr->{'tag'}->{'network'}} = 1;
                    #printf STDERR "analyze_route_master_environment(): network = %s\n", $temp_relation_ptr->{'tag'}->{'network'};
                }

                if ( $temp_relation_ptr->{'tag'}->{'operator'} ) {
                    $operators{$temp_relation_ptr->{'tag'}->{'operator'}} = 1;
                    #printf STDERR "analyze_route_master_environment(): operator = %s\n", $temp_relation_ptr->{'tag'}->{'operator'};
                }
            }

            $num_of_networks  = scalar( keys ( %networks  ) );
            $num_of_operators = scalar( keys ( %operators ) );
            #printf STDERR "analyze_route_master_environment(): num_of_networks = %s, num_of_operators = %s\n", $num_of_networks, $num_of_operators;
            if ( $num_of_networks < 2 && $num_of_operators < 2 ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('master.multiple') );
            }

            if ( $number_of_my_routes > $number_of_routes ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('master.more_routes', $number_of_route_masters, $number_of_my_routes, $number_of_routes) );
            } elsif ( $number_of_my_routes < $number_of_routes ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('master.fewer_routes', $number_of_route_masters, $number_of_my_routes, $number_of_routes) );
            }
        } else {
            # how many routes are members of this route_master?
            $number_of_my_routes        = scalar( @{$relation_ptr->{'route_master_relation'}} );

            if ( $number_of_my_routes > $number_of_routes ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('master.more_routes', $number_of_route_masters, $number_of_my_routes, $number_of_routes) );
            } elsif ( $number_of_my_routes < $number_of_routes ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('master.fewer_routes', $number_of_route_masters, $number_of_my_routes, $number_of_routes) );
            }
        }

        # check whether all my member routes actually exist, tell us which one does not
        foreach my $member_ref ( @{$relation_ptr->{'route_master_relation'}} ) {
            $my_routes{$member_ref->{'ref'}} = 1;
            if ( !defined($env_ref->{'route'}->{$route_type}->{$member_ref->{'ref'}}) ) {
                #
                # relation_id points to a route which has different 'ref' or does not exist in data set
                #
                if ( $RELATIONS{$member_ref->{'ref'}} && $RELATIONS{$member_ref->{'ref'}}->{'tag'} ) {
                    #
                    # relation is included in XML input file check for settings
                    #
                    if ( $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'type'} ) {

                        if ( $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'type'} eq 'route' ) {

                            if ( $relation_ptr->{'route_master_type_value'} && $RELATIONS{$member_ref->{'ref'}}->{'route_type_value'} ) {

                                if ( $relation_ptr->{'route_master_type_value'} eq $RELATIONS{$member_ref->{'ref'}}->{'route_type_value'} ) {

                                    if ( exists($RELATIONS{$relation_id}->{'tag'}->{'ref'}) ) {
                                        $masters_ref = $RELATIONS{$relation_id}->{'tag'}->{'ref'};
                                    }
                                    if ( exists($RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'ref'}) ) {
                                        foreach $members_ref ( @{$ref_or_list} ) {
                                            $allowed_refs{$members_ref} = 1;
                                        }
                                        $members_ref = $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'ref'};
                                        if ( $allowed_refs{$members_ref} ) {
                                            #
                                            # 'members_ref' is in the list, check for other problems
                                            #
                                            if ( $relation_ptr->{'tag'}->{'network'} && $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'network'} ) {

                                                $route_master_network = ';' . $relation_ptr->{'tag'}->{'network'} . ';';

                                                if ( $relation_ptr->{'tag'}->{'network'} eq $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'network'}  ||
                                                     $route_master_network =~ m/;\Q$RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'network'}\E;/          ) {

                                                    if ( $route_master_network =~ m/;\Q$RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'network'}\E;/  ) {
                                                        push( @{$relation_ptr->{'__notes__'}}, note('network.part_of_master_value', foreign($RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'network'}), foreign($relation_ptr->{'tag'}->{'network'}), printRelationTemplate($member_ref->{'ref'})) );
                                                    }

                                                    #printf STDERR "%s Route of Route-Master not found although 'ref' is valid and 'network' are equal. Route-Master: %s, Route: %s, 'ref': %s, 'network': %s\n", get_time(), $relation_id, $member_ref->{'ref'}, $members_ref, text_msg($relation_ptr->{'tag'}->{'network'});
                                                    if ( $relation_ptr->{'tag'}->{'operator'} && $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'operator'} ) {
                                                        if ( $relation_ptr->{'tag'}->{'operator'} eq $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'operator'} ) {
                                                            #printf STDERR "%s Route of Route-Master not found although 'ref' is valid and 'operator' are equal. Route-Master: %s, Route: %s, 'ref': %s, 'operator': %s\n", get_time(), $relation_id, $member_ref->{'ref'}, $members_ref, text_msg($relation_ptr->{'tag'}->{'operator'});
                                                            # 'ref' tag is valid (in the list) 'operator' is OK, any other reason
                                                            push( @{$relation_ptr->{'__issues__'}}, issue('route.other_section_ref', $members_ref, printRelationTemplate($member_ref->{'ref'})) );
                                                        } else {
                                                            # 'ref' tag is valid (in the list) but 'operator' is set and differs
                                                            push( @{$relation_ptr->{'__issues__'}}, issue('route.operator_differs_master', foreign($RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'operator'}), foreign($relation_ptr->{'tag'}->{'operator'}), printRelationTemplate($member_ref->{'ref'})) );
                                                        }
                                                    } elsif ( $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'operator'} ) {
                                                        # 'ref' tag is valid (in the list) but 'operator' is strange
                                                        push( @{$relation_ptr->{'__issues__'}}, issue('operator.irrelevant_value', foreign($RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'operator'}), printRelationTemplate($member_ref->{'ref'})) );
                                                    }
                                                } else {
                                                    # 'ref' tag is valid (in the list) but 'network' is set and differs
                                                    push( @{$relation_ptr->{'__issues__'}}, issue('route.network_differs_master', foreign($RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'network'}), foreign($relation_ptr->{'tag'}->{'network'}), printRelationTemplate($member_ref->{'ref'})) );
                                                }
                                            } elsif ( $RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'network'} ) {
                                                # 'ref' tag is valid (in the list) but 'network' is strange
                                                push( @{$relation_ptr->{'__notes__'}}, note('network.irrelevant_value', foreign($RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'network'}), printRelationTemplate($member_ref->{'ref'})) );
                                            }
                                            if ( $members_ref ne $masters_ref ) {
                                                # 'members_ref' is valid (in the list) but differs from 'ref' of route-master, so we have at least two refs in the list (a real list)
                                                #$notes_string = gettext( "Route has different 'ref' = '%s' than Route-Master 'ref' = '%s' - this should be avoided: %s" );
                                                #push( @{$relation_ptr->{'__notes__'}}, msg( $notes_string, $members_ref, $masters_ref, printRelationTemplate($member_ref->{'ref'}) ) );
                                                ;
                                            }
                                        } else {
                                            # 'ref' tag is set but is not valid, not in list
                                            push( @{$relation_ptr->{'__issues__'}}, issue('route.ref_mismatch', foreign($members_ref), printRelationTemplate($member_ref->{'ref'})) );
                                        }
                                    } else {
                                        # 'ref' tag is not set
                                        push( @{$relation_ptr->{'__issues__'}}, issue('route.no_ref_in_data', printRelationTemplate($member_ref->{'ref'})) );
                                    }
                                } else {
                                    # 'ref' tag is valid (in the list) but 'route' is set and differs from 'route_master'
                                    push( @{$relation_ptr->{'__issues__'}}, issue('route.type_differs_master', foreign($RELATIONS{$member_ref->{'ref'}}->{'route_type_value'}), foreign($relation_ptr->{'route_master_type_value'}), printRelationTemplate($member_ref->{'ref'})) );
                                }
                            } else {
                                if ( $RELATIONS{$member_ref->{'ref'}}->{'route_type_value'} ) {
                                    # 'route' is strange
                                    push( @{$relation_ptr->{'__issues__'}}, issue('route.value_irrelevant', foreign($RELATIONS{$member_ref->{'ref'}}->{'route_type_value'}), printRelationTemplate($member_ref->{'ref'})) );
                                } else {
                                    # 'route' is not set
                                    push( @{$relation_ptr->{'__issues__'}}, issue('route.tag_not_set', printRelationTemplate($member_ref->{'ref'})) );
                                }
                            }
                        } else {
                            # 'type' is strange
                            push( @{$relation_ptr->{'__issues__'}}, issue('rel.type_not_route', foreign($RELATIONS{$member_ref->{'ref'}}->{'tag'}->{'type'}), printRelationTemplate($member_ref->{'ref'})) );
                        }
                    } else {
                        # 'type' is not set
                        push( @{$relation_ptr->{'__issues__'}}, issue('rel.type_not_set', printRelationTemplate($member_ref->{'ref'})) );
                    }
                } else {
                    #
                    # relation is not included in XML input file
                    #
                    push( @{$relation_ptr->{'__issues__'}}, issue('route.not_in_data', printRelationTemplate($member_ref->{'ref'})) );
                    printf STDERR "%s Error in input data (%s): insufficient data for relations of route_master 'ref' = '%s' : r%s\n", get_time(), $section, ($relation_ptr->{'tag'}->{'ref'} ? $relation_ptr->{'tag'}->{'ref'} : 'no ref', $member_ref->{'ref'});
                }
            }
        }
        # check whether all found relations are member of this/these route master(s), tell us which one is not
        foreach my $rel_id ( sort( keys( %{$env_ref->{'route'}->{$route_type}} ) ) ) {
            if ( !defined($my_routes{$rel_id}) ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('route.not_in_master', printRelationTemplate($rel_id)) );
            }
        }
    }

    return $return_code;
}


#############################################################################################

sub analyze_route_environment {
    my $env_ref         = shift;
    my $ref_or_list     = shift;
    my $type            = shift;
    my $route_type      = shift;
    my $relation_id     = shift;
    my $return_code     = 0;

    my $relation_ptr                            = undef;
    my $number_of_direct_route_masters          = 0;
    my $number_of_route_masters                 = 0;
    my $number_of_routes                        = 0;
    my %direct_and_matching_route_masters       = ();
    my %allowed_refs                            = ();
    my $masters_ref                             = undef;
    my $routes_ref                              = undef;
    my $route_master_network                    = undef;

    if ( $env_ref && $ref_or_list && $type && $type eq 'route' && $route_type && $relation_id ) {

        $relation_ptr = $env_ref->{'route'}->{$route_type}->{$relation_id};

        #
        # 1. find all direct and matching route_masters here (also those where only 'ref' and 'route_type' match)
        #
        foreach my $direct_route_master_rel_id ( keys( %{$RELATIONS{$relation_id}->{'member_of_route_master'}}  ) ) {
            $direct_and_matching_route_masters{$direct_route_master_rel_id} = 1;
            $number_of_direct_route_masters++;
        }
        foreach my $indirect_route_master_rel_id ( keys( %{$env_ref->{'route_master'}->{$route_type}} ) ) {
            $direct_and_matching_route_masters{$indirect_route_master_rel_id} = 1;
        }
        $number_of_route_masters = scalar( keys ( %direct_and_matching_route_masters ) );

        if ( $number_of_route_masters > 1 && $number_of_direct_route_masters < $number_of_route_masters ) {
            # number_of_direct_route_masters < y : because number_of_direct_route_masters == number_of_route_masters will be checked some lines below if number_of_direct_route_masters > 1
            push( @{$relation_ptr->{'__issues__'}}, issue('master.multiple') );
        }
        if ( $number_of_direct_route_masters > $number_of_route_masters ) {
            foreach my $direct_route_master_rel_id ( keys( %{$RELATIONS{$relation_id}->{'member_of_route_master'}}  ) ) {
                if ( !defined($env_ref->{'route_master'}->{$route_type}->{$direct_route_master_rel_id}) ) {
                    if ( $RELATIONS{$direct_route_master_rel_id} && $RELATIONS{$direct_route_master_rel_id}->{'tag'} && exists($RELATIONS{$direct_route_master_rel_id}->{'tag'}->{'ref'}) ) {
                        $masters_ref = $RELATIONS{$direct_route_master_rel_id}->{'tag'}->{'ref'};
                        push( @{$relation_ptr->{'__issues__'}}, issue('master.other_section_ref', $masters_ref, printRelationTemplate($direct_route_master_rel_id)) );
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, issue('master.other_section_unknown_ref', $masters_ref, printRelationTemplate($direct_route_master_rel_id)) );
                    }
                }
            }
        }

        #
        # 2. check direct environment of this route: route_master(s) where this route is member of (independent of PTv2 or not)
        #

        $number_of_routes = scalar( keys( %{$env_ref->{'route'}->{$route_type}} ) );

        if ( $number_of_direct_route_masters > 1 ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('route.in_multiple_masters', list_msg('comma', map { printRelationTemplate($_); } sort( keys( %{$RELATIONS{$relation_id}->{'member_of_route_master'}} ) ) )) );
        } else {
            if ( $number_of_routes > 1 ) {
                if ( $number_of_route_masters == 0 ) {
                    push( @{$relation_ptr->{'__issues__'}}, issue('route.multiple_no_master') );
                } elsif ( $number_of_direct_route_masters == 0 ) {
                    push( @{$relation_ptr->{'__issues__'}}, issue('route.multiple_not_in_master') );
                }
            } else {
                # only one route but ... check if there is a route_master
                if ( $number_of_route_masters > 0 && $number_of_direct_route_masters == 0 ) {
                    # there is at least one route_master, but this route is not a member of any
                    push( @{$relation_ptr->{'__issues__'}}, issue('route.no_master') );
                }
            }
        }

        #
        # 3. check major tags of this route and the route_masters: they should match
        #

        foreach my $route_master_rel_id ( sort( keys( %direct_and_matching_route_masters ) ) ) {
            if ( $relation_ptr->{'route_type_value'}   && $RELATIONS{$route_master_rel_id}->{'route_master_type_value'} &&
                 $relation_ptr->{'route_type_value'}   ne $RELATIONS{$route_master_rel_id}->{'route_master_type_value'}     ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('route.type_not_fit_master', $relation_ptr->{'route_type_value'}, $RELATIONS{$route_master_rel_id}->{'route_master_type_value'}, printRelationTemplate($route_master_rel_id)) );
            }
            if ( exists($RELATIONS{$route_master_rel_id}->{'tag'}->{'ref'}) && defined($RELATIONS{$route_master_rel_id}->{'tag'}->{'ref'}) && $RELATIONS{$route_master_rel_id}->{'tag'}->{'ref'} ne '' ) {
                foreach $masters_ref ( @{$ref_or_list} ) {
                    $allowed_refs{$masters_ref} = 1;
                }
                $masters_ref = $RELATIONS{$route_master_rel_id}->{'tag'}->{'ref'};
                if ( $allowed_refs{$masters_ref} ) {
                    $routes_ref = $relation_ptr->{'tag'}->{'ref'};
                    #
                    # 'masters_ref' is in the list, check for other problems
                    #
                    if ( defined($routes_ref) && $routes_ref ne '' && $routes_ref ne $masters_ref ) {
                        # 'masters_ref' is valid (in the list) but differs from 'ref' of route, so we have at least two refs in the list (a real list)
                        #$notes_string = gettext( "Route has different 'ref' = '%s' than Route-Master 'ref' = '%s' - this should be avoided: %s" );
                        #push( @{$relation_ptr->{'__notes__'}}, msg( $notes_string, $routes_ref, $masters_ref, printRelationTemplate($route_master_rel_id) ) );
                        ;
                    }
                } else {
                    push( @{$relation_ptr->{'__issues__'}}, issue('master.ref_mismatch', $masters_ref, printRelationTemplate($route_master_rel_id)) );
                }
            } else {
                    push( @{$relation_ptr->{'__issues__'}}, issue('master.no_ref_in_data', printRelationTemplate($route_master_rel_id)) );
            }
            if ( $relation_ptr->{'tag'}->{'network'} && $RELATIONS{$route_master_rel_id}->{'tag'}->{'network'} &&
                 $relation_ptr->{'tag'}->{'network'} ne $RELATIONS{$route_master_rel_id}->{'tag'}->{'network'}     ) {

                $route_master_network = ';' . $RELATIONS{$route_master_rel_id}->{'tag'}->{'network'} . ';';

                if ( $route_master_network =~ m/;\Q$relation_ptr->{'tag'}->{'network'}\E;/  ) {
                    push( @{$relation_ptr->{'__notes__'}}, note('network.part_of_master', foreign($relation_ptr->{'tag'}->{'network'}), foreign($RELATIONS{$route_master_rel_id}->{'tag'}->{'network'}), printRelationTemplate($route_master_rel_id)) );
                } else {
                    push( @{$relation_ptr->{'__issues__'}}, issue('network.differs_from_master', foreign($relation_ptr->{'tag'}->{'network'}), foreign($RELATIONS{$route_master_rel_id}->{'tag'}->{'network'}), printRelationTemplate($route_master_rel_id)) );
                }
            }
            if ( $relation_ptr->{'tag'}->{'operator'} && $RELATIONS{$route_master_rel_id}->{'tag'}->{'operator'} &&
                 $relation_ptr->{'tag'}->{'operator'} ne $RELATIONS{$route_master_rel_id}->{'tag'}->{'operator'}     ) {
                my $help_route_master_opeartor = ';' . $RELATIONS{$route_master_rel_id}->{'tag'}->{'operator'} . ';';
                my $help_route_operator        = ';' . $relation_ptr->{'tag'}->{'operator'} . ';';
                unless ( $help_route_master_opeartor =~ m/\Q$help_route_operator\E/ ) {
                    push( @{$relation_ptr->{'__issues__'}}, issue('operator.differs_from_master', foreign($relation_ptr->{'tag'}->{'operator'}), foreign($RELATIONS{$route_master_rel_id}->{'tag'}->{'operator'}), printRelationTemplate($route_master_rel_id)) );
                }
            }
            foreach my $colour_tag ( 'colour', 'colour:text' ) {
                if ( $relation_ptr->{'tag'}->{$colour_tag} ) {
                    if ( $RELATIONS{$route_master_rel_id}->{'tag'}->{$colour_tag} ) {
                        if ( uc($relation_ptr->{'tag'}->{$colour_tag}) ne uc($RELATIONS{$route_master_rel_id}->{'tag'}->{$colour_tag}) ) {
                            push( @{$relation_ptr->{'__issues__'}}, issue('tag.differs_from_master', $colour_tag, $relation_ptr->{'tag'}->{$colour_tag}, $colour_tag, $RELATIONS{$route_master_rel_id}->{'tag'}->{$colour_tag}, printRelationTemplate($route_master_rel_id)) );
                        }
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, issue('tag.set_but_not_on_master', , $colour_tag, foreign($relation_ptr->{'tag'}->{$colour_tag}), $colour_tag, printRelationTemplate($route_master_rel_id)) );
                    }
                } else {
                    unless ( $inherit_tags ) {
                        if ( $RELATIONS{$route_master_rel_id}->{'tag'}->{$colour_tag} ) {
                            push( @{$relation_ptr->{'__issues__'}}, issue('tag.not_set_but_on_master', $colour_tag, $colour_tag, $RELATIONS{$route_master_rel_id}->{'tag'}->{$colour_tag}, printRelationTemplate($route_master_rel_id)) );
                        }
                    }
                }
            }

            #
            # --check-gtfs  check gtfs:feed, gtfs:release_date and gtfs:route_id of this route against those of route_master - must match: each of the route's values must be part of route_master's value
            #
            if ( $check_gtfs ) {
                my $help_rtag = '';
                my $help_mtag = '';
                my $mcount    = 0;
                my $tcount    = 0;
                my %gtfs_keys = ();
                foreach my $key ( keys(%{$relation_ptr->{'gtfs_keys'}}), keys(%{$RELATIONS{$route_master_rel_id}->{'gtfs_keys'}}) ) {
                    if ( $key =~ m/^gtfs:/ ) {
                        if ( $key eq 'gtfs:feed'                                                 ||
                             $key =~ m/^gtfs:(release_date|route_id)$/                           ||
                             $key =~ m/^gtfs:(release_date|route_id):[A-Z][A-Z][a-zA-Z0-9_.-]+$/    ) {
                            $gtfs_keys{$key} = 1;
                        }
                    }
                }
                foreach my $gtfs_tag ( sort( keys(%gtfs_keys) ) ) {
                    if ( $relation_ptr->{'tag'}->{$gtfs_tag} ) {
                        if ( $RELATIONS{$route_master_rel_id}->{'tag'}->{$gtfs_tag} ) {
                            $help_rtag = $relation_ptr->{'tag'}->{$gtfs_tag};
                            $help_rtag =~ s/\s*;\s*/;/g;
                            $help_mtag = ';' . $RELATIONS{$route_master_rel_id}->{'tag'}->{$gtfs_tag} . ';';
                            $help_mtag =~ s/\s*;\s*/;/g;
                            $tcount = 0;
                            $mcount = 0;
                            foreach my $rval ( split( /;/, $help_rtag ) ){
                                $tcount++;
                                $mcount++  if ( $help_mtag =~ m/;\Q$rval\E;/ );
                            }
                            if ( $mcount != $tcount ) {
                                push( @{$relation_ptr->{'__issues__'}}, issue('tag.differs_from_master', $gtfs_tag, $relation_ptr->{'tag'}->{$gtfs_tag}, $gtfs_tag, $RELATIONS{$route_master_rel_id}->{'tag'}->{$gtfs_tag}, printRelationTemplate($route_master_rel_id)) );
                            }
                        } else {
                            # route_masters do not inherit keys from routes
                            push( @{$relation_ptr->{'__issues__'}}, issue('tag.set_but_not_on_master', $gtfs_tag, $relation_ptr->{'tag'}->{$gtfs_tag}, $gtfs_tag, printRelationTemplate($route_master_rel_id)) );
                        }
                    } else {
                        unless ( $inherit_tags ) {
                            if ( $RELATIONS{$route_master_rel_id}->{'tag'}->{$gtfs_tag} ) {
                                # route deoes not inherit 'gtfs:*' from route_master
                                push( @{$relation_ptr->{'__issues__'}}, issue('tag.not_set_but_on_master', $gtfs_tag, $gtfs_tag, $RELATIONS{$route_master_rel_id}->{'tag'}->{$gtfs_tag}, printRelationTemplate($route_master_rel_id)) );
                            }
                        }
                    }
                }
            }
        }

        if ( $number_of_routes > 1 ) {

            # 4. check 'name' tag of this route against the 'name' tag of the other routes, there should be no match, 'name' should be unique

            if ( $check_name                                                &&
                 $relation_ptr->{'tag'}->{'name'}                           &&
                 $relation_ptr->{'tag'}->{'public_transport:version'}       &&
                 $relation_ptr->{'tag'}->{'public_transport:version'} eq '2'   ) {

                my %name_matches = ();

                foreach my $peer_route_relation_id ( keys ( %{$env_ref->{'route'}->{$route_type}} ) ) {

                    next    if ( $relation_id eq $peer_route_relation_id );

                    if ( $RELATIONS{$peer_route_relation_id}->{'tag'}->{'name'}                             &&
                         $RELATIONS{$peer_route_relation_id}->{'tag'}->{'public_transport:version'}         &&
                         $RELATIONS{$peer_route_relation_id}->{'tag'}->{'public_transport:version'} eq '2'  &&
                         $relation_ptr->{'tag'}->{'name'} eq $RELATIONS{$peer_route_relation_id}->{'tag'}->{'name'}     ) {
                        $name_matches{$peer_route_relation_id} = 1;
                    }
                }

                if ( scalar( keys ( %name_matches ) ) ) {
                    my @help_array    = sort( keys ( %name_matches ) );
                    my $num_of_errors = scalar(@help_array);
                    if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                        push( @{$relation_ptr->{'__notes__'}}, listed(note('ptv2.name_identical_other'), [map { printRelationTemplate($_); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                    } else {
                        push( @{$relation_ptr->{'__notes__'}}, listed(note('ptv2.name_identical_other'), [map { printRelationTemplate($_); } @help_array]) );
                    }
                }
            }


            # 5. check for 'public_transport:version' being set to '2' if there is more than one route

            if ( !$relation_ptr->{'tag'}->{'public_transport:version'} || $relation_ptr->{'tag'}->{'public_transport:version'} ne '2' ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('route.multiple_no_ptv2') . printRelationInjectData($relation_ptr->{'id'},('public_transport:version=2')) );
            }

            #
            # 6.  --check-gtfs  check that gtfs:trip_id, gtfs:trip_id:sample and gtfs:trip_id:like are unique
            #

            if ( $check_gtfs ) {
                my %gtfs_ident = ();
                my %gtfs_match = ();
                my $help_val   = '';
                my $help_pval  = '';
                my %gtfs_keys  = ();
                foreach my $key ( keys(%{$relation_ptr->{'gtfs_keys'}}) ) {
                    if ( $key =~ m/^gtfs:trip_id/    ) {
                        if ( $key =~ m/^gtfs:trip_id$/                                          ||
                             $key =~ m/^gtfs:trip_id:(sample|like)$/                            ||
                             $key =~ m/^gtfs:trip_id:[A-Z][A-Z][a-zA-Z0-9_.-]+$/                ||
                             $key =~ m/^gtfs:trip_id:(sample|like):[A-Z][A-Z][a-zA-Z0-9_.-]+$/     ) {
                            $gtfs_keys{$key} = 1;
                        }
                    }
                }
                foreach my $gtfs_tag ( sort( keys(%gtfs_keys) ) ) {
                    %gtfs_ident = ();
                    %gtfs_match = ();

                    foreach my $peer_route_relation_id ( keys ( %{$env_ref->{'route'}->{$route_type}} ) ) {

                        next    if ( $relation_id eq $peer_route_relation_id );

                        if ( $relation_ptr->{'tag'}->{$gtfs_tag} && $RELATIONS{$peer_route_relation_id}->{'tag'}->{$gtfs_tag} ) {
                            if ( $relation_ptr->{'tag'}->{$gtfs_tag} eq $RELATIONS{$peer_route_relation_id}->{'tag'}->{$gtfs_tag} ) {
                                $gtfs_ident{$peer_route_relation_id} = 1;
                            } else {
                                $help_val  = $relation_ptr->{'tag'}->{$gtfs_tag};
                                $help_pval = ';' . $RELATIONS{$peer_route_relation_id}->{'tag'}->{$gtfs_tag} . ';';
                                $help_val  =~ s/\s*;\s*/;/g;
                                $help_pval =~ s/\s*;\s*/;/g;
                                foreach my $val ( split( /;/,$help_val) ) {
                                    if ( $help_pval =~ m/;\Q$val\E;/ ) {
                                        push( @{$gtfs_match{$RELATIONS{$peer_route_relation_id}->{'tag'}->{$gtfs_tag}}}, $peer_route_relation_id );
                                    }
                                }
                            }
                        }
                    }

                    if ( scalar( keys ( %gtfs_ident ) ) ) {
                        my @help_array    = sort( keys ( %gtfs_ident ) );
                        my $num_of_errors = scalar(@help_array);
                        my $help_string = issue('tag.identical_to_other_route', $gtfs_tag, $relation_ptr->{'tag'}->{$gtfs_tag}, $gtfs_tag);
                        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                            push( @{$relation_ptr->{'__issues__'}}, listed($help_string, [map { printRelationTemplate($_); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                        } else {
                            push( @{$relation_ptr->{'__issues__'}}, listed($help_string, [map { printRelationTemplate($_); } @help_array]) );
                        }
                    }

                    if ( scalar( keys ( %gtfs_match ) ) ) {
                        foreach my $val ( sort( keys ( %gtfs_match ) ) ) {
                            my @help_array    = sort( @{$gtfs_match{$val}} );
                            my $num_of_errors = scalar(@help_array);
                            my $help_string = issue('tag.matches_other_route', $gtfs_tag, $relation_ptr->{'tag'}->{$gtfs_tag}, $gtfs_tag, $val);
                            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                                push( @{$relation_ptr->{'__issues__'}}, listed($help_string, [map { printRelationTemplate($_); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                            } else {
                                push( @{$relation_ptr->{'__issues__'}}, listed($help_string, [map { printRelationTemplate($_); } @help_array]) );
                            }
                        }
                    }
                }
            }
        }
    }

    return $return_code;
}


#############################################################################################

sub analyze_relation {
    my $relation_ptr    = shift;
    my $relation_id     = shift;
    my $entryref        = shift || undef;
    my $return_code     = 0;

    my $ref                             = '';
    my $type                            = '';
    my $route_type                      = '';
    my $network                         = '';
    my $operator                        = '';
    my $member_index                    = 0;
    my $relation_index                  = 0;
    my $route_master_relation_index     = 0;    # counts number of relation members in a 'route_master' which are not 'platforms' (should be equal to $relation_index')
    my $route_relation_index            = 0;    # counts number of relation members in a 'route' which are not 'platforms'
    my $way_index                       = 0;    # counts number of all way members
    my $route_highway_index             = 0;    # counts number of ways members in a route which are not 'platforms'
    my $node_index                      = 0;
    my @specialtags                     = ( 'comment', 'note', 'fixme', 'check_date' );
    my $specialtag                      = undef;
    my %specialtag2reporttype           = ( 'comment'       => '__notes__',
                                            'note'          => '__issues__',
                                            'fixme'         => '__issues__',
                                            'check_date'    => '__notes__'
                                          );
    my @check_osm_separator_tags        = ( 'network', 'ref', 'gtfs' );
    my $check_osm_separator_tag         = undef;
    my $reporttype                      = undef;
    my @datetags                        = ( 'check_date', 'gtfs:release_date' );
    my $datetag                         = undef;
    my $datevalue                       = undef;

    if ( $relation_ptr ) {

        $ref                            = $relation_ptr->{'tag'}->{'ref'};
        $type                           = $relation_ptr->{'tag'}->{'type'};
        $route_type                     = $relation_ptr->{'tag'}->{$type};

        # we need these several times

        my @relation_tags = sort( keys( %{$relation_ptr->{'tag'}} ) );

        #
        # now, check existing and defined tags and report them to front of list (ISSUES, NOTES)
        #

        foreach $specialtag ( @specialtags ) {
            foreach my $tag ( @relation_tags ) {
                if ( $tag =~ m/^\Q$specialtag\E/i ) {
                    if ( defined($relation_ptr->{'tag'}->{$tag}) ) {
                        $reporttype = ( $specialtag2reporttype{$specialtag} ) ? $specialtag2reporttype{$specialtag} : '__notes__';
                        if ( $tag =~ m/^note$/i && $relation_ptr->{'tag'}->{$tag} =~ m|^https{0,1}://wiki.openstreetmap.org\S+\s*[;,_+#\.\-]*\s*(.*)| ) {
                            unshift( @{$relation_ptr->{$reporttype}}, msg("'%s' ~ '%s'", foreign($tag), foreign($1)) )  if ( $1 );
                        } elsif ( $tag =~ m/^note$/i && $relation_ptr->{'tag'}->{$tag} =~ m|^https{0,1}://ptna.openstreetmap.de\S+\s*[;,_+#\.\-]*\s*(.*)| ) {
                            unshift( @{$relation_ptr->{$reporttype}}, msg("'%s' ~ '%s'", foreign($tag), foreign($1)) )  if ( $1 );
                        } else {
                            unshift( @{$relation_ptr->{$reporttype}}, note('note.tag_value', foreign($tag), foreign($relation_ptr->{'tag'}->{$tag})) )
                        }
                    }
                }
            }
        }

        #
        # now check existance of required/optional tags
        #

        unless ( exists($relation_ptr->{'tag'}->{'ref'}) ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('ref.not_set') );
        }
        if ( $check_name ) {
            unless ( exists($relation_ptr->{'tag'}->{'name'}) ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('name.not_set') );
                foreach my $tag ( @relation_tags ) {
                    if ( $tag =~ m/^name:/ || $tag =~ m/_name$/ ) {
                        push( @{$relation_ptr->{'__notes__'}}, note('note.tag_value', foreign($tag), foreign($relation_ptr->{'tag'}->{$tag})) );
                    }
                }
            }
        }

        $network = $relation_ptr->{'tag'}->{'network'};

        if ( $network ) {
            my $match           = '';
            my $we_have_a_match = 0;

            my $network_with = ';' . $network . ';';        # we match only with sourrounding ';', i.e. 'DB InterCity' does not match network='DB InterCityExpress'

            if ( $network_short_regex ) {
                foreach my $short_value ( split('\|',$network_short_regex) ) {
                    if ( $network_with =~ m/[;,]\s*(\Q$short_value\E)\s*[;,]\s*/ ) {
                        $match = $1;
                        if ( $positive_notes ) {
                            if ( $network eq $match ) {
                                push( @{$relation_ptr->{'__notes__'}}, note('note.network_equal', foreign($match)) );
                            } else {
                                push( @{$relation_ptr->{'__notes__'}}, note('note.network_similar', foreign($match)) );
                            }
                        }
                        $we_have_a_match++;
                    }
                }
            }
            if ( $network_long_regex ) {
                foreach my $long_value ( split('\|',$network_long_regex) ) {
                    if ( $network_with =~ m/[;,]\s*(\Q$long_value\E)\s*[;,]\s*/ ) {
                        $match = $1;
                        if ( $positive_notes ) {
                            if ( $network eq $match ) {
                                push( @{$relation_ptr->{'__notes__'}}, note('note.network_equal', foreign($match)) );
                            } else {
                                push( @{$relation_ptr->{'__notes__'}}, note('note.network_similar', foreign($match)) );
                            }
                        }
                        $we_have_a_match++;
                    }
                }
            }
            if ( $we_have_a_match == 0 && ($network_long_regex || $network_short_regex) ) {
                push( @{$relation_ptr->{'__notes__'}}, note('network.irrelevant_value', foreign($network), printRelationTemplate($relation_id)) );
                if ( $positive_notes ) {
                    push( @{$relation_ptr->{'__notes__'}}, note('note.network_equal', foreign($network)) );
                }
            }

            if ( $expect_network_short  ) {
                my $match_short     = '';
                my $match_long      = '';
                my $expect_long_as  = '';
                my $expect_long_for = '';

                $match_short     = $1   if ( $network_short_regex     && $network =~ m/($network_short_regex)/     );
                $match_long      = $1   if ( $network_long_regex      && $network =~ m/($network_long_regex)/      );
                $expect_long_as  = $1   if ( $expect_network_long_as  && $network =~ m/(\Q$expect_network_long_as\E)/  );
                $expect_long_for = $1   if ( $expect_network_long_for && $network =~ m/(\Q$expect_network_long_for\E)/ );

                if ( $match_long ) {
                    if ( $match_long ne $expect_long_as ) {
                        push( @{$relation_ptr->{'__notes__'}}, note('network.should_be_short', foreign($match_long)) );
                    }
                } elsif ( $match_short ) {
                    if ( $match_short eq $expect_long_for ) {
                        push( @{$relation_ptr->{'__notes__'}}, note('network.should_be_long', foreign($match_short)) );
                    }
                }
            } elsif ( $expect_network_long  ) {
                my $match_long       = '';
                my $match_short      = '';
                my $expect_short_as  = '';
                my $expect_short_for = '';

                $match_long       = $1   if ( $network_long_regex       && $network =~ m/($network_long_regex)/       );
                $match_short      = $1   if ( $network_short_regex      && $network =~ m/($network_short_regex)/      );
                $expect_short_as  = $1   if ( $expect_network_short_as  && $network =~ m/(\Q$expect_network_short_as\E)/  );
                $expect_short_for = $1   if ( $expect_network_short_for && $network =~ m/(\Q$expect_network_short_for\E)/ );

                if ( $match_short ) {
                    if ( $match_short ne $expect_short_as ) {
                        push( @{$relation_ptr->{'__notes__'}}, note('network.should_be_long', foreign($match_short)) );
                    }
                } elsif ( $match_long ) {
                    if ( $match_long eq $expect_short_for ) {
                        push( @{$relation_ptr->{'__notes__'}}, note('network.should_be_short', foreign($match_long)) );
                    }
                }
            }
        } else {
            push( @{$relation_ptr->{'__issues__'}}, issue('network.not_set') );
        }

        foreach my $colour_tag ( 'colour', 'colour:text' ) {
            if ( $relation_ptr->{'tag'}->{$colour_tag} ) {
                my $colour = GetColourFromString( $relation_ptr->{'tag'}->{$colour_tag} );
                unless ( $colour ) {
                    if ( $relation_ptr->{'tag'}->{$colour_tag} =~ m/^[0-9A-Fa-f]{3,6}$/ ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('colour.missing_hash', $colour_tag, text_msg($relation_ptr->{'tag'}->{$colour_tag})) );
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, issue('colour.unknown_value', $colour_tag, foreign($relation_ptr->{'tag'}->{$colour_tag})) );
                    }
                }
            }
        }

        if ( $positive_notes ) {

            if ( !$network_long_regex && !$network_short_regex ) {
                # we do not filter for any 'network' values, so let's print also the value of 'network'
                if ( $relation_ptr->{'tag'}->{'network'} ) {
                    push( @{$relation_ptr->{'__notes__'}}, note('note.network_equal', foreign($relation_ptr->{'tag'}->{'network'})) )
                }
            }

            foreach my $special ( 'network:', 'route:', 'ref:', 'ref_', 'operator', 'timetable' ) {
                foreach my $tag ( @relation_tags ) {
                    if ( $tag =~ m/^\Q$special\E/i ) {
                        if ( defined($relation_ptr->{'tag'}->{$tag}) ) {
                            if ( $tag =~ m/^network:long$/i && $network_long_regex ){
                                if ( $relation_ptr->{'tag'}->{$tag} =~ m/^$network_long_regex$/ ) {
                                    push( @{$relation_ptr->{'__notes__'}}, note('network.long_form_set') );
                                } elsif ( $relation_ptr->{'tag'}->{$tag} =~ m/$network_long_regex/ ) {
                                    push( @{$relation_ptr->{'__notes__'}}, note('network.matches_long_form') );
                                } else {
                                    push( @{$relation_ptr->{'__notes__'}}, note('note.network_long_equal', foreign($relation_ptr->{'tag'}->{$tag})) )
                                }
                            } else {
                                push( @{$relation_ptr->{'__notes__'}}, note('note.tag_value', foreign($tag), foreign($relation_ptr->{'tag'}->{$tag})) )
                            }
                        }
                    }
                }
            }
        }

        if ( $check_osm_separator ) {
            foreach $check_osm_separator_tag ( @check_osm_separator_tags ) {
                foreach my $tag ( @relation_tags ) {
                    if ( $tag ne 'ref_trips' && $tag ne 'ref_name' && $tag !~ m/:wiki/ && $tag =~ m/^\Q$check_osm_separator_tag\E/ ) {
                        if ( defined($relation_ptr->{'tag'}->{$tag}) ) {
#                            if ( $relation_ptr->{'tag'}->{$tag} =~ m/\s;|;\s/ ) {
#                                $notes_string = gettext( "'%s' = '%s' includes the separator value ';' (semi-colon) with sourrounding blank" );
#                                push( @{$relation_ptr->{'__notes__'}}, msg( $notes_string, foreign($tag), foreign($relation_ptr->{'tag'}->{$tag})) );
#                            }
                            if ( $relation_ptr->{'tag'}->{$tag} =~ m/,/ ) {
                                push( @{$relation_ptr->{'__notes__'}}, note('tag.comma_separator', foreign($tag), foreign($relation_ptr->{'tag'}->{$tag})) );
                            }
                        }
                    }
                }
            }
        }

        if ( $show_gtfs ) {
            foreach my $special ( 'gtfs:', 'gtfs_' ) {
                foreach my $tag ( @relation_tags ) {
                    if ( $tag =~ m/^\Q$special\E/i ) {
                        if ( defined($relation_ptr->{'tag'}->{$tag}) ) {
                            push( @{$relation_ptr->{'__notes__'}}, note('note.tag_value', foreign($tag), foreign($relation_ptr->{'tag'}->{$tag})) )
                        }
                    }
                }
            }
        }

        if ( $check_gtfs ) {
            if ( $entryref ) {
                ;
            }
            my $num_short_gtfs_keys = 0;
            my $num_long_gtfs_keys  = 0;
            my $example_long_gtfs_key = '';
            my $example_short_gtfs_key = '';
            printf STDERR "relation_ptr->{'gtfs_keys'} = %s\n", Data::Dumper::Dumper($relation_ptr->{'gtfs_keys'})  if ( $debug );
            foreach my $gtfs_key ( sort( keys(%{$relation_ptr->{'gtfs_keys'}}) ) ) {
                if ( $gtfs_key =~ m/^gtfs:/ ) {
                    if ( $gtfs_key =~ m/^gtfs:([a-z][a-z_]+[a-z])$/                                 ||
                         $gtfs_key =~ m/^gtfs:(trip_id):(like|sample)$/                             ||
                         $gtfs_key =~ m/^gtfs:([a-z][a-z_]+[a-z])(:)([A-Z][A-Z][a-zA-Z0-9_.-]+)$/   ||
                         $gtfs_key =~ m/^gtfs:(trip_id):(like|sample):([A-Z][A-Z][a-zA-Z0-9_.-]+)$/    ) {
                        my $first = $1;
                        my $third = $3;
                        if ( exists($deprecated_gtfs_terms{$first}) ) {
                            push( @{$relation_ptr->{'__issues__'}}, issue('gtfs.invalid_key', foreign($gtfs_key), '<a target="_blank" href="https://wiki.openstreetmap.org/wiki/GTFS#General_rules" title="OSM Wiki - GTFS tags">OSM Wiki</a>') );
                        } else {
                            if ( $third ) {
                                if ( $first eq 'feed' ) {
                                    push( @{$relation_ptr->{'__issues__'}}, issue('gtfs.key_has_feed_suffix', foreign($gtfs_key), '<a target="_blank" href="https://wiki.openstreetmap.org/wiki/GTFS#Tags" title="OSM Wiki - GTFS tags">OSM Wiki</a>') );
                                } else {
                                    if ( $third =~ m/^[A-Z][A-Z]-[a-zA-Z0-9_.-]+$/ ||
                                        ($opt_test && $third eq 'GTFS-Test')          ) {
                                        $num_long_gtfs_keys++;
                                        $example_long_gtfs_key = $gtfs_key;
                                    } else {
                                        push( @{$relation_ptr->{'__issues__'}}, issue('gtfs.invalid_feed_code', foreign($third), foreign($gtfs_key), '<a target="_blank" href="https://wiki.openstreetmap.org/wiki/GTFS#Step_2:_Document_the_feed" title="OSM Wiki - GTFS tags">OSM Wiki</a>') );
                                    }
                                }
                                $num_long_gtfs_keys++;
                                $example_long_gtfs_key = $gtfs_key;
                            } else {
                                $num_short_gtfs_keys++;
                                $example_short_gtfs_key = $gtfs_key;
                            }
                        }
                        if ( $opt_test && $first eq 'shape_id' ) {
                            my $key0 = 'gtfs:shape_id';
                            my $key1 = 'gtfs:trip_id';
                            my $key2 = 'gtfs:trip_id:sample';
                            if ( $third ) {
                                $key0 .= ':'.$third;
                                $key1 .= ':'.$third;
                                $key2 .= ':'.$third;
                            }
                            if ( !defined($relation_ptr->{'tag'}->{$key1}) &&
                                 !defined($relation_ptr->{'tag'}->{$key2})    ) {
                                push( @{$relation_ptr->{'__notes__'}}, note('tag.missing_alternatives', $key0, foreign($relation_ptr->{'tag'}->{'gtfs:shape_id'}), $key1, $key2) );
                            }
                        }
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, issue('gtfs.invalid_key', foreign($gtfs_key), '<a target="_blank" href="https://wiki.openstreetmap.org/wiki/GTFS#Tags" title="OSM Wiki - GTFS tags">OSM Wiki</a>') );
                    }
                } else {
                    push( @{$relation_ptr->{'__issues__'}}, issue('gtfs.deprecated_key', foreign($gtfs_key), '<a target="_blank" href="https://wiki.openstreetmap.org/wiki/GTFS#Tags" title="OSM Wiki - GTFS tags">OSM Wiki</a>') );
                }
            }
            if ( $num_short_gtfs_keys && $num_long_gtfs_keys ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('gtfs.mixed_feed_suffix', foreign($example_long_gtfs_key), foreign($example_short_gtfs_key)) );
            } else {
                if ( $relation_ptr->{'gtfs_keys'}->{'gtfs:release_date'} ) {
                    if ( $num_short_gtfs_keys == 1 ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('gtfs.orphaned_key', 'gtfs:release_date', foreign($relation_ptr->{'gtfs_keys'}->{'gtfs:release_date'})) );
                    }
                }
            }
        }

        if ( $relation_ptr->{'tag'}->{'line'} ) {
            push( @{$relation_ptr->{'__notes__'}}, note('tag.line_reserved', foreign($relation_ptr->{'tag'}->{'line'})) );
        }

        if ( $relation_ptr->{'tag'}->{'public_transport'} ) {
            if ( exists($relation_ptr->{'tag'}->{'public_transport:version'}) && $relation_ptr->{'tag'}->{'public_transport:version'} == '2') {
                push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.tag_undefined_for_route', foreign($relation_ptr->{'tag'}->{'public_transport'}), printRelationInjectData($relation_ptr->{'id'},('public_transport='))) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.tag_undefined_for_route', foreign($relation_ptr->{'tag'}->{'public_transport'}), printRelationInjectData($relation_ptr->{'id'},('public_transport=','public_transport:version=2'))) );
            }
        }

        #
        # check route_master/route specific things
        #

        if ( $type eq 'route_master' ) {
            $return_code = analyze_route_master_relation( $relation_ptr, $relation_id, $entryref );
        } elsif ( $type eq 'route') {
            $return_code = analyze_route_relation( $relation_ptr, $relation_id, $entryref );
        }

        #
        # search for empty values in tags
        # search for whitespace characters in key
        # search for potentially problematic characters in keys
        #
        my $value = '';
        my $char  = '';
        foreach my $tag ( @relation_tags ) {
            if ( !exists($relation_ptr->{'tag'}->{$tag})       ||
                 !defined($relation_ptr->{'tag'}->{$tag})      ||
                          $relation_ptr->{'tag'}->{$tag} eq ''    ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('tag.empty_value', $tag) );
            }
            while ( $tag =~ m/([=\+\/\&\<\>;\'\"\?%\#@\\\r\t\n, ])/g ) {
                $char = $1;
                $value = defined($relation_ptr->{'tag'}->{$tag}) ? $relation_ptr->{'tag'}->{$tag} : '';
                if ( $char eq ' ' || $char eq "\r" || $char eq "\n" || $char eq "\t" ) {
                    push( @{$relation_ptr->{'__notes__'}}, note('tag.whitespace_in_key', $tag, $char, ord($char), $value) );
               } else {
                    push( @{$relation_ptr->{'__notes__'}}, note('tag.problematic_char_key', $tag, $char, $value) );
                }
            }
        }
        #
        # Link to GTFS data shall be shown and/or problems shall be reported
        #
        if ( $link_gtfs || $check_gtfs ) {
            my @gtfs_infos = getGtfsInfos( $relation_ptr );
            printf STDERR "gtfs_infos = %s\n", Data::Dumper::Dumper(\@gtfs_infos)   if ( $debug );
            if ( $link_gtfs ) {
                $relation_ptr->{'GTFS-HTML-TAG'} = jointext( ', ', map { gtfsInfoMsg( $_ ); } @gtfs_infos );
            }
            if ( $check_gtfs ) {
                foreach my $gtfs_info ( @gtfs_infos ) {
                    if ( $gtfs_info->{'link'}->{'status'} ne 'valid' ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('gtfs.problem', gtfs_status_msg( $gtfs_info->{'link'} )) );
                    }
                }
            }
        }
        #
        #
        #
        if ( $check_dates ) {
            foreach $datetag ( @datetags ) {
                foreach my $tag ( @relation_tags ) {
                    if ( $tag =~ m/^\Q$datetag\E$/ ) {
                        if ( defined($relation_ptr->{'tag'}->{$tag}) ) {
                            $datevalue = $relation_ptr->{'tag'}->{$tag};
                            if ( $datevalue !~ m/^([0-9][0-9][0-9][0-9])-([01][0-9])-([0-3][0-9])$/ ) {
                                push( @{$relation_ptr->{'__notes__'}}, note('date.not_iso8601', $tag, $datevalue) );
                            } else {
                                printf STDERR "Checking for correct date: '%s' = '%s-%s-%s'\n", $tag, $1, $2, $3  if ( $debug );
                                eval {
                                    timelocal (0, 0, 0, $3, $2-1, $1-1900);
                                };
                                # $@ is set when an exception occurs: i.e. the date does not exist
                                if ( $@ ) {
                                    printf STDERR "%s' = '%s-%s-%s': The date does not exist\n", $tag, $1, $2, $3  if ( $debug );
                                    push( @{$relation_ptr->{'__issues__'}}, issue('tag.value_issue', $tag, $datevalue, issue('date.not_exists')) );
                                }

                            }
                        }
                    }
                }
            }
        }
    }

    return $return_code;
}


#############################################################################################

sub analyze_route_master_relation {
    my $relation_ptr    = shift;
    my $relation_id     = shift;
    my $entryref        = shift || undef;
    my $return_code     = 0;

    my $ref                            = defined($relation_ptr->{'tag'}->{'ref'}) ? $relation_ptr->{'tag'}->{'ref'} : '';
    my $type                           = $relation_ptr->{'tag'}->{'type'} || '';
    my $route_type                     = $relation_ptr->{'route_master_type_value'}  || '';
    my $member_index                   = scalar( @{$relation_ptr->{'members'}} );
    my $relation_index                 = scalar( @{$relation_ptr->{'relation'}} );
    my $route_master_relation_index    = scalar( @{$relation_ptr->{'route_master_relation'}} );
    my $route_relation_index           = scalar( @{$relation_ptr->{'route_relation'}} );
    my $way_index                      = scalar( @{$relation_ptr->{'way'}} );
    my $route_highway_index            = scalar( @{$relation_ptr->{'route_highway'}} );
    my $node_index                     = scalar( @{$relation_ptr->{'node'}} );
    my $members_with_role              = 0;
    my %members_with_role_hash         = ();
    my %members_roles                  = ();

    $relation_ptr->{'missing_way_data'}   = 0;
    $relation_ptr->{'missing_node_data'}  = 0;
    $relation_ptr->{'missing_relation_data'}  = 0;

    $return_code += CheckCompletenessOfData( $relation_ptr );

    unless ( $route_master_relation_index ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('master.no_routes') );
    }
    #if ( $route_master_relation_index == 1 ) {
    #    $notes_string = gettext( "Route-Master with only 1 Route" );
    #    push( @{$relation_ptr->{'__notes__'}}, $notes_string );
    #}
    if ( $route_master_relation_index != $relation_index ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('master.has_relations') );
    }
    if ( $way_index ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('master.has_ways') );
    }
    if ( $node_index ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('master.has_nodes') );
    }
    foreach my $member ( @{$relation_ptr->{'members'}} )
    {
        if ( $member->{'role'} ) {
            $members_with_role++;
            $members_with_role_hash{$member->{'ref'}} = $member->{'type'};
            $members_roles{$member->{'role'}}         = 1;
        }
    }
    if ( $members_with_role ) {
        my $helpstring = issue('master.members_with_role', $members_with_role, $members_with_role);
        if ( 1 ) {
            my @help_array = sort ( keys ( %members_roles ) );
            push( @{$relation_ptr->{'__issues__'}}, issue('master.members_with_role_list', $helpstring, list_msg('role_or', @help_array )) );
        } else {
            my @help_array = sort ( keys ( %members_with_role_hash ) );
            if ( $max_error && $max_error > 0 && $members_with_role > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printXxxTemplate($members_with_role_hash{$_},$_,'name;ref'); } splice(@help_array,0,$max_error)], ($members_with_role-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printXxxTemplate($members_with_role_hash{$_},$_,'name;ref'); } @help_array]) );
            }
        }
    }
    if ( $relation_ptr->{'tag'}->{'public_transport:version'} ) {
        if ( $relation_ptr->{'tag'}->{'public_transport:version'} !~ m/^2$/ ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.version_not_2') . printRelationInjectData($relation_ptr->{'id'},('public_transport:version=2')) )        if ( $check_version );
        } else {
            ; #push( @{$relation_ptr->{'__notes__'}}, msg("'public_transport:version' = '%s'",foreign($relation_ptr->{'tag'}->{'public_transport:version'})) )    if ( $positive_notes );
        }
    } # else {
    #    $notes_string = gettext( "'public_transport:version' is not set" );
    #    push( @{$relation_ptr->{'__notes__'}}, $notes_string )        if ( $check_version );
    #}

    #
    # relation shall be shown on jungle-bus' unroll page: https://jungle-bus.github.io/unroll/route.html?qa=yes&line=<relation_id>
    #
    $relation_ptr->{'unroll_relation'} = 1;

    return $return_code;
}


#############################################################################################

sub analyze_route_relation {
    my $relation_ptr    = shift;
    my $relation_id     = shift;
    my $entryref        = shift || undef;
    my $return_code     = 0;

    my $ref                            = defined($relation_ptr->{'tag'}->{'ref'}) ? $relation_ptr->{'tag'}->{'ref'} : '';
    my $type                           = $relation_ptr->{'tag'}->{'type'} || '';
    my $route_type                     = $relation_ptr->{'route_type_value'}  || '';
    my $route_relation_index           = $relation_ptr->{'route_relation'} ? scalar( @{$relation_ptr->{'route_relation'}} ) : 0;
    my $route_highway_index            = $relation_ptr->{'route_highway'}  ? scalar( @{$relation_ptr->{'route_highway'}} )  : 0;
    my $node_index                     = $relation_ptr->{'node'}           ? scalar( @{$relation_ptr->{'node'}} )           : 0;

    $relation_ptr->{'missing_way_data'}   = 0;
    $relation_ptr->{'missing_node_data'}  = 0;
    $relation_ptr->{'missing_relation_data'}  = 0;

    $return_code += CheckCompletenessOfData( $relation_ptr );

    if ( $relation_ptr->{'tag'}->{'public_transport:version'} && $relation_ptr->{'tag'}->{'public_transport:version'} eq '2' ) {
        if ( $relation_ptr->{'missing_way_data'} == 0 && $relation_ptr->{'missing_node_data'} == 0 && $relation_ptr->{'missing_relation_data'} == 0 ) {
            $return_code = analyze_ptv2_route_relation( $relation_ptr );
        } else {
            push( @{$relation_ptr->{'__issues__'}}, issue('data.skipped_incomplete') );
        }
        #
        # PTv2 relation can be edited with "Relatify" (initially supported only 'bus' routes, since 2024-10-* also 'tram')
        #
        if ( $route_type eq 'bus' || $route_type eq 'tram' ) {
            $relation_ptr->{'relatify_relation'} = 1;
        }

    } else {
        unless ( $route_highway_index ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('route.no_ways') );
        }
        if( $route_highway_index == 1 && $route_type ne 'monorail' && $route_type ne 'ferry' && $route_type ne 'aerialway' && $route_type ne 'funicular' ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('route.one_way') );
        }
        unless ( $node_index ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('route.no_stops') );
        }
        if ( $node_index == 1 ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('route.one_stop') );
        }
        if ( $route_relation_index ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('route.has_relations') );
        }
        if ( $relation_ptr->{'tag'}->{'public_transport:version'} ) {
            if ( $relation_ptr->{'tag'}->{'public_transport:version'} ne '1' ) {
                push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.version_invalid') . printRelationInjectData($relation_ptr->{'id'},('public_transport:version=2')) );
            } else {
                #push( @{$relation_ptr->{'__notes__'}}, msg("'public_transport:version' = '%s'",foreign($relation_ptr->{'tag'}->{'public_transport:version'})) )    if ( $positive_notes );
            }
        } #else {
        #    $notes_string = gettext( "'public_transport:version' is not set" );
        #    push( @{$relation_ptr->{'__notes__'}}, $notes_string )        if ( $check_version );
        #}
    }

    #
    # for WAYS used by vehicles             vehicles must use the right type of way
    #
    if ( $check_way_type ) {
        $return_code += CheckWayType( $relation_ptr );
    }

    #
    # for WAYS used by vehicles             vehicles must have access permission
    # for NODES of WAYS used by vehicles    vehicles must have access permission on barrier NODES
    #
    if ( $check_access ) {
        $return_code += CheckAccessOnWaysAndNodes( $relation_ptr );
    }

    #
    # all WAYS          must not have "highway" = "bus_stop" set - allowed only on nodes
    # all RELATIONS     must not have "highway" = "bus_stop" set - allowed only on nodes
    #
    if ( $check_bus_stop ) {
        $return_code += CheckBusStopOnWaysAndRelations( $relation_ptr );
    }

    #
    # check tag 'route_ref' on stops (highway_bus_stop and public_transport=platform (and also public_transport=stop_position))
    #
    if ( $check_route_ref ) {
        $return_code += CheckRouteRefOnStops( $relation_ptr );
    }

    #
    # check whether 'gtfs:agency_name' fits 'gtfs_agancy_id'
    # check whether 'gtfs:route_id' belongs to 'gtfs:agency_id'
    # check whether 'gtfs:trip_id'/'gtfs:trip_id:sample' belongs to 'gtfs:route_id'
    # check whether 'gtfs:shape_id' belongs to 'gtfs:trip_id'/'gtfs:trip_id:sample'
    #
    if ( $check_gtfs ) {
        ;
    }

    #
    # relation shall be shown on PTNA's special map
    #
    $relation_ptr->{'show_relation'} = 1;

    return $return_code;
}


#############################################################################################

sub analyze_ptv2_route_relation {
    my $relation_ptr    = shift;
    my $relation_id     = shift;
    my $entryref        = shift || undef;
    my $return_code     = 0;

    my $type                                = $relation_ptr->{'tag'}->{'type'};
    my $route_type                          = $relation_ptr->{'route_type_value'};
    my $role_mismatch_found                 = 0;
    my %role_mismatch                       = ();
    my @sorted_way_nodes                    = ();
    my @help_array                          = ();
    my $help_string                         = '';
    my $num_of_errors                       = 0;
    my $access_restriction                  = undef;

    my $number_of_route_relation            = $relation_ptr->{'route_relation'} ? scalar( @{$relation_ptr->{'route_relation'}} ) : 0;

    my @relation_route_highways             = FindRouteHighWays( $relation_ptr );
    my %relation_route_highways_hash        = ();
    my $number_of_route_highways            = scalar( @relation_route_highways );

    my @relation_route_stop_positions       = FindRouteStopPositions( $relation_ptr );  # stop positions are nodes only
    my $number_of_route_stop_positions      = scalar( @relation_route_stop_positions );

    my @relation_route_platform_nodes       = FindRoutePlatformNodes( $relation_ptr );
    my @relation_route_platform_ways        = FindRoutePlatformWays( $relation_ptr );
    my @relation_route_platform_relations   = FindRoutePlatformRelations( $relation_ptr );
    my $number_of_route_platform_nodes      = scalar( @relation_route_platform_nodes );
    my $number_of_route_platform_ways       = scalar( @relation_route_platform_ways );
    my $number_of_route_platform_relations  = scalar( @relation_route_platform_relations );
    my $number_of_route_platforms           = $number_of_route_platform_nodes + $number_of_route_platform_ways + $number_of_route_platform_relations;

    if ( $number_of_route_highways ) {
        map { $relation_route_highways_hash{$_} = 1; } @relation_route_highways;
    } else {
        push( @{$relation_ptr->{'__issues__'}}, issue('route.no_ways') );
    }
    if ( $number_of_route_highways == 1 && $route_type ne 'monorail' && $route_type ne 'ferry' && $route_type ne 'aerialway' && $route_type ne 'funicular' ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('route.one_way') );
    }
    if ( $number_of_route_stop_positions == 0 && $number_of_route_platforms == 0 ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.no_stop_no_platform') );
    } else {
        unless ( $number_of_route_stop_positions ) {
            push( @{$relation_ptr->{'__notes__'}}, note('ptv2.no_stop') );
        }
        if ( $number_of_route_stop_positions == 1 ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.one_stop') );
        }
        unless ( $number_of_route_platforms ) {
            push( @{$relation_ptr->{'__notes__'}},note('ptv2.no_platform') );
        }
        if ( $number_of_route_platforms == 1 ) {
            push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.one_platform') );
        }
    }
    if ( $number_of_route_relation ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('route.has_relations') );
    }

    $relation_ptr->{'non_platform_ways'}                = \@relation_route_highways;
    $relation_ptr->{'number_of_segments'}               = 0;
    $relation_ptr->{'gap_at_way'}                       = ();
    $relation_ptr->{'number_of_traversed_roundabouts'}  = 0;
    $relation_ptr->{'traversed_roundabout'}             = ();
    $relation_ptr->{'sorted_in_reverse_order'}          = '';

    if ( $check_name ) {
        $return_code += CheckNameRefFromViaToPTV2( $relation_ptr );
    }

    if ( $check_from_to || $check_via ) {
        $return_code += CheckFromViaToPlatformNamesPTV2( $relation_ptr );
    }

    if ( $relation_route_highways[0] && $relation_route_highways[1] ) {
        #
        # special check for route being sorted in reverse order and starting with a oneway (except closed way)
        # another check for first way being a oneway way being used in wrong direction
        #
        my $first_way_id    = $relation_route_highways[0];
        my $second_way_id   = $relation_route_highways[1];
        my $entry_node_id1  = undef;
        my $exit_node_id1   = undef;
        my $entry_node_id2  = undef;
        my $exit_node_id2   = undef;
        printf STDERR "analyze_ptv2_route_relation() : at least two ways exist: 1st = %d, 2nd = %s\n", $first_way_id, $second_way_id     if ( $debug );
        if ( !isClosedWay($first_way_id) ) {
            printf STDERR "analyze_ptv2_route_relation() : first way is not a closed way\n"     if ( $debug );
            if ( 0 != ($entry_node_id1 = isOneway($first_way_id,undef)) ) {
                printf STDERR "analyze_ptv2_route_relation() : first way is onway with entry_node_id1 = %d\n", $entry_node_id1     if ( $debug );
                if ( $entry_node_id1 == $WAYS{$first_way_id}->{'first_node'} ) {
                    $exit_node_id1 = $WAYS{$first_way_id}->{'last_node'};
                    printf STDERR "analyze_ptv2_route_relation() : exit_node_id1 = %d is 'last_node'\n", $exit_node_id1     if ( $debug );
                } else {
                    $exit_node_id1 = $WAYS{$first_way_id}->{'first_node'};
                    printf STDERR "analyze_ptv2_route_relation() : exit_node_id1 = %d is 'first_node'\n", $exit_node_id1     if ( $debug );
                }
                if ( isNodeInNodeArray($exit_node_id1,@relation_route_stop_positions) ) {
                    printf STDERR "analyze_ptv2_route_relation() : exit_node_id1 is in relations's stop node array\n" if ( $debug );
                    #
                    # OK, let's check whether this stop-position is not a connecting node to the second way
                    #
                    if ( $exit_node_id1 == $WAYS{$second_way_id}->{'first_node'} ||
                         $exit_node_id1 == $WAYS{$second_way_id}->{'last_node'}     ) {
                        #
                        # OK: so it's: ->->->->Sn----Cn------Cn--- which means, the route starts too early (found and reported later on)
                        #
                        ;
                    } else {      # Sn == Stop-Node; Cn == Connecting-Node; ----- == normal Way; ->->->-> == Oneway
                        #
                        #
                        # Bad: it's: Sn<-<-<-<Cn---Cn----- and reverse it's OK: -----Cn---Cn->->->->Sn
                        #
                        $relation_ptr->{'sorted_in_reverse_order'} = 1;
                    }
                } else {
                    if ( 0 == isOneway($second_way_id,undef) ) {
                        #
                        # second way is not a oneway
                        #
                        if ( $entry_node_id1 == $WAYS{$second_way_id}->{'first_node'} ||
                             $entry_node_id1 == $WAYS{$second_way_id}->{'last_node'}     ) {
                            printf STDERR "analyze_ptv2_route_relation() : entering first way (=oneway) in wrong direction %s:", $first_way_id     if ( $debug );
                            $relation_ptr->{'wrong_direction_oneways'}->{$first_way_id} = 1;
                        }
                    }
                }
            }
        }
    }

    if ( $check_sequence ) {
        #
        # check for correct sequence of members: stop1, platform1, stop2, platform2, ... way1, way2, ...
        #
        my $have_seen_stop            = 0;
        my $have_seen_platform        = 0;
        my $have_seen_highway_railway = 0;

        $relation_ptr->{'wrong_sequence'} = 0;

        foreach my $item ( @{$relation_ptr->{'members'}} ) {
            if ( $item->{'type'} eq 'node' ) {
                if ( $stop_nodes{$item->{'ref'}} ) {
                    $have_seen_stop++;
                    $relation_ptr->{'wrong_sequence'}++     if ( $have_seen_highway_railway );
                    #printf STDERR "stop node after way for %s\n", $item->{'ref'};
                } elsif ( $platform_nodes{$item->{'ref'}} ) {
                    $have_seen_platform++;
                    $relation_ptr->{'wrong_sequence'}++     if ( $have_seen_highway_railway );
                    #printf STDERR "platform node after way for %s\n", $item->{'ref'};
                }
            } elsif ( $item->{'type'} eq 'way' ) {
                if ( $platform_ways{$item->{'ref'}} ) {
                    $have_seen_platform++;
                    $relation_ptr->{'wrong_sequence'}++     if ( $have_seen_highway_railway );
                    #printf STDERR "platform way after way for %s\n", $item->{'ref'};
                } elsif ( $WAYS{$item->{'ref'}}->{'tag'}->{'railway'} ) {
                    if ( $WAYS{$item->{'ref'}}->{'tag'}->{'railway'} ne 'platform' ) {
                        $have_seen_highway_railway++;
                    }
                } elsif ( $WAYS{$item->{'ref'}}->{'tag'}->{'highway'} ) {
                    if ( $WAYS{$item->{'ref'}}->{'tag'}->{'highway'} ne 'platform' &&
                         $WAYS{$item->{'ref'}}->{'tag'}->{'highway'} ne 'bus_stop'    ) {
                        $have_seen_highway_railway++;
                    }
                }
            } elsif ( $item->{'type'} eq 'relation' ) {
                if ( $platform_multipolygon_relations{$item->{'ref'}} ) {
                    $have_seen_platform++;
                    $relation_ptr->{'wrong_sequence'}++     if ( $have_seen_highway_railway );
                    #printf STDERR "platform relation after way for %s\n", $item->{'ref'};
                }
            }
        }
    }

    printf STDERR "analyze_ptv2_route_relation() : SortRouteWayNodes() for relation ref=%s, name=%s\n", (defined($relation_ptr->{'tag'}->{'ref'}) ? $relation_ptr->{'tag'}->{'ref'} : ''), ($relation_ptr->{'tag'}->{'name'} || '')   if ( $debug );

    @sorted_way_nodes    = SortRouteWayNodes( $relation_ptr, $relation_ptr->{'non_platform_ways'} );

    if ( $relation_ptr->{'sorted_in_reverse_order'} ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.first_oneway_no_exit') );
        $return_code++
    }
    if ( $relation_ptr->{'number_of_segments'} > 1 ) {
        my @help_array     = @{$relation_ptr->{'gap_at_way'}};
        my $num_of_errors  = scalar(@help_array);
        my $error_string   = issue('ptv2.gap_in_route', $relation_ptr->{'number_of_segments'}-1, $relation_ptr->{'number_of_segments'});
        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
            push( @{$relation_ptr->{'__issues__'}}, listed($error_string, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
        } else {
            push( @{$relation_ptr->{'__issues__'}}, listed($error_string, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
        }
        $return_code += $relation_ptr->{'number_of_segments'} - 1;
    }
    if ( $relation_ptr->{'number_of_traversed_roundabouts'} > 0 ) {
        foreach my $roundabout_id ( keys %{$relation_ptr->{'traversed_roundabout'}} ) {
            my @help_array     = keys %{$relation_ptr->{'traversed_roundabout'}->{$roundabout_id}};
            my $num_of_errors  = scalar(@help_array);
            my $error_string   = issue('ptv2.way_into_roundabout', $num_of_errors, printWayTemplate($roundabout_id,'name;ref'));
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed($error_string, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, listed($error_string, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
            }
        }
        $return_code += $relation_ptr->{'number_of_traversed_roundabouts'};
    }
    if ( $relation_ptr->{'wrong_sequence'} ) {
        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.wrong_order') );
        $return_code++;
    }
    if ( $check_roundabouts ) {
        my @help_array    = sort( keys( %{$relation_ptr->{'roundabout_segments_at'}} ) );
        my $num_of_errors = scalar( @help_array );
        if ( $num_of_errors ) {
            my $error_string   = note('ptv2.roundabout_partial', $num_of_errors, $num_of_errors);
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__notes__'}}, listed($error_string, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__notes__'}}, listed($error_string, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
            }
            $return_code++;
        }
    }
    if ( $relation_ptr->{'wrong_direction_oneways'} ) {
        my @help_array     = sort(keys(%{$relation_ptr->{'wrong_direction_oneways'}}));
        my $num_of_errors  = scalar(@help_array);
        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
            push( @{$relation_ptr->{'__issues__'}}, listed(issue('ptv2.oneway_wrong_direction', $num_of_errors), [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
        } else {
            push( @{$relation_ptr->{'__issues__'}}, listed(issue('ptv2.oneway_wrong_direction', $num_of_errors), [map { printWayTemplate($_,'name;ref'); } @help_array]) );
        }
        $return_code++;
    }
    if ( $relation_ptr->{'number_of_segments'} == 1 && $check_motorway_link && $relation_ptr->{'expect_motorway_after'} ) {
        my @help_array    = sort(keys(%{$relation_ptr->{'expect_motorway_after'}}));
        my $num_of_errors = scalar(@help_array);
        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
            push( @{$relation_ptr->{'__issues__'}}, listed(issue('ptv2.motorway_link_no_motorway', $num_of_errors), [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
        } else {
            push( @{$relation_ptr->{'__issues__'}}, listed(issue('ptv2.motorway_link_no_motorway', $num_of_errors), [map { printWayTemplate($_,'name;ref'); } @help_array]) );
        }
        $return_code++;
    }
    if ( $relation_ptr->{'number_of_segments'} == 1 && $relation_ptr->{'roundabout_follows_itself'} ) {
        my @help_array    = sort(keys(%{$relation_ptr->{'roundabout_follows_itself'}}));
        my $num_of_errors = scalar(@help_array);
        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
            push( @{$relation_ptr->{'__issues__'}}, listed(issue('ptv2.roundabout_twice', $num_of_errors), [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
        } else {
            push( @{$relation_ptr->{'__issues__'}}, listed(issue('ptv2.roundabout_twice', $num_of_errors), [map { printWayTemplate($_,'name;ref'); } @help_array]) );
        }
        $return_code++;
    }
    #
    # NODES     are either Stop-Positions or Platforms, so they must have a 'role'
    #
    foreach my $node_ref ( @{$relation_ptr->{'node'}} ) {
        if ( $node_ref->{'role'} ){
            if ( $node_ref->{'role'} =~ m/^stop$/                   ||
                 $node_ref->{'role'} =~ m/^stop_entry_only$/        ||
                 $node_ref->{'role'} =~ m/^stop_exit_only$/         ||
                 $node_ref->{'role'} =~ m/^platform$/               ||
                 $node_ref->{'role'} =~ m/^platform_entry_only$/    ||
                 $node_ref->{'role'} =~ m/^platform_exit_only$/        ) {

                if ( $xml_has_nodes ) {
                    if ( $node_ref->{'role'} =~ m/^stop/ ) {
                        if ( $stop_nodes{$node_ref->{'ref'}} ) {
                            if ( isNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) ) {

                                # checking roles stop_entry_only and stop_exit_only makes only sense if there are no gaps, i.e. the ways are sorted
                                # checking stop_exit_only and stop_entry_only is not performed
                                # MVV Bus 213 (Munich) has stops at Karl-Preis-Platz which are neither first nor last nodes.

                                if ( $relation_ptr->{'number_of_segments'} == 1 ) {
                                      #
                                    ; # fine, what can we check here now?
                                      #

                                    #if ( $node_ref->{'role'} eq 'stop_entry_only' ) {
                                    #    if ( isFirstNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) ) {
                                    #        ; # fine, what else can we check here?
                                    #    }
                                    #    else {
                                    #        $role_mismatch{"'role' = 'stop_entry_only' is not first node of first way"}->{$node_ref->{'ref'}} = 1;
                                    #        $role_mismatch_found++;
                                    #    }
                                    #}
                                    #if ( $node_ref->{'role'} eq 'stop_exit_only' ) {
                                    #    if ( isLastNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) ) {
                                    #       ; # fine, what else can we check here?
                                    #    }
                                    #    else {
                                    #        $role_mismatch{"'role' = 'stop_exit_only' is not last node of last way"}->{$node_ref->{'ref'}} = 1;
                                    #        $role_mismatch_found++;
                                    #    }
                                    #}
                                }
                                if ( scalar(@relation_route_highways) == 1 ) {
                                    my $entry_node_id = isOneway( $relation_route_highways[0], undef );
                                    if ( $entry_node_id != 0 ) {
                                        # it is a oneway
                                        if ( $node_ref->{'role'} eq 'stop_exit_only' && isFirstNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) ) {
                                            $role_mismatch{mkey(issue('ptv2.first_node_oneway_exit_only'))}->{$node_ref->{'ref'}} = 1;
                                            $role_mismatch_found++;
                                        }
                                        if ( $node_ref->{'role'} eq 'stop_entry_only' && isLastNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) ) {
                                            $role_mismatch{mkey(issue('ptv2.last_node_oneway_entry_only'))}->{$node_ref->{'ref'}} = 1;
                                            $role_mismatch_found++;
                                        }
                                    }
                                } elsif ( scalar(@relation_route_highways) > 1 ) {
                                    #
                                    # for routes with more than 1 way
                                    #
                                    # do not consider roundtrip routes where first and last node is the same node but passengers have to leave the bus/tram/...
                                    #
                                    if ( $node_ref->{'role'} eq 'stop_exit_only' ) {
                                        if ( isFirstNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) && !isLastNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) ) {
                                            $role_mismatch{mkey(issue('ptv2.first_node_exit_only'))}->{$node_ref->{'ref'}} = 1;
                                            $role_mismatch_found++;
                                        }
                                    }
                                    if ( $node_ref->{'role'} eq 'stop_entry_only' ) {
                                        if ( isLastNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) && ! isFirstNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) ) {
                                            $role_mismatch{mkey(issue('ptv2.last_node_entry_only'))}->{$node_ref->{'ref'}} = 1;
                                            $role_mismatch_found++;
                                        }
                                    }
                                }
                            } else {
                                if ( $number_of_route_highways ) {
                                    $role_mismatch{mkey(issue('ptv2.stop_not_part_of_way'))}->{$node_ref->{'ref'}} = 1;
                                    $role_mismatch_found++;
                                }
                            }
                            if ( $check_stop_position ) {
                                if (  $relation_ptr->{'route_type_value'} eq 'bus'                     ||
                                     ($relation_ptr->{'route_type_value'} eq 'coach' && $allow_coach)  ||
                                      $relation_ptr->{'route_type_value'} eq 'tram'                    ||
                                      $relation_ptr->{'route_type_value'} eq 'share_taxi'                 ) {
                                    if ( $NODES{$node_ref->{'ref'}}->{'tag'}->{$relation_ptr->{'route_type_value'}}          &&
                                         $NODES{$node_ref->{'ref'}}->{'tag'}->{$relation_ptr->{'route_type_value'}} eq "yes"    ) {
                                        ; # fine
                                    } else {
                                        $help_string   = issue('ptv2.missing_yes_on_pt', $relation_ptr->{'route_type_value'}, 'stop_position');
                                        $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                                        $role_mismatch_found++;
                                    }
                                }
                            }
                        }
                        elsif ( $NODES{$node_ref->{'ref'}}->{'tag'}->{'public_transport'} ) {
                            $help_string   = issue('ptv2.role_pt_mismatch', $node_ref->{'role'}, $NODES{$node_ref->{'ref'}}->{'tag'}->{'public_transport'});
                            $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                            $role_mismatch_found++;
                        } elsif ( $ptv1_compatibility ne "no"  ) {
                            my $compatible_tag = PTv2CompatibleNodeStopTag( $node_ref->{'ref'}, $relation_ptr->{'route_type_value'} );
                            if ( $compatible_tag ) {
                                if ( $ptv1_compatibility eq "show" ) {
                                    $help_string   = issue('ptv2.role_suggest_stop', $node_ref->{'role'}, $compatible_tag);
                                    $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                                    $role_mismatch_found++;
                                }
                            } else {
                                my $with_lifecycle_prefix= '';
                                foreach my $lcp ( @lifecycle_prefixes ) {
                                    if ( $NODES{$node_ref->{'ref'}}->{'tag'}->{$lcp.':public_transport'} ) {
                                        $with_lifecycle_prefix = $lcp . ':public_transport';
                                        last;
                                    }
                                }
                                if ( $with_lifecycle_prefix) {
                                    $help_string   = issue('ptv2.role_pt_unset_but_set', $node_ref->{'role'}, $with_lifecycle_prefix);
                                } else {
                                    $help_string   = issue('ptv2.role_pt_unset', $node_ref->{'role'});
                                }
                                $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                                $role_mismatch_found++;
                            }
                        } else {
                            my $with_lifecycle_prefix= '';
                            foreach my $lcp ( @lifecycle_prefixes ) {
                                if ( $NODES{$node_ref->{'ref'}}->{'tag'}->{$lcp.':public_transport'} ) {
                                    $with_lifecycle_prefix = $lcp . ':public_transport';
                                    last;
                                }
                            }
                            if ( $with_lifecycle_prefix) {
                                $help_string   = issue('ptv2.role_pt_unset_but_set', $node_ref->{'role'}, $with_lifecycle_prefix);
                            } else {
                                $help_string   = issue('ptv2.role_pt_unset', $node_ref->{'role'});
                            }
                            $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                            $role_mismatch_found++;
                        }
                    } else {           # matches any platform of the three choices
                        if ( $platform_nodes{$node_ref->{'ref'}} ) {
                            if ( isNodeInNodeArray($node_ref->{'ref'},@sorted_way_nodes) ) {
                                $role_mismatch{mkey(issue('ptv2.platform_part_of_way'))}->{$node_ref->{'ref'}} = 1;
                                $role_mismatch_found++;
                            } else {
                                ; # fine, what else can we check here?
                            }
                            #
                            # bus=yes, tram=yes or share_taxi=yes is not required on public_transport=platform
                            #
                            if ( $check_platform ) {
                                if (  $relation_ptr->{'route_type_value'} eq 'bus'                     ||
                                     ($relation_ptr->{'route_type_value'} eq 'coach' && $allow_coach)  ||
                                      $relation_ptr->{'route_type_value'} eq 'tram'                    ||
                                      $relation_ptr->{'route_type_value'} eq 'share_taxi'                 ) {
                                    if ( $NODES{$node_ref->{'ref'}}->{'tag'}->{$relation_ptr->{'route_type_value'}}          &&
                                         $NODES{$node_ref->{'ref'}}->{'tag'}->{$relation_ptr->{'route_type_value'}} eq "yes"    ) {
                                        ; # fine
                                    }
                                    else {
                                        $help_string   = issue('ptv2.missing_yes_on_pt', $relation_ptr->{'route_type_value'}, 'platform');
                                        $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                                        $role_mismatch_found++;
                                    }
                                }
                            }
                        } elsif ( $NODES{$node_ref->{'ref'}}->{'tag'}->{'public_transport'} ) {
                            $help_string   = issue('ptv2.role_pt_mismatch', $node_ref->{'role'}, $NODES{$node_ref->{'ref'}}->{'tag'}->{'public_transport'});
                            $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                            $role_mismatch_found++;
                        } elsif ( $ptv1_compatibility ne "no"  ) {
                            my $compatible_tag = PTv2CompatibleNodePlatformTag( $node_ref->{'ref'}, $relation_ptr->{'route_type_value'} );
                            if ( $compatible_tag ) {
                                if ( $ptv1_compatibility eq "show" ) {
                                    $help_string   = issue('ptv2.role_suggest_platform', $node_ref->{'role'}, $compatible_tag);
                                    $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                                    $role_mismatch_found++;
                                }
                            } else {
                                my $with_lifecycle_prefix= '';
                                foreach my $lcp ( @lifecycle_prefixes ) {
                                    if ( $NODES{$node_ref->{'ref'}}->{'tag'}->{$lcp.':public_transport'} ) {
                                        $with_lifecycle_prefix = $lcp . ':public_transport';
                                        last;
                                    }
                                }
                                if ( $with_lifecycle_prefix) {
                                    $help_string   = issue('ptv2.role_pt_unset_but_set', $node_ref->{'role'}, $with_lifecycle_prefix);
                                } else {
                                    $help_string   = issue('ptv2.role_pt_unset', $node_ref->{'role'});
                                }
                                $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                                $role_mismatch_found++;
                            }
                        } else {
                            my $with_lifecycle_prefix= '';
                            foreach my $lcp ( @lifecycle_prefixes ) {
                                if ( $NODES{$node_ref->{'ref'}}->{'tag'}->{$lcp.':public_transport'} ) {
                                    $with_lifecycle_prefix = $lcp . ':public_transport';
                                    last;
                                }
                            }
                            if ( $with_lifecycle_prefix) {
                                $help_string   = issue('ptv2.role_pt_unset_but_set', $node_ref->{'role'}, $with_lifecycle_prefix);
                            } else {
                                $help_string   = issue('ptv2.role_pt_unset', $node_ref->{'role'});
                            }
                            $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                            $role_mismatch_found++;
                        }
                    }
                }
            } else {
                $help_string   = issue('ptv2.wrong_role', ctrl_escape($node_ref->{'role'}));
                $role_mismatch{mkey($help_string)}->{$node_ref->{'ref'}} = 1;
                $role_mismatch_found++;
            }
        } else {
            # code for issue #161
            my $helpstring;
            if ( $NODES{$node_ref->{'ref'}}->{'tag'} && $NODES{$node_ref->{'ref'}}->{'tag'}->{'public_transport'} ) {
                if ( $NODES{$node_ref->{'ref'}}->{'tag'}->{'public_transport'} eq 'stop_position' ) {
                    $helpstring    = issue('ptv2.empty_role_stop');
                } elsif ( $NODES{$node_ref->{'ref'}}->{'tag'}->{'public_transport'} eq 'platform') {
                    $helpstring    = issue('ptv2.empty_role_platform');
                } else {
                    $helpstring    = issue('ptv2.empty_role_unknown_pt', $NODES{$node_ref->{'ref'}}->{'tag'}->{'public_transport'});
                }
            } else {
                $helpstring    = issue('ptv2.empty_role_no_pt');
            }
            $role_mismatch{mkey($helpstring)}->{$node_ref->{'ref'}} = 1;
            $role_mismatch_found++;
        }
    }
    if ( $role_mismatch_found ) {
        foreach my $role ( sort ( keys ( %role_mismatch ) ) ) {
            @help_array     = sort(keys(%{$role_mismatch{$role}}));
            $num_of_errors  = scalar(@help_array);
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed(unkey($role), [map { printNodeTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, listed(unkey($role), [map { printNodeTemplate($_,'name;ref'); } @help_array]) );
            }
        }
    }
    $return_code += $role_mismatch_found;

    if ( $relation_ptr->{'number_of_segments'} == 1 ) {
        printf STDERR "Checking whether first node is member of relation_route_stop_positions: Route-Name: %s\n", ($relation_ptr->{'tag'}->{'name'} || '')      if ( $debug );
        if ( isNodeInNodeArray($sorted_way_nodes[0],@relation_route_stop_positions) ) {
            #
            # fine, first node of ways is actually a stop position of this route
            #
            if ( $sorted_way_nodes[0] == $relation_route_stop_positions[0] ) {
                #
                # fine, first stop position in the list is actually the first node of the way
                #
                ;
            } else {
                if ( scalar(@relation_route_highways) > 1 || isOneway($relation_route_highways[0],undef) ) {
                    #
                    # if we have more than one way or the single way is a oneway, and because we know: the ways are sorted and w/o gaps
                    #
                    push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.first_node_not_first_stop', printNodeTemplate($sorted_way_nodes[0],'name;ref'), printNodeTemplate($relation_route_stop_positions[0],'name;ref')) );
                    $return_code++;
                }
            }
        } else {
            printf STDERR "No! Checking whether we can be relaxed: Route-Name: %s\n", $relation_ptr->{'tag'}->{'name'}      if ( $debug );
            my $relaxed_for =  $relaxed_begin_end_for || '';
            $relaxed_for    =~ s/;/,/g;
            $relaxed_for    =  ',' . $relaxed_for . ',';
            if ( $relaxed_for =~ m/,\Q$relation_ptr->{'route_type_value'}\E,/ ) {
                my $first_way_ID     = $relation_route_highways[0];
                my @first_way_nodes  = ();
                my $found_it         = 0;
                my $found_nodeid     = 0;
                my $node_name       = '';

                if ( $sorted_way_nodes[0] == ${$WAYS{$first_way_ID}->{'chain'}}[0] ) {
                    @first_way_nodes  = @{$WAYS{$first_way_ID}->{'chain'}};
                } else {
                    @first_way_nodes  = reverse @{$WAYS{$first_way_ID}->{'chain'}};
                }

                foreach my $nodeid ( @first_way_nodes ) {
                    if ( $debug ) { $node_name = ( $NODES{$nodeid} && $NODES{$nodeid}->{'tag'} && $NODES{$nodeid}->{'tag'}->{'name'}) ? $NODES{$nodeid}->{'tag'}->{'name'} : ''; }
                    printf STDERR "WAY{%s}->{'chain'}->%s name='%s'\n", $first_way_ID, $nodeid, $node_name   if ( $debug );
                    if ( isNodeInNodeArray($nodeid,@relation_route_stop_positions) ) {
                        #
                        # fine, an inner node, or the last of the first way is a stop position of this route
                        #
                        $found_it++;
                        printf STDERR "WAY{%s}->{'chain'}->%s - %d\n", $first_way_ID, $nodeid, $found_it   if ( $debug );
                        if ( $nodeid == $relation_route_stop_positions[0] ) {
                            #
                            # fine the first node of the first way which is a stop position and is actually the first stop position
                            #
                            $found_it++;
                            printf STDERR "WAY{%s}->{'chain'}->%s - %d\n", $first_way_ID, $nodeid, $found_it   if ( $debug );
                        }
                        $found_nodeid = $nodeid;
                        last;
                    }
                }
                if ( $found_it == 1 ) {
                    printf STDERR "1: Number of ways: %s, found_nodeid = %s, last node of first way = %s\n", scalar(@relation_route_highways), $found_nodeid, $first_way_nodes[$#first_way_nodes]  if ( $debug );
                    if ( scalar(@relation_route_highways) > 1 && $found_nodeid == $first_way_nodes[$#first_way_nodes] ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.way_before_first_stop', printWayTemplate($first_way_ID,'name;ref')) );
                        $return_code++;
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.first_stop_not_first', printNodeTemplate($found_nodeid,'name;ref'), printNodeTemplate($relation_route_stop_positions[0],'name;ref')) );
                        $return_code++;
                    }
                }
                elsif ( $found_it == 2 ) {
                    printf STDERR "2: Number of ways: %s, found_nodeid = %s, last node of first way = %s\n", scalar(@relation_route_highways), $found_nodeid, $first_way_nodes[$#first_way_nodes]  if ( $debug );
                    if ( scalar(@relation_route_highways) > 1 && $found_nodeid == $first_way_nodes[$#first_way_nodes] ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.way_before_first_stop', printWayTemplate($first_way_ID,'name;ref')) );
                        $return_code++;
                    }
                } else {
                    if ( $number_of_route_stop_positions > 0 ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.no_stop_on_first_way', printWayTemplate($first_way_ID,'name;ref')) );
                        $return_code++;
                    }
                }
            } else {
                if ( $number_of_route_stop_positions > 0 ) {
                    push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.first_node_not_stop', printNodeTemplate($sorted_way_nodes[0],'name;ref')) );
                    $return_code++;
                }
            }
        }
        printf STDERR "Checking whether last node is member of relation_route_stop_positions: Route-Name: %s\n", ($relation_ptr->{'tag'}->{'name'} || '')      if ( $debug );
        if ( isNodeInNodeArray($sorted_way_nodes[$#sorted_way_nodes],@relation_route_stop_positions) ) {
            #
            # fine, last node of ways is actually a stop position of this route
            #
            if ( $sorted_way_nodes[$#sorted_way_nodes] == $relation_route_stop_positions[$#relation_route_stop_positions] ) {
                #
                # fine, last stop position in the list is actually the last node of the way
                #
                ;
            } else {
                if ( scalar(@relation_route_highways) > 1 || isOneway($relation_route_highways[0],undef) ) {
                    #
                    # if we have more than one way or the single way is a oneway, and because we know: the ways are sorted and w/o gaps
                    #
                    push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.last_node_not_last_stop', printNodeTemplate($sorted_way_nodes[$#sorted_way_nodes],'name;ref'), printNodeTemplate($relation_route_stop_positions[$#relation_route_stop_positions],'name;ref')) );
                    $return_code++;
                }
            }
        } else {
            printf STDERR "No! Checking whether we can be relaxed: Route-Name: %s\n", $relation_ptr->{'tag'}->{'name'}      if ( $debug );
            my $relaxed_for =  $relaxed_begin_end_for || '';
            $relaxed_for    =~ s/;/,/g;
            $relaxed_for    =  ',' . $relaxed_for . ',';
            if ( $relaxed_for =~ m/,\Q$relation_ptr->{'route_type_value'}\E,/ ) {
                my $last_way_ID     = $relation_route_highways[$#relation_route_highways];
                my @last_way_nodes  = ();
                my $found_it        = 0;
                my $found_nodeid    = 0;
                my $node_name       = '';

                if ( $sorted_way_nodes[$#sorted_way_nodes] == ${$WAYS{$last_way_ID}->{'chain'}}[0] ) {
                    @last_way_nodes  = @{$WAYS{$last_way_ID}->{'chain'}};
                } else {
                    @last_way_nodes  = reverse @{$WAYS{$last_way_ID}->{'chain'}};
                }

                foreach my $nodeid ( @last_way_nodes ) {
                    if ( $debug ) { $node_name = ( $NODES{$nodeid} && $NODES{$nodeid}->{'tag'} && $NODES{$nodeid}->{'tag'}->{'name'}) ? $NODES{$nodeid}->{'tag'}->{'name'} : ''; }
                    printf STDERR "WAY{%s}->{'chain'}->%s name='%s'\n", $last_way_ID, $nodeid, $node_name   if ( $debug );
                    if ( isNodeInNodeArray($nodeid,@relation_route_stop_positions) ) {
                        #
                        # fine, an inner node, or the first of the last way is a stop position of this route
                        #
                        $found_it++;
                        printf STDERR "WAY{%s}->{'chain'}->%s - %d\n", $last_way_ID, $nodeid, $found_it   if ( $debug );
                        if ( $nodeid == $relation_route_stop_positions[$#relation_route_stop_positions] ) {
                            #
                            # fine the last node of the last way which is a stop position and is actually the last stop position
                            #
                            $found_it++;
                            printf STDERR "WAY{%s}->{'chain'}->%s - %d\n", $last_way_ID, $nodeid, $found_it   if ( $debug );
                        }
                        $found_nodeid = $nodeid;
                        last;
                    }
                }
                if ( $found_it == 1 ) {
                    printf STDERR "1: Number of ways: %s, found_nodeid = %s, first node of last way = %s\n", scalar(@relation_route_highways), $found_nodeid, $last_way_nodes[0]  if ( $debug );
                    if ( scalar(@relation_route_highways) > 1 && $found_nodeid == $last_way_nodes[$#last_way_nodes] ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.way_after_last_stop', printWayTemplate($last_way_ID,'name;ref')) );
                        $return_code++;
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.last_stop_not_last', printNodeTemplate($found_nodeid,'name;ref'), printNodeTemplate($relation_route_stop_positions[$#relation_route_stop_positions],'name;ref')) );
                        $return_code++;
                    }
                }
                elsif ( $found_it == 2 ) {
                    printf STDERR "2: Number of ways: %s, found_nodeid = %s, first node of last way = %s\n", scalar(@relation_route_highways), $found_nodeid, $last_way_nodes[0]  if ( $debug );
                    if ( scalar(@relation_route_highways) > 1 && $found_nodeid == $last_way_nodes[$#last_way_nodes] ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.way_after_last_stop', printWayTemplate($last_way_ID,'name;ref')) );
                        $return_code++;
                    }
                } else {
                    if ( $number_of_route_stop_positions > 0 ) {
                        push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.no_stop_on_last_way', printWayTemplate($last_way_ID,'name;ref')) );
                        $return_code++;
                    }
                }
            } else {
                if ( $number_of_route_stop_positions > 0 ) {
                    push( @{$relation_ptr->{'__issues__'}}, issue('ptv2.last_node_not_stop', printNodeTemplate($sorted_way_nodes[$#sorted_way_nodes],'name;ref')) );
                    $return_code++;
                }
            }
        }
    }
    #
    # WAYS      are either Platforms (which must have a 'role') or Ways (which may have a 'role' = 'hail_and_ride')
    #
    $role_mismatch_found = 0;
    %role_mismatch       = ();
    foreach my $highway_ref ( @{$relation_ptr->{'way'}} ) {
        if ( $highway_ref->{'role'} ) {
            if ( $highway_ref->{'role'} =~ m/^platform$/               ||
                 $highway_ref->{'role'} =~ m/^platform_entry_only$/    ||
                 $highway_ref->{'role'} =~ m/^platform_exit_only$/        ) {

                if ( $xml_has_ways ) {
                    if ( $platform_ways{$highway_ref->{'ref'}} ) {
                        #
                        # bus=yes, tram=yes or share_taxi=yes is not required on public_transport=platform
                        #
                        if ( $check_platform ) {
                            if (  $relation_ptr->{'route_type_value'} eq 'bus'                    ||
                                 ($relation_ptr->{'route_type_value'} eq 'coach' && $allow_coach) ||
                                  $relation_ptr->{'route_type_value'} eq 'tram'                   ||
                                  $relation_ptr->{'route_type_value'} eq 'share_taxi'                ) {
                                if ( $WAYS{$highway_ref->{'ref'}}->{'tag'}->{$relation_ptr->{'route_type_value'}}          &&
                                     $WAYS{$highway_ref->{'ref'}}->{'tag'}->{$relation_ptr->{'route_type_value'}} eq "yes"    ) {
                                    ; # fine
                                }
                                else {
                                    $help_string   = issue('ptv2.missing_yes_on_pt', $relation_ptr->{'route_type_value'}, 'platform');
                                    $role_mismatch{mkey($help_string)}->{$highway_ref->{'ref'}} = 1;
                                    $role_mismatch_found++;
                                }
                            }
                        }
                    } elsif ( $WAYS{$highway_ref->{'ref'}}->{'tag'}->{'public_transport'} ) {
                        $help_string   = issue('ptv2.role_pt_mismatch', $highway_ref->{'role'}, $WAYS{$highway_ref->{'ref'}}->{'tag'}->{'public_transport'});
                        $role_mismatch{mkey($help_string)}->{$highway_ref->{'ref'}} = 1;
                        $role_mismatch_found++;
                    } else {
                        my $with_lifecycle_prefix= '';
                        foreach my $lcp ( @lifecycle_prefixes ) {
                            if ( $WAYS{$highway_ref->{'ref'}}->{'tag'}->{$lcp.':public_transport'} ) {
                                $with_lifecycle_prefix = $lcp . ':public_transport';
                                last;
                            }
                        }
                        if ( $with_lifecycle_prefix) {
                            $help_string   = issue('ptv2.role_pt_unset_but_set', $highway_ref->{'role'}, $with_lifecycle_prefix);
                        } else {
                            $help_string   = issue('ptv2.role_pt_unset', $highway_ref->{'role'});
                        }
                        $role_mismatch{mkey($help_string)}->{$highway_ref->{'ref'}} = 1;
                        $role_mismatch_found++;
                    }
                }
            } elsif ( $highway_ref->{'role'}  =~ m/^hail_and_ride$/       &&
                      $relation_route_highways_hash{$highway_ref->{'ref'}}    ) {
                ; # fine, 'hail_and_ride' is allowed on non platform ways only
            } else {
                $help_string   = issue('ptv2.wrong_role', ctrl_escape($highway_ref->{'role'}));
                $role_mismatch{mkey($help_string)}->{$highway_ref->{'ref'}} = 1;
                $role_mismatch_found++;
            }
        } else {
            if ( $platform_ways{$highway_ref->{'ref'}} ) {
                # code for issue #161
                my $helpstring;
                if ( $WAYS{$highway_ref->{'ref'}}->{'tag'} && $WAYS{$highway_ref->{'ref'}}->{'tag'}->{'public_transport'} ) {
                    if ( $WAYS{$highway_ref->{'ref'}}->{'tag'}->{'public_transport'} eq 'stop_position' ) {
                        $helpstring    = issue('ptv2.empty_role_stop_way');
                    } elsif ( $WAYS{$highway_ref->{'ref'}}->{'tag'}->{'public_transport'} eq 'platform') {
                        $helpstring    = issue('ptv2.empty_role_platform');
                    } else {
                        $helpstring    = issue('ptv2.empty_role_unknown_pt', $WAYS{$highway_ref->{'ref'}}->{'tag'}->{'public_transport'});
                    }
                } else {
                    $helpstring    = issue('ptv2.empty_role_no_pt');
                }
                $role_mismatch{mkey($helpstring)}->{$highway_ref->{'ref'}} = 1;
                $role_mismatch_found++;
            }
        }
    }
    if ( $role_mismatch_found ) {
        foreach my $role ( sort ( keys ( %role_mismatch ) ) ) {
            @help_array     = sort(keys(%{$role_mismatch{$role}}));
            $num_of_errors  = scalar(@help_array);
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed(unkey($role), [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            }
            else {
                push( @{$relation_ptr->{'__issues__'}}, listed(unkey($role), [map { printWayTemplate($_,'name;ref'); } @help_array]) );
            }
        }
    }
    $return_code += $role_mismatch_found;

    #
    # RELATIONS     are Platforms, which must have a 'role'
    #
    $role_mismatch_found = 0;
    %role_mismatch       = ();
    foreach my $rel_ref ( @{$relation_ptr->{'relation'}} ) {
        if ( $rel_ref->{'role'} ){
            if ( $rel_ref->{'role'} =~ m/^platform$/               ||
                 $rel_ref->{'role'} =~ m/^platform_entry_only$/    ||
                 $rel_ref->{'role'} =~ m/^platform_exit_only$/        ) {

                if ( $number_of_platform_multipolygon_relations ) {
                    if ( $platform_multipolygon_relations{$rel_ref->{'ref'}} ) {
                        #
                        # bus=yes, tram=yes or share_taxi=yes is not required on public_transport=platform
                        #
                        if ( $check_platform ) {
                            if (  $relation_ptr->{'route_type_value'} eq 'bus'                    ||
                                 ($relation_ptr->{'route_type_value'} eq 'coach' && $allow_coach) ||
                                  $relation_ptr->{'route_type_value'} eq 'tram'                   ||
                                  $relation_ptr->{'route_type_value'} eq 'share_taxi'               ) {
                                if ( $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{$relation_ptr->{'route_type_value'}}          &&
                                     $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{$relation_ptr->{'route_type_value'}} eq "yes"    ) {
                                   ; # fine
                                }
                                else {
                                    $help_string   = issue('ptv2.missing_yes_on_pt', $relation_ptr->{'route_type_value'}, 'platform');
                                    $role_mismatch{mkey($help_string)}->{$rel_ref->{'ref'}} = 1;
                                    $role_mismatch_found++;
                                }
                            }
                        }
                    } elsif ( $RELATIONS{$rel_ref->{'ref'}}                                &&
                              $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{'public_transport'}    ) {
                        $help_string   = issue('ptv2.role_pt_mismatch', $rel_ref->{'role'}, $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{'public_transport'});
                        $role_mismatch{mkey($help_string)}->{$rel_ref->{'ref'}} = 1;
                        $role_mismatch_found++;
                    } else {
                        my $with_lifecycle_prefix= '';
                        foreach my $lcp ( @lifecycle_prefixes ) {
                            if ( $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{$lcp.':public_transport'} ) {
                                $with_lifecycle_prefix = $lcp . ':public_transport';
                                last;
                            }
                        }
                        if ( $with_lifecycle_prefix) {
                            $help_string   = issue('ptv2.role_pt_unset_but_set', $rel_ref->{'role'}, $with_lifecycle_prefix);
                        } else {
                            $help_string   = issue('ptv2.role_pt_unset', $rel_ref->{'role'});
                        }
                        $role_mismatch{mkey($help_string)}->{$rel_ref->{'ref'}} = 1;
                        $role_mismatch_found++;
                    }
                }
            } else {
                $help_string = issue('ptv2.wrong_role', ctrl_escape($rel_ref->{'role'}));
                $role_mismatch{mkey($help_string)}->{$rel_ref->{'ref'}} = 1;
                $role_mismatch_found++;
            }
        } else {
            # code for issue #161
            my $helpstring;
            if ( $RELATIONS{$rel_ref->{'ref'}}->{'tag'} && $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{'public_transport'} ) {
                if ( $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{'public_transport'} eq 'stop_position' ) {
                    $helpstring    = issue('ptv2.empty_role_stop_relation');
                } elsif ( $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{'public_transport'} eq 'platform') {
                    $helpstring    = issue('ptv2.empty_role_platform');
                } else {
                    $helpstring    = issue('ptv2.empty_role_unknown_pt', $RELATIONS{$rel_ref->{'ref'}}->{'tag'}->{'public_transport'});
                }
            } else {
                $helpstring    = issue('ptv2.empty_role_no_pt');
            }
            $role_mismatch{mkey($helpstring)}->{$rel_ref->{'ref'}} = 1;
            $role_mismatch_found++;
        }
    }
    if ( $role_mismatch_found ) {
        foreach my $role ( sort ( keys ( %role_mismatch ) ) ) {
            @help_array     = sort(keys(%{$role_mismatch{$role}}));
            $num_of_errors  = scalar(@help_array);
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed(unkey($role), [map { printRelationTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, listed(unkey($role), [map { printRelationTemplate($_,'name;ref'); } @help_array]) );
            }
        }
    }
    $return_code += $role_mismatch_found;

    if ( $check_sequence ) {
        #
        # check whether first stop/platform includes 'exit'  in 'role'
        # check whether last  stop/platform includes 'entry' in 'role'
        #
        my $first_stop_role     = '';
        my $first_platform_role = '';
        my $first_platform_type = '';
        my $first_platform_id   = '';
        my $first_way_id        = '';
        my $last_stop_role      = '';
        my $last_platform_role  = '';
        my $last_platform_type  = '';
        my $last_platform_id    = '';
        my $last_way_id         = '';
        my $number_of_stops     = 0;
        my $number_of_platforms = 0;
        my $number_of_ways      = 0;
        foreach my $item ( @{$relation_ptr->{'members'}} ) {
            if ( $item->{'role'} ) {
                if ( $item->{'role'} =~ m/^stop/ ) {
                    $first_stop_role = $item->{'role'}        unless ( $number_of_stops );
                    $last_stop_role  = $item->{'role'};
                    $number_of_stops++;
                } elsif ( $item->{'role'} =~ m/^platform/ ) {
                    unless ( $number_of_platforms ) {
                        $first_platform_role = $item->{'role'};
                        $first_platform_type = $item->{'type'};
                        $first_platform_id   = $item->{'ref'};
                    }
                    $last_platform_role  = $item->{'role'};
                    $last_platform_type  = $item->{'type'};
                    $last_platform_id    = $item->{'ref'};
                    $number_of_platforms++;
                }
            } else {
                # this is then assumed to be a highway/railway member, so do not consider nodes or relations here
                if ( $item->{'type'} eq 'way' ) {
                    $first_way_id   = $item->{'ref'}    unless ( $number_of_ways );
                    $last_way_id    = $item->{'ref'};
                    $number_of_ways++;
                }
            }
        }
        if ( $number_of_stops > 1 ) {
            if ( $first_stop_role eq 'stop_exit_only' ) {
                $help_string = issue('ptv2.wrong_role_first_stop', ctrl_escape($first_stop_role));
                push( @{$relation_ptr->{'__issues__'}}, $help_string );
                $return_code++;
            }
            if ( $last_stop_role eq 'stop_entry_only' ) {
                $help_string = issue('ptv2.wrong_role_last_stop', ctrl_escape($last_stop_role));
                push( @{$relation_ptr->{'__issues__'}}, $help_string );
                $return_code++;
            }
        }
        if ( $number_of_platforms > 1 ) {
            if ( $first_platform_role eq 'platform_exit_only' ) {
                $help_string = issue('ptv2.wrong_role_first_platform', ctrl_escape($first_platform_role));
                push( @{$relation_ptr->{'__issues__'}}, $help_string );
                $return_code++;
            }
            if ( $last_platform_role eq 'platform_entry_only' ) {
                $help_string = issue('ptv2.wrong_role_last_platform', ctrl_escape($last_platform_role));
                push( @{$relation_ptr->{'__issues__'}}, $help_string );
                $return_code++;
            }
            if ( $number_of_ways > 1 ) {
                #
                # will report false positive messages if there is only one way and the 1. platform is near the last node
                #
                my $max_allowed_distance = (defined($relation_ptr->{'route_type_value'}) && defined($max_allowed_platform_distances{$relation_ptr->{'route_type_value'}}))
                                           ? $max_allowed_platform_distances{$relation_ptr->{'route_type_value'}}
                                           : 30;
                my $distance = OSM::Geo::PlatformToNodeDistance( $first_platform_type, $first_platform_id, $sorted_way_nodes[0], $max_allowed_distance );
                if ( defined($distance) ) {
                    if ( $distance > $max_allowed_distance ) {
                        $help_string = issue('ptv2.start_not_near_first', printWayTemplate($first_way_id,'name;ref'), printXxxTemplate($first_platform_type,$first_platform_id,'name;ref'), $distance, OSM::Geo::ConvertMetersToFeet($distance));
                        push( @{$relation_ptr->{'__issues__'}}, $help_string );
                        $return_code++;
                    }
                } else {
                    my $insufficient = ( $first_platform_type eq 'node' ) ? 'data.insufficient_nodes' : ( $first_platform_type eq 'way' ) ? 'data.insufficient_ways' : 'data.insufficient_relations';
                    $help_string = issue($insufficient.'_dist', printXxxTemplate($first_platform_type,$first_platform_id,'name;ref'), printNodeTemplate($sorted_way_nodes[0],'name;ref'));
                    push( @{$relation_ptr->{'__issues__'}}, $help_string );
                    $return_code++;
                }
                $distance = OSM::Geo::PlatformToNodeDistance( $last_platform_type, $last_platform_id, $sorted_way_nodes[$#sorted_way_nodes], $max_allowed_distance );
                if ( defined($distance) ) {
                    if ( $distance > $max_allowed_distance ) {
                        $help_string = issue('ptv2.end_not_near_last', printWayTemplate($last_way_id,'name;ref'), printXxxTemplate($last_platform_type,$last_platform_id,'name;ref'), $distance, OSM::Geo::ConvertMetersToFeet($distance));
                        push( @{$relation_ptr->{'__issues__'}}, $help_string );
                        $return_code++;
                    }
                } else {
                    my $insufficient = ( $last_platform_type eq 'node' ) ? 'data.insufficient_nodes' : ( $last_platform_type eq 'way' ) ? 'data.insufficient_ways' : 'data.insufficient_relations';
                    $help_string = issue($insufficient.'_dist', printXxxTemplate($last_platform_type,$last_platform_id,'name;ref'), printNodeTemplate($sorted_way_nodes[$#sorted_way_nodes],'name;ref'));
                    push( @{$relation_ptr->{'__issues__'}}, $help_string );
                    $return_code++;
                }
            }
            if ( $first_platform_type eq $last_platform_type && $first_platform_id == $last_platform_id ) {
                if ( !defined($relation_ptr->{'tag'}->{'roundtrip'}) ) {
                    push( @{$relation_ptr->{'__notes__'}}, note('ptv2.roundtrip_unset_same_stops', 'yes', printRelationInjectData($relation_ptr->{'id'},('roundtrip=yes'))) );
                    $return_code++;
                } elsif ( $relation_ptr->{'tag'}->{'roundtrip'} ne 'yes' ) {
                    push( @{$relation_ptr->{'__issues__'}},  issue('ptv2.roundtrip_same_stops', text_msg($relation_ptr->{'tag'}->{'roundtrip'}), 'yes', printRelationInjectData($relation_ptr->{'id'},('roundtrip=yes'))) );
                    $return_code++;
                }
            } elsif ( $roundtrip_distance > 0 && defined($relation_ptr->{'tag'}->{'roundtrip'}) && $relation_ptr->{'tag'}->{'roundtrip'} eq 'yes' ) {
                my $distance = OSM::Geo::ObjectToObjectDistance( $first_platform_type, $first_platform_id, $last_platform_type, $last_platform_id );
                if ( $distance < 0 ) {
                    push( @{$relation_ptr->{'__issues__'}},  issue('ptv2.roundtrip_not_same_stops', 'yes', 'no', printRelationInjectData($relation_ptr->{'id'},('roundtrip=no'))) );
                    $return_code++;
                } elsif ( $distance > $roundtrip_distance ) {
                    push( @{$relation_ptr->{'__issues__'}},  issue('ptv2.roundtrip_yes_far', $roundtrip_distance, OSM::Geo::ConvertMetersToFeet($roundtrip_distance), $distance, OSM::Geo::ConvertMetersToFeet($distance), 'no', printRelationInjectData($relation_ptr->{'id'},('roundtrip=no'))) );
                    $return_code++;
                } else {
                    push( @{$relation_ptr->{'__notes__'}},  note('ptv2.roundtrip_yes_near', $roundtrip_distance, OSM::Geo::ConvertMetersToFeet($roundtrip_distance), $distance, OSM::Geo::ConvertMetersToFeet($distance)) );
                    $return_code++;
                }
            } else {
                if ( defined($relation_ptr->{'tag'}->{'roundtrip'}) && $relation_ptr->{'tag'}->{'roundtrip'} ne 'no' ) {
                    push( @{$relation_ptr->{'__issues__'}},  issue('ptv2.roundtrip_not_same_stops', text_msg($relation_ptr->{'tag'}->{'roundtrip'}), 'no', printRelationInjectData($relation_ptr->{'id'},('roundtrip=no'))) );
                    $return_code++;
                }
            }
        }
    }

    return $return_code;
}


#############################################################################################

sub FindRouteWays {
    my $relation_ptr            = shift;
    my $highway_ref             = undef;
    my @relations_route_ways    = ();

    foreach $highway_ref ( @{$relation_ptr->{'way'}} ) {
        push( @relations_route_ways, $highway_ref->{'ref'} )    unless ( $platform_ways{$highway_ref->{'ref'}} );
        #printf STDERR "FindRouteWays(): not pushed() %s\n", $highway_ref->{'ref'}   if ( $platform_ways{$highway_ref->{'ref'}} );
        #printf STDERR "FindRouteWays(): pushed() %s\n", $highway_ref->{'ref'}       unless ( $platform_ways{$highway_ref->{'ref'}} );
    }

    return @relations_route_ways;
}


#############################################################################################

sub FindRouteHighWays {
    my $relation_ptr                = shift;
    my $highway_ref                 = undef;
    my @relations_route_highways    = ();

    foreach $highway_ref ( @{$relation_ptr->{'route_highway'}} ) {
        push( @relations_route_highways, $highway_ref->{'ref'} )    unless ( $platform_ways{$highway_ref->{'ref'}} );
        #printf STDERR "FindRouteHighWays(): not pushed() %s\n", $highway_ref->{'ref'}   if ( $platform_ways{$highway_ref->{'ref'}} );
        #printf STDERR "FindRouteHighWays(): pushed() %s\n", $highway_ref->{'ref'}       unless ( $platform_ways{$highway_ref->{'ref'}} );
    }

    return @relations_route_highways;
}


#############################################################################################

sub FindRouteStopPositions {
    my $relation_ptr                    = shift;
    my $node_ref                        = undef;
    my @relations_route_stop_positions  = ();

    foreach $node_ref ( @{$relation_ptr->{'node'}} ) {
        if ( $stop_nodes{$node_ref->{'ref'}} ) {
            push( @relations_route_stop_positions, $node_ref->{'ref'} );
        } elsif ( $ptv1_compatibility ne "no" && $node_ref->{'role'} =~ m/^stop/ ) {
            my $compatible_tag = PTv2CompatibleNodeStopTag( $node_ref->{'ref'}, $relation_ptr->{'route_type_value'} );
            if ( $compatible_tag ) {
                push( @relations_route_stop_positions, $node_ref->{'ref'} );
            }
        }
    }

    return @relations_route_stop_positions;
}


#############################################################################################

sub FindRoutePlatformNodes {
    my $relation_ptr                    = shift;
    my $node_ref                        = undef;
    my @relations_route_platform_nodes  = ();

    foreach $node_ref ( @{$relation_ptr->{'node'}} ) {
        if ( $platform_nodes{$node_ref->{'ref'}} ) {
            push( @relations_route_platform_nodes, $node_ref->{'ref'} );
        } elsif ( $ptv1_compatibility ne "no"  ) {
            my $compatible_tag = PTv2CompatibleNodePlatformTag( $node_ref->{'ref'}, $relation_ptr->{'route_type_value'} );
            if ( $compatible_tag ) {
                push( @relations_route_platform_nodes, $node_ref->{'ref'} );
            }
        }
    }

    return @relations_route_platform_nodes;
}


#############################################################################################

sub FindRoutePlatformWays {
    my $relation_ptr                    = shift;
    my $way_ref                         = undef;
    my @relations_route_platform_ways   = ();

    foreach $way_ref ( @{$relation_ptr->{'way'}} ) {
        push( @relations_route_platform_ways, $way_ref->{'ref'} )    if ( $platform_ways{$way_ref->{'ref'}} );
    }

    return @relations_route_platform_ways;
}


#############################################################################################

sub FindRoutePlatformRelations {
    my $relation_ptr                        = shift;
    my $rel_ref                             = undef;
    my @relations_route_platform_relations  = ();

    foreach $rel_ref ( @{$relation_ptr->{'relation'}} ) {
        push( @relations_route_platform_relations, $rel_ref->{'ref'} )    if ( $platform_multipolygon_relations{$rel_ref->{'ref'}} );
    }

    return @relations_route_platform_relations;
}


#############################################################################################

sub SortRouteWayNodes {
    my $relation_ptr                = shift;
    my $relations_route_ways_ref    = shift;
    my @sorted_nodes                = ();
    my $connecting_node_id          = 0;
    my $previous_way_id             = undef;
    my $current_way_id              = undef;
    my $next_way_id                 = undef;
    my $node_id                     = undef;
    my @control_nodes               = ();
    my @stop_positions              = ();
    my $counter                     = 0;
    my $index                       = undef;
    my $way_index                   = 0;
    my $entry_node_id               = 0;
    my $route_type                  = undef;
    my $access_restriction          = undef;
    my $number_of_ways              = 0;
    my %expect_motorway_or_motorway_link_after = ();
    my $stop_in_roundabout          = 0;

    printf STDERR "SortRouteWayNodes() : processing Ways:\nWays: %s\n", jointext( ', ', @{$relations_route_ways_ref} )     if ( $debug );

    if ( $relation_ptr && $relations_route_ways_ref ) {

        @stop_positions = FindRouteStopPositions( $relation_ptr );

        $number_of_ways = scalar @{$relations_route_ways_ref} ;
        if ( $number_of_ways ) {
            # we have at least one way, so we start with one segment
            $relation_ptr->{'number_of_segments'} = 1;
        } else {
            # no ways, no segments
            $relation_ptr->{'number_of_segments'} = 0;
        }

        while ( ${$relations_route_ways_ref}[$way_index] ) {

            $previous_way_id = ($way_index > 0) ? ${$relations_route_ways_ref}[$way_index-1] : 0;
            $current_way_id  = ${$relations_route_ways_ref}[$way_index];
            $next_way_id     = ${$relations_route_ways_ref}[$way_index+1];
            $way_index++;

            push( @control_nodes, @{$WAYS{$current_way_id}->{'chain'}} );

            if ( $next_way_id ) {

                if ( $current_way_id == $next_way_id && isClosedWay($current_way_id) ) {
                    $relation_ptr->{'roundabout_follows_itself'}->{$current_way_id} = 1;
                }

                if ( $connecting_node_id ) {
                    #
                    printf STDERR "SortRouteWayNodes() : Connecting Node %d\n",$connecting_node_id       if ( $debug );
                    #
                    # continue this segment with the connecting node of the previously handled way
                    #
                    if ( isClosedWay($current_way_id) ) {
                        #
                        # no direct match, this current way is a closed way, roundabout or whatever, where first node is also last node
                        # check whether connecting node is a node of this, closed way
                        #
                        if ( ($index=IndexOfNodeInNodeArray($connecting_node_id,@{$WAYS{$current_way_id}->{'chain'}})) >= 0 ) {
                            printf STDERR "SortRouteWayNodes() : handle Nodes of closed Way %s with Index %d:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $index, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            my $i = 0;
                            $stop_in_roundabout = 0;
                            for ( $i = $index+1; $i <= $#{$WAYS{$current_way_id}->{'chain'}}; $i++ ) {
                                push( @sorted_nodes, ${$WAYS{$current_way_id}->{'chain'}}[$i] );
                                if ( isNodeInNodeArray(${$WAYS{$current_way_id}->{'chain'}}[$i],@stop_positions) ) {
                                    $stop_in_roundabout = 1;
                                    printf STDERR "SortRouteWayNodes() : this is bus ref : %s\n", $relation_ptr->{'tag'}{'ref'}     if ( $debug );
                                    printf STDERR "SortRouteWayNodes() : stop_position in roundabout %s = %s with Index %d:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}{'name'}, $i, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                }
                            }
                            for ( $i = 1; $i <= $index; $i++ ) {
                                push( @sorted_nodes, ${$WAYS{$current_way_id}->{'chain'}}[$i] );
                                if ( isNodeInNodeArray(${$WAYS{$current_way_id}->{'chain'}}[$i],@stop_positions) ) {
                                    $stop_in_roundabout = 1;
                                    printf STDERR "SortRouteWayNodes() : stop_position in roundabout %s with Index %d:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $i, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                }
                            }

                            #
                            # now that we entered the closed way, how and where (!) do we get out of it
                            # - if this current way is a turning circle, where the 'bus' turns and comes back, then entering_node is leaving_node and we're fine and next While-loop will find that out
                            # - if this current way is an entire roundabout and the 'bus' leaves it prematurely, then we have an issue, because some parts of the roundabout aren't used
                            #
                            if ( $sorted_nodes[$#sorted_nodes] == $WAYS{$next_way_id}->{'first_node'} ||
                                 $sorted_nodes[$#sorted_nodes] == $WAYS{$next_way_id}->{'last_node'}     ) {
                                #
                                # perfect: this is a turnig roundabout where the 'bus' leaves where it entered the closed way, no reason to complain
                                # error; roundabout is in member list but a way traverses the roundabout at this point
                                #
                                printf STDERR "SortRouteWayNodes() : handle turning roundabout %s at node %s for %s:\nNodes here : %s\nNodes there: %s\n",
                                                                    $WAYS{$current_way_id}->{'tag'}->{'name'},
                                                                    $sorted_nodes[$#sorted_nodes],
                                                                    $WAYS{$next_way_id}->{'tag'}->{'name'},
                                                                    jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} ),
                                                                    jointext( ', ', @{$WAYS{$next_way_id}->{'chain'}} )     if ( $debug );
                                if ( $previous_way_id && !isClosedWay($previous_way_id) ) {
                                    printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$previous_way_id}->{'tag'}->{'name'}, , $WAYS{$current_way_id}->{'tag'}->{'name'}    if ( $debug );
                                    if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$previous_way_id}->{'chain'}}, \@{$WAYS{$current_way_id}->{'chain'}} ) ) {
                                        $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                        $relation_ptr->{'traversed_roundabout'}->{$current_way_id}->{$previous_way_id} = 1;
                                        printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$previous_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                    }
                                }
                                if ( $next_way_id && !isClosedWay($next_way_id) ) {
                                    printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, , $WAYS{$current_way_id}->{'tag'}->{'name'}    if ( $debug );
                                    if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$next_way_id}->{'chain'}}, \@{$WAYS{$current_way_id}->{'chain'}} ) ) {
                                        $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                        $relation_ptr->{'traversed_roundabout'}->{$current_way_id}->{$next_way_id} = 1;
                                        printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                    }
                                }
                            } else {
                                printf STDERR "SortRouteWayNodes() : handle partially used roundabout %s at node %s for %s:\nNodes here : %s\nNodes there: %s\n",
                                                                    $WAYS{$current_way_id}->{'tag'}->{'name'},
                                                                    $sorted_nodes[$#sorted_nodes],
                                                                    $WAYS{$next_way_id}->{'tag'}->{'name'},
                                                                    jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} ),
                                                                    jointext( ', ', @{$WAYS{$next_way_id}->{'chain'}} )     if ( $debug );

                                $relation_ptr->{'roundabout_segments_at'}{$current_way_id}= 1;

                                if ( isNodeInNodeArray($WAYS{$next_way_id}->{'first_node'},@{$WAYS{$current_way_id}->{'chain'}}) ||
                                     isNodeInNodeArray($WAYS{$next_way_id}->{'last_node'}, @{$WAYS{$current_way_id}->{'chain'}})     ){
                                    #
                                    # there is a match with first or last node of next way and some node of this roundabout
                                    # so we're deleting superflous nodes from the top of sorted_nodes until we hit the connecting node
                                    #
                                    if ( $stop_in_roundabout ) {
                                        # copy the same roundabout a second time into the sorted_nodes
                                        printf STDERR "SortRouteWayNodes() : copy the same roundabout  %s = %s a second time into the sorted_nodes\n", $current_way_id, $WAYS{$current_way_id}->{'tag'}{'name'}     if ( $debug );
                                        for ( $i = $index+1; $i <= $#{$WAYS{$current_way_id}->{'chain'}}; $i++ ) {
                                            push( @sorted_nodes, ${$WAYS{$current_way_id}->{'chain'}}[$i] );
                                        }
                                        for ( $i = 1; $i <= $index; $i++ ) {
                                            push( @sorted_nodes, ${$WAYS{$current_way_id}->{'chain'}}[$i] );
                                        }
                                    }
                                    while ( $sorted_nodes[$#sorted_nodes] != $WAYS{$next_way_id}->{'first_node'} &&
                                            $sorted_nodes[$#sorted_nodes] != $WAYS{$next_way_id}->{'last_node'}     ) {
                                        printf STDERR "SortRouteWayNodes() : pop() Node %s from \@sorted_nodes\n", $sorted_nodes[$#sorted_nodes]     if ( $debug );
                                        pop( @sorted_nodes );
                                    }

                                    if ( $previous_way_id && !isClosedWay($previous_way_id) ) {
                                        printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$previous_way_id}->{'tag'}->{'name'}, , $WAYS{$current_way_id}->{'tag'}->{'name'}    if ( $debug );
                                        if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$previous_way_id}->{'chain'}}, \@{$WAYS{$current_way_id}->{'chain'}} ) ) {
                                            $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                            $relation_ptr->{'traversed_roundabout'}->{$current_way_id}->{$previous_way_id} = 1;
                                            printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$previous_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                        }
                                    }
                                    if ( $next_way_id && !isClosedWay($next_way_id) ) {
                                        printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, , $WAYS{$current_way_id}->{'tag'}->{'name'}    if ( $debug );
                                        if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$next_way_id}->{'chain'}}, \@{$WAYS{$current_way_id}->{'chain'}} ) ) {
                                            $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                            $relation_ptr->{'traversed_roundabout'}->{$current_way_id}->{$next_way_id} = 1;
                                            printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                        }
                                    }
                                } else {
                                    #
                                    # no way out, we do not have any connection between any node of this way and the next way
                                    #
                                    printf STDERR "SortRouteWayNodes() : no match between this closed Way %s and the next Way %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}      if ( $debug );
                                    push( @sorted_nodes, 0 );      # mark a gap in the sorted nodes
                                    $relation_ptr->{'number_of_segments'}++;
                                    push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                                    printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d at Way %s and the next Way %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}      if ( $debug );
                                }
                            }
                        } else {
                            printf STDERR "SortRouteWayNodes() : handle Nodes of first, closed, single Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                            push( @sorted_nodes, 0 );      # mark a gap in the sorted nodes
                            $relation_ptr->{'number_of_segments'}++;
                            push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                            printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d at first, closed, single Way %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        }
                    } elsif ( 0 != ($entry_node_id=isOneway($current_way_id,undef)) ) {
                        if ( $connecting_node_id == $entry_node_id ) {
                            #
                            # perfect, entering the oneway in the right or allowed direction
                            #
                            if ( $entry_node_id == $WAYS{$current_way_id}->{'first_node'} ) {
                                #
                                # perfect order for this way (oneway=yes, junction=roundabout): last node of former segment is first node of this way
                                #
                                printf STDERR "SortRouteWayNodes() : handle Nodes of oneway Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                pop( @sorted_nodes );     # don't add connecting node twice
                                push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                            } else {
                                #
                                # not so perfect (oneway=-1), but we can take the nodes of this way in reverse order
                                #
                                printf STDERR "SortRouteWayNodes() : handle Nodes of oneway Way %s:\nNodes: reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                pop( @sorted_nodes );     # don't add connecting node twice
                                push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                            }
                        } else {
                            if ( $connecting_node_id == $WAYS{$current_way_id}->{'last_node'}  ||
                                 $connecting_node_id == $WAYS{$current_way_id}->{'first_node'}    ) {
                                #
                                # oops! entering oneway in wrong direction, copying nodes assuming we are allowd to do so
                                #
                                if ( $entry_node_id == $WAYS{$current_way_id}->{'first_node'} ) {
                                    printf STDERR "SortRouteWayNodes() : entering oneway in wrong direction Way %s:\nNodes: %s, reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                    push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                                } else {
                                    # not so perfect (oneway=-1), but we can take the nodes of this way in direct order
                                    printf STDERR "SortRouteWayNodes() : entering oneway in wrong direction Way %s:\nNodes: %s, %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                    push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                                }
                                $relation_ptr->{'wrong_direction_oneways'}->{$current_way_id} = 1;
                            } else {
                                #
                                # no match, i.e. a gap between this (current) way and the way before
                                #
                                push( @sorted_nodes, 0 );      # mark a gap in the sorted nodes
                                if ( $entry_node_id == $WAYS{$current_way_id}->{'first_node'} ) {
                                    printf STDERR "SortRouteWayNodes() : mark a gap before oneway Way %s:\nNodes: %s, G, %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                    push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                                } else {
                                    # not so perfect (oneway=-1), but we can take the nodes of this way in revers order
                                    printf STDERR "SortRouteWayNodes() : mark a gap before oneway Way %s:\nNodes: %s, G, reverse(%)s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                    push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                                }
                                printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ at gap between this (current) way and the way before\n"     if ( $debug );
                                $relation_ptr->{'number_of_segments'}++;
                                push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                                $connecting_node_id = 0;
                            }
                        }
                    } elsif ( $connecting_node_id eq $WAYS{$current_way_id}->{'first_node'} ) {
                        #
                        # perfect order for this way: last node of former segment is first node of this way
                        #
                        printf STDERR "SortRouteWayNodes() : handle Nodes of Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        pop( @sorted_nodes );     # don't add connecting node twice
                        push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                    } elsif ( $connecting_node_id eq $WAYS{$current_way_id}->{'last_node'} ) {
                        #
                        # not so perfect, but we can take the nodes of this way in reverse order
                        #
                        printf STDERR "SortRouteWayNodes() : handle Nodes of Way %s:\nNodes: reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        pop( @sorted_nodes );     # don't add connecting node twice
                        push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                    } else {
                        #
                        # no match, i.e. a gap between this (current) way and the way before
                        #
                        printf STDERR "SortRouteWayNodes() : mark a gap before Way %s:\nNodes: %s, G, %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                        push( @sorted_nodes, 0 );      # mark a gap in the sorted nodes
                        push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                        $relation_ptr->{'number_of_segments'}++;
                        push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                        printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d before Way %s:\nNodes: %s, G, %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                        $connecting_node_id = 0;
                    }
                }
                if ( $connecting_node_id == 0 ) {
                    #
                    printf STDERR "SortRouteWayNodes() : Connecting Node 0\n"       if ( $debug );
                    #
                    # we're at the beginning of the first or a new segment
                    #
                    if ( isClosedWay($current_way_id) ) {
                        #
                        # no direct match, this current way is a closed way, roundabout or whatever, where first node is also last node
                        # find a node in this way which connects to the first or last node of the next way
                        #
                        if ( ($index=IndexOfNodeInNodeArray($WAYS{$next_way_id}->{'first_node'},@{$WAYS{$current_way_id}->{'chain'}})) >= 0 ||
                             ($index=IndexOfNodeInNodeArray($WAYS{$next_way_id}->{'last_node'}, @{$WAYS{$current_way_id}->{'chain'}})) >= 0    ) {
                            printf STDERR "SortRouteWayNodes() : handle Nodes of first, closed Way %s with Index %d:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $index, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            my $i = 0;
                            for ( $i = $index+1; $i <= $#{$WAYS{$current_way_id}->{'chain'}}; $i++ ) {
                                push( @sorted_nodes, ${$WAYS{$current_way_id}->{'chain'}}[$i] );
                            }
                            for ( $i = 1; $i <= $index; $i++ ) {
                                push( @sorted_nodes, ${$WAYS{$current_way_id}->{'chain'}}[$i] );
                            }
                            if ( $next_way_id && !isClosedWay($next_way_id) ) {
                                printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, , $WAYS{$current_way_id}->{'tag'}->{'name'}    if ( $debug );
                                if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$next_way_id}->{'chain'}}, \@{$WAYS{$current_way_id}->{'chain'}} ) ) {
                                    $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                    $relation_ptr->{'traversed_roundabout'}->{$current_way_id}->{$next_way_id} = 1;
                                    printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                }
                            }
                        } else {
                            printf STDERR "SortRouteWayNodes() : handle Nodes of first, closed, single Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                            push( @sorted_nodes, 0 );                   # mark a gap in the sorted nodes
                            $relation_ptr->{'number_of_segments'}++;
                            push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                            printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d at Nodes of first, closed, single Way %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );

                        }
                    } elsif ( 0 != ($entry_node_id=isOneway($current_way_id,undef)) ) {
                        if ( $entry_node_id == $WAYS{$current_way_id}->{'first_node'} ) {
                            #
                            # perfect order for this way (oneway=yes, junction=roundabout): start at first node of this way
                            #
                            printf STDERR "SortRouteWayNodes() : handle Nodes of first oneway Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                        } else {
                            #
                            # not so perfect (oneway=-1), but we can take the nodes of this way in reverse order
                            #
                            printf STDERR "SortRouteWayNodes() : handle Nodes of first oneway Way %s:\nNodes: reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                        }
                        if ( $next_way_id && !isClosedWay($next_way_id) ) {
                            printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, , $WAYS{$current_way_id}->{'tag'}->{'name'}    if ( $debug );
                            if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$next_way_id}->{'chain'}}, \@{$WAYS{$current_way_id}->{'chain'}} ) ) {
                                $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                $relation_ptr->{'traversed_roundabout'}->{$current_way_id}->{$next_way_id} = 1;
                                printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            }
                        }
                    } elsif ( isClosedWay($next_way_id) ) {
                        #
                        # no direct match, this current way shall connect to a closed way, roundabout or whatever, where first node is also last node
                        # check whether first or last node of this way is one of the nodes of the next, closed way, so that we have a connectting point
                        #
                        if ( ($index=IndexOfNodeInNodeArray($WAYS{$current_way_id}->{'last_node'},@{$WAYS{$next_way_id}->{'chain'}})) >= 0 ) {
                            #
                            # perfect match, last node of this way is a node of the next roundabout
                            #
                            printf STDERR "SortRouteWayNodes() : handle Nodes for last Node %s of first Way %s connecting to a closed Way %s with Index %d:\nNodes: %s\n", $WAYS{$current_way_id}->{'first_node'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, $index, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                            printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, , $WAYS{$next_way_id}->{'tag'}->{'name'}    if ( $debug );
                            if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$current_way_id}->{'chain'}}, \@{$WAYS{$next_way_id}->{'chain'}} ) ) {
                                $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                $relation_ptr->{'traversed_roundabout'}->{$next_way_id}->{$current_way_id} = 1;
                                printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            }
                        } elsif ( ($index=IndexOfNodeInNodeArray($WAYS{$current_way_id}->{'first_node'},@{$WAYS{$next_way_id}->{'chain'}})) >= 0 ) {
                            #
                            # not so perfect match, but first node of this way is a node of the next roundabout
                            # take nodes of this way in reverse order
                            #
                            printf STDERR "SortRouteWayNodes() : handle Nodes for first Node %s of first Way %s connecting to a closed Way %s with Index %s:\nNodes: reverse( %s )\n", $WAYS{$current_way_id}->{'first_node'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, $index, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                            printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, , $WAYS{$next_way_id}->{'tag'}->{'name'}    if ( $debug );
                            if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$current_way_id}->{'chain'}}, \@{$WAYS{$next_way_id}->{'chain'}} ) ) {
                                $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                $relation_ptr->{'traversed_roundabout'}->{$next_way_id}->{$current_way_id} = 1;
                                printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            }
                        } else {
                            #
                            # no match at all into next, closed way, i.e. a gap between this (current) way and the next, closed way
                            # take nodes of this way in normal order and mark a gap after that
                            #
                            printf STDERR "SortRouteWayNodes() : handle Nodes of single Way %s before a closed Way %s:\nNodes: %s, G\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                            push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                            push( @sorted_nodes, 0 );                   # mark a gap in the sorted nodes
                            $relation_ptr->{'number_of_segments'}++;
                            push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                            printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d at Nodes of single Way %s before a closed Way %s:\nNodes: %s, G\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, $WAYS{$next_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                        }
                    } elsif ( $WAYS{$current_way_id}->{'last_node'} == $WAYS{$next_way_id}->{'first_node'}   ||
                            $WAYS{$current_way_id}->{'last_node'} == $WAYS{$next_way_id}->{'last_node'}       ) {
                        #
                        # perfect order for this way: last node of this segment is first or last node of next segment
                        #
                        printf STDERR "SortRouteWayNodes() : handle Nodes of first Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                    } elsif ( $WAYS{$current_way_id}->{'first_node'} == $WAYS{$next_way_id}->{'first_node'}   ||
                            $WAYS{$current_way_id}->{'first_node'} == $WAYS{$next_way_id}->{'last_node'}       ) {
                        #
                        # not so perfect, but we can take the nodes of this way in reverse order
                        #
                        printf STDERR "SortRouteWayNodes() : handle Nodes of first Way %s:\nNodes: reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                    } else {
                        #
                        # no match at all, i.e. a gap between this (current) way and the next way
                        #
                        printf STDERR "SortRouteWayNodes() : handle Nodes of single Way %s:\nNodes: %s, G\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                        push( @sorted_nodes, 0 );                   # mark a gap in the sorted nodes
                        $relation_ptr->{'number_of_segments'}++;
                        push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                        printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d at Nodes of single Way %s:\nNodes: %s, G\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                    }
                }
            } else {
                #
                # handle last way
                #
                if ( $connecting_node_id ) {
                    #
                    printf STDERR "SortRouteWayNodes() : Connecting Node for last way %d\n", $connecting_node_id       if ( $debug );
                    #
                    # handle last way by appending its nodes in right order to the segment
                    #
                    if ( isClosedWay($current_way_id) ) {
                        #
                        # no direct match, this current way is a closed way, roundabout or whatever, where first node is also last node
                        # check whether connecting node is a node of this, closed way
                        #
                        if ( ($index=IndexOfNodeInNodeArray($connecting_node_id,@{$WAYS{$current_way_id}->{'chain'}})) >= 0 ) {
                            printf STDERR "SortRouteWayNodes() : handle Nodes of last, closed Way %s with Index %d:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $index, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            my $i = 0;
                            for ( $i = $index+1; $i <= $#{$WAYS{$current_way_id}->{'chain'}}; $i++ ) {
                                push( @sorted_nodes, ${$WAYS{$current_way_id}->{'chain'}}[$i] );
                            }
                            for ( $i = 1; $i <= $index; $i++ ) {
                                push( @sorted_nodes, ${$WAYS{$current_way_id}->{'chain'}}[$i] );
                            }
                            if ( $previous_way_id && !isClosedWay($previous_way_id) ) {
                                printf STDERR "SortRouteWayNodes() : call doesWayTraverseRoundAbout() for %s, %s, %s\n", $relation_ptr->{'tag'}->{'name'}, $WAYS{$previous_way_id}->{'tag'}->{'name'}, , $WAYS{$current_way_id}->{'tag'}->{'name'}    if ( $debug );
                                if ( doesWayTraverseRoundAbout( $relation_ptr, \@{$WAYS{$previous_way_id}->{'chain'}}, \@{$WAYS{$current_way_id}->{'chain'}} ) ) {
                                    $relation_ptr->{'number_of_traversed_roundabouts'}++;
                                    $relation_ptr->{'traversed_roundabout'}->{$current_way_id}->{$previous_way_id} = 1;
                                    printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_traversed_roundabouts'}++ = %d at first, closed, single Way being traversed by previous way (%s) %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$previous_way_id}->{'tag'}->{'name'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                }
                            }
                        } else {
                            push( @sorted_nodes, 0 );      # mark a gap in the sorted nodes
                            printf STDERR "SortRouteWayNodes() : handle Nodes of last, closed, isolated Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                            $relation_ptr->{'number_of_segments'}++;
                            push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                            printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d at Nodes of last, closed, isolated Way %s:\nNodes: %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        }
                    } elsif ( 0 != ($entry_node_id=isOneway($current_way_id,undef)) ) {
                        if ( $connecting_node_id == $entry_node_id ) {
                            #
                            # perfect, entering the oneway in the right or allowed direction
                            #
                            if ( $entry_node_id == $WAYS{$current_way_id}->{'first_node'} ) {
                                #
                                # perfect order for this way (oneway=yes, junction=roundabout): last node of former segment is first node of this way
                                #
                                printf STDERR "SortRouteWayNodes() : handle Nodes of oneway Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                pop( @sorted_nodes );     # don't add connecting node twice
                                push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                            } else {
                                #
                                # not so perfect (oneway=-1), but we can take the nodes of this way in reverse order
                                #
                                printf STDERR "SortRouteWayNodes() : handle Nodes of oneway Way %s:\nNodes: reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                                pop( @sorted_nodes );     # don't add connecting node twice
                                push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                            }
                        } else{
                            if ( $connecting_node_id == $WAYS{$current_way_id}->{'last_node'}  ||
                                 $connecting_node_id == $WAYS{$current_way_id}->{'first_node'}    ) {
                                #
                                # oops! entering oneway in wrong direction, copying nodes assuming we are allowd to do so
                                #
                                if ( $entry_node_id == $WAYS{$current_way_id}->{'first_node'} ) {
                                    printf STDERR "SortRouteWayNodes() : entering oneway in wrong direction Way %s:\nNodes: %s, reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                    push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                                } else {
                                    # not so perfect (oneway=-1), but we can take the nodes of this way in direct order
                                    printf STDERR "SortRouteWayNodes() : entering oneway in wrong direction Way %s:\nNodes: %s, %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                    push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                                }
                                $relation_ptr->{'wrong_direction_oneways'}->{$current_way_id} = 1;
                            } else {
                                #
                                # no match, i.e. a gap between this (current) way and the way before, we will follow the oneway in the intended direction
                                #
                                push( @sorted_nodes, 0 );      # mark a gap in the sorted nodes
                                if ( $entry_node_id == $WAYS{$current_way_id}->{'first_node'} ) {
                                    printf STDERR "SortRouteWayNodes() : mark a gap before oneway Way %s:\nNodes: %s, G, %s, G\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                    push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                                } else {
                                    # not so perfect (oneway=-1), but we can take the nodes of this way in reverse order
                                    printf STDERR "SortRouteWayNodes() : mark a gap before oneway Way %s:\nNodes: %s, G, reverse( %s ), G\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                    push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                                }
                                $relation_ptr->{'number_of_segments'}++;
                                push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                                printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d at gap between this (current) way and the way before, we will follow the oneway in the intended direction\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )    if ( $debug );
                                $connecting_node_id = 0;
                            }
                        }
                    } elsif ( $connecting_node_id eq $WAYS{$current_way_id}->{'first_node'} ) {
                        printf STDERR "SortRouteWayNodes() : handle Nodes of last, connected Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        pop( @sorted_nodes );     # don't add connecting node twice
                        push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                    } elsif ( $connecting_node_id eq $WAYS{$current_way_id}->{'last_node'} ) {
                        printf STDERR "SortRouteWayNodes() : handle Nodes of last, connected Way %s:\nNodes: reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        pop( @sorted_nodes );     # don't add connecting node twice
                        push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                    } else {
                        printf STDERR "SortRouteWayNodes() : last, isolated Way %s and Node %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id     if ( $debug );
                        push( @sorted_nodes, 0 );      # mark a gap in the sorted nodes
                        push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                        $relation_ptr->{'number_of_segments'}++;
                        push( @{$relation_ptr->{'gap_at_way'}}, $current_way_id );
                        printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'}++ = %d last, isolated Way %s and Node %s\n", $relation_ptr->{'number_of_segments'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, $connecting_node_id     if ( $debug );
                    }
                } else {
                    #
                    printf STDERR "SortRouteWayNodes() : Connecting Node for last way is ZERO\n"                if ( $debug );
                    #
                    # seems that that there was only one way at all or the last segment consists of only one way
                    #
                    if ( 0 != ($entry_node_id=isOneway($current_way_id,undef)) ) {
                        if ( $entry_node_id == $WAYS{$current_way_id}->{'first_node'} ) {
                            #
                            # perfect order for this way (oneway=yes, junction=roundabout): we can take the nodes of this way in this order
                            #
                            printf STDERR "SortRouteWayNodes() : handle Nodes of last, isolated, single oneway Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            pop( @sorted_nodes );     # don't add connecting node twice
                            push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                        } else {
                            #
                            # not so perfect (oneway=-1), but we can take the nodes of this way in reverse order
                            #
                            printf STDERR "SortRouteWayNodes() : handle Nodes of last, isolated, single oneway Way %s:\nNodes: reverse( %s )\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                            pop( @sorted_nodes );     # don't add connecting node twice
                            push( @sorted_nodes, reverse(@{$WAYS{$current_way_id}->{'chain'}}) );
                        }
                    } else {
                        printf STDERR "SortRouteWayNodes() : handle Nodes of last, isolated Way %s:\nNodes: %s\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, jointext( ', ', @{$WAYS{$current_way_id}->{'chain'}} )     if ( $debug );
                        push( @sorted_nodes, @{$WAYS{$current_way_id}->{'chain'}} );
                    }
                    $relation_ptr->{'number_of_segments'}++ unless ( $number_of_ways == 1 );  # a single way cannot have 2 segments
                    printf STDERR "SortRouteWayNodes() : relation_ptr->{'number_of_segments'} = %d at handle Nodes of last, isolated Way\n", $relation_ptr->{'number_of_segments'}    if ( $debug );
                }
            }

            $connecting_node_id = $sorted_nodes[$#sorted_nodes];

            if ( $current_way_id && $WAYS{$current_way_id} && $WAYS{$current_way_id}->{'tag'} ) {
                #
                # check whether we entered a motorway_link and did not enter motorway before entering another type of way
                #
                if ( $WAYS{$current_way_id}->{'tag'}->{'highway'} &&
                     $next_way_id                                 &&
                     $WAYS{$next_way_id}                          &&
                     $WAYS{$next_way_id}->{'tag'}                 &&
                     $WAYS{$next_way_id}->{'tag'}->{'highway'}        ) {
                    if ( $WAYS{$next_way_id}->{'tag'}->{'highway'} eq 'motorway_link' ) {
                        #
                        # next way is a motorway_link - be carefull
                        #
                        if ( $WAYS{$current_way_id}->{'tag'}->{'highway'} eq 'motorway' ||
                            $WAYS{$current_way_id}->{'tag'}->{'highway'} eq 'trunk'       ) {
                            #
                            # current way is motorway or trunk and next way is motorway_link - everthings is fine, no problem
                            #
                            %expect_motorway_or_motorway_link_after = ();
                        } elsif ( $WAYS{$current_way_id}->{'tag'}->{'highway'} eq 'motorway_link' ) {
                            #
                            # current way is motorway_link and next way is motorway_link
                            #
                            if ( scalar ( keys ( %expect_motorway_or_motorway_link_after ) ) ) {
                                #
                                # a problem only if it has been a problem already
                                #
                                $expect_motorway_or_motorway_link_after{$next_way_id} = 1;
                            }
                        } else {
                            #
                            # current way is anything except motorway/motorway-link and next way is motorway_link - be carefull, start watching this
                            #
                            $expect_motorway_or_motorway_link_after{$next_way_id} = 1;
                        }
                    } elsif ( $WAYS{$next_way_id}->{'tag'}->{'highway'} eq 'motorway' ||
                              $WAYS{$next_way_id}->{'tag'}->{'highway'} eq 'trunk'       ) {
                        if ( $WAYS{$current_way_id}->{'tag'}->{'highway'} eq 'motorway_link' ) {
                            #
                            # current way is motorway_link and next way is motorway or trunk - everthings is fine, no problem
                            #
                            %expect_motorway_or_motorway_link_after = ();
                        }
                    }
                }
                if ( !exists($WAYS{$current_way_id}->{'has_forward_backward_access_keys'}) ) {
                    #
                    # *:forward and *:backward in access keys has not yet been evaluated for this way
                    #
                    my $found = 0;
                    my $forward_or_backward = undef;
                    foreach my $key ( keys ( %{$WAYS{$current_way_id}->{'tag'}}) ) {
                        if ( $key =~ m/:(forward|backward)/ ) {
                            $forward_or_backward = $1;
                            if ( $key =~ m/^(access|motor_vehicle|motorcar|psv|bus|vehicle|share_taxi|trolleybus):/ &&
                                 $key !~ m/:lanes/                                               ) {
                                $WAYS{$current_way_id}->{'forward_backward_access_keys'}->{$forward_or_backward}->{$key} = $WAYS{$current_way_id}->{'tag'}->{$key};
                                $found++;
                            }
                        }
                    }
                    $WAYS{$current_way_id}->{'has_forward_backward_access_keys'} = $found;

                }
                if ( $connecting_node_id && $WAYS{$current_way_id}->{'has_forward_backward_access_keys'} > 0 ) {
                    #
                    # *:forward and *:backward in access keys has been evaluated for this way and is either 0 (none) or > 0
                    #
                    my $used_in_xxx_direction = 'unknown';
                    foreach my $forward_or_backward ( keys ( %{$WAYS{$current_way_id}->{'forward_backward_access_keys'}} ) ) {
                        foreach my $key ( keys ( %{$WAYS{$current_way_id}->{'forward_backward_access_keys'}->{$forward_or_backward}} ) ) {
                            printf STDERR "WAY %s: has %s key '%s' = '%s'\n", $WAYS{$current_way_id}->{'tag'}->{'name'}, $forward_or_backward, $key, $WAYS{$current_way_id}->{'forward_backward_access_keys'}->{$forward_or_backward}->{$key}   if ( $debug );
                            #
                            # mark this way in relation as being used in backward and/or forward direction
                            # based on $connecting_node_id (last node of the trip so far) being first (then backward) or last (then forward) node of way
                            #
                            if ( $connecting_node_id == $WAYS{$current_way_id}->{'chain'}[0] ) {
                                $used_in_xxx_direction = 'backward';
                            } elsif ( $connecting_node_id == $WAYS{$current_way_id}->{'chain'}[$#{$WAYS{$current_way_id}->{'chain'}}] ) {
                                $used_in_xxx_direction = 'forward';
                            } else {
                                $used_in_xxx_direction = 'unknown';
                            }
                            printf STDERR "PTv2 route %s uses way %s in '%s' direction\n", $relation_ptr->{'id'}, $WAYS{$current_way_id}->{'tag'}->{'name'}, $used_in_xxx_direction   if ( $debug );
                            $relation_ptr->{'ways_used_with_relevant_forward_backward_tags'}->{$current_way_id}->{$used_in_xxx_direction} = 1;
                        }
                    }
                }
            }
        }

        foreach my $k ( keys ( %expect_motorway_or_motorway_link_after ) ) {
            $relation_ptr->{'expect_motorway_after'}->{$k} = 1;
        }

        if ( $debug ) {
            foreach $node_id ( @control_nodes ) {
                $counter = isNodeInNodeArray( $node_id, @sorted_nodes );
                printf STDERR "SortRouteWayNodes() : Node %s has been considered %d times\n", $node_id, $counter   if ( $counter != 1 );
            }

            printf STDERR "SortRouteWayNodes() : route %s has %d segments\n", $relation_ptr->{'id'}, $relation_ptr->{'number_of_segments'};
            printf STDERR "SortRouteWayNodes() : returning Nodes:\nNodes: %s\n", jointext( ', ', @sorted_nodes );
            printf STDERR "%s\n", jointext( '', map { $_ ? '_' : 'G' } @sorted_nodes );

            foreach my $way_id ( keys ( %{$relation_ptr->{'ways_used_with_relevant_forward_backward_tags'}} ) ) {
                foreach my $used_in_xxx_direction ( keys ( %{$relation_ptr->{'ways_used_with_relevant_forward_backward_tags'}->{$way_id}} ) ) {
                    foreach my $forward_or_backward ( keys ( %{$WAYS{$way_id}->{'forward_backward_access_keys'}} ) ) {
                        foreach my $key ( keys ( %{$WAYS{$way_id}->{'forward_backward_access_keys'}->{$forward_or_backward}} ) ) {
                            printf STDERR "PTv2 route %s has %d segments and uses way %s in '%s' direction. Way has keys '%s' = '%s'\n", $relation_ptr->{'id'}, $relation_ptr->{'number_of_segments'}, $way_id, $used_in_xxx_direction, $key, $WAYS{$way_id}->{'forward_backward_access_keys'}->{$forward_or_backward}->{$key};     #   if ( $debug );
                        }
                    }
                }
            }

        }

        if ( $relation_ptr->{'number_of_segments'} != 1 && exists($relation_ptr->{'ways_used_with_relevant_forward_backward_tags'}) ) {
            # we cannot make statements on: which way is used in which direction
            delete($relation_ptr->{'ways_used_with_relevant_forward_backward_tags'});
        }
    }

    return @sorted_nodes;
}


#############################################################################################

sub isNodeInNodeArray {
    my $node_id         = shift;
    my @node_array      = @_;

    my $node_of_way     = undef;
    my $return_code     = 0;

    if ( $node_id && @node_array ) {
        foreach $node_of_way ( @node_array ) {
            if ( $node_of_way eq $node_id ) {
                $return_code++;
                printf STDERR "... match found for Node-ID %d\n", $node_id       if ( $debug );
            }
        }
    }
    printf STDERR "isNodeInNodeArray() returns %d for node-ID %d\n", $return_code, $node_id       if ( $debug );
    return $return_code;
}


#############################################################################################

sub IndexOfNodeInNodeArray {
    my $node_id         = shift;
    my @node_array      = @_;

    my $index           = undef;

    if ( $node_id && @node_array ) {
        for ( $index = 0; $index <= $#node_array; $index++ ) {
            if ( $node_array[$index] == $node_id ) {
                printf STDERR "IndexOfNodeInNodeArray() : ... match found for Node-ID %s at index %d\n", $node_id, $index       if ( $debug );
                return $index;
            }
        }
    }
    printf STDERR "IndexOfNodeInNodeArray() : ... no match found for Node-ID %s\n", $node_id       if ( $debug );
    return -1;
}


#############################################################################################

sub isFirstNodeInNodeArray {
    my $node_id         = shift;
    my @node_array      = @_;

    if ( $node_id && @node_array ) {
        if ( $node_array[0] == $node_id    ) {
            printf STDERR "... match found for Node-ID %d, $node_id\n"       if ( $debug );
            return 1;
        }
    }
    printf STDERR "isFirstNodeInNodeArray() returns 0 for node-ID %d\n", $node_id       if ( $debug );
    return 0;
}


#############################################################################################

sub isLastNodeInNodeArray {
    my $node_id         = shift;
    my @node_array      = @_;

    if ( $node_id && @node_array ) {
        if ( $node_array[$#node_array] == $node_id    ) {
            printf STDERR "... match found for Node-ID %d, $node_id\n"       if ( $debug );
            return 1;
        }
    }
    printf STDERR "isLastNodeInNodeArray() returns 0 for node-ID %d\n", $node_id       if ( $debug );
    return 0;
}


#############################################################################################

sub PTv2CompatibleNodeStopTag {
    my $node_id         = shift;
    my $vehicle_type    = shift;
    my $ret_val         = '';

    if ( $NODES{$node_id}->{'member_of_way'} ) {
        # this node is a member of a way,  don't care at the moment which type
        if ( !defined($vehicle_type)                    ||
              $vehicle_type eq 'bus'                    ||
             ($vehicle_type eq 'coach' && $allow_coach) ||
              $vehicle_type eq 'share_taxi'             ||
              $vehicle_type eq 'trolleybus'                ) {
            if ( $NODES{$node_id}->{'tag'}->{'highway'} ) {
                if ( $NODES{$node_id}->{'tag'}->{'highway'} eq 'bus_stop' ) {
                     $ret_val = "'highway' = " . $NODES{$node_id}->{'tag'}->{'highway'} . "'";
                }
            }
        }
    }else {
        ; # PTv2 compatible stop_position must be member of a way, higway=bus_stop can be placed next to a way though
    }

    return $ret_val;
}


#############################################################################################

sub PTv2CompatibleNodePlatformTag {
    my $node_id         = shift;
    my $vehicle_type    = shift;
    my $ret_val         = '';

    if ( $NODES{$node_id}->{'member_of_way'} ) {
        # this node is a member of a way,  yet don't know which type
        if ( !defined($vehicle_type)                    ||
              $vehicle_type eq 'bus'                    ||
             ($vehicle_type eq 'coach' && $allow_coach) ||
              $vehicle_type eq 'share_taxi'             ||
              $vehicle_type eq 'trolleybus'                ) {
            if ( $NODES{$node_id}->{'tag'}->{'highway'} ) {
                if ( $NODES{$node_id}->{'tag'}->{'highway'} eq 'bus_stop' || $NODES{$node_id}->{'tag'}->{'highway'} eq 'platform' ) {
                    foreach my $way_id ( keys (  %{$NODES{$node_id}->{'member_of_way'}} ) ) {
                        if ( $WAYS{$way_id}->{'tag'} ) {
                            if ( ($WAYS{$way_id}->{'tag'}->{'highway'}          && $WAYS{$way_id}->{'tag'}->{'highway'}          eq 'platform') ||
                                 ($WAYS{$way_id}->{'tag'}->{'public_transport'} && $WAYS{$way_id}->{'tag'}->{'public_transport'} eq 'platform')    ) {
                                     $ret_val = "'highway' = " . $NODES{$node_id}->{'tag'}->{'highway'} . "'";
                            }
                        }
                    }
                }
            }
        }
    } else {
        # this node is a solitary node
        if ( !defined($vehicle_type)                    ||
              $vehicle_type eq 'bus'                    ||
             ($vehicle_type eq 'coach' && $allow_coach) ||
              $vehicle_type eq 'share_taxi'             ||
              $vehicle_type eq 'trolleybus'                ) {
            if ( $NODES{$node_id}->{'tag'} && $NODES{$node_id}->{'tag'}->{'highway'} ) {
                if ( $NODES{$node_id}->{'tag'}->{'highway'} eq 'bus_stop' || $NODES{$node_id}->{'tag'}->{'highway'} eq 'platform' ) {
                    $ret_val = "'highway' = " . $NODES{$node_id}->{'tag'}->{'highway'} . "'";
                }
            }
        }
    }

    return $ret_val;
}


#############################################################################################

sub isOneway {
    my $way_id          = shift;
    my $vehicle_type    = shift;        # optional !

    my $entry_node_id   = 0;

    if ( $way_id && $WAYS{$way_id} ) {
        if ( $vehicle_type ) {
            ; # todo
        } else {
            if ( ($WAYS{$way_id}->{'tag'}->{'oneway:bus'}   && $WAYS{$way_id}->{'tag'}->{'oneway:bus'}   eq 'no')            ||
                 ($WAYS{$way_id}->{'tag'}->{'oneway:psv'}   && $WAYS{$way_id}->{'tag'}->{'oneway:psv'}   eq 'no')            ||
                 ($WAYS{$way_id}->{'tag'}->{'busway'}       && $WAYS{$way_id}->{'tag'}->{'busway'}       eq 'opposite_lane') ||
                 ($WAYS{$way_id}->{'tag'}->{'busway:left'}  && $WAYS{$way_id}->{'tag'}->{'busway:left'}  eq 'opposite_lane') ||
                 ($WAYS{$way_id}->{'tag'}->{'busway:right'} && $WAYS{$way_id}->{'tag'}->{'busway:right'} eq 'opposite_lane')    ) {
                # bus may enter the road in either direction, return 0: don't care about entry point
                printf STDERR "isOneway() : no for bus/psv/busway*=opposite_lane for Way %d\n", $way_id       if ( $debug );
                return 0;
            } elsif ( $WAYS{$way_id}->{'tag'}->{'oneway'} && $WAYS{$way_id}->{'tag'}->{'oneway'} eq 'yes' ) {
                $entry_node_id = $WAYS{$way_id}->{'first_node'};
                printf STDERR "isOneway() : yes for all for Way %d, entry at first Node %d\n", $way_id, $entry_node_id       if ( $debug );
                return $entry_node_id;
            } elsif ( $WAYS{$way_id}->{'tag'}->{'oneway'} && $WAYS{$way_id}->{'tag'}->{'oneway'} eq '-1'  ) {
                $entry_node_id = $WAYS{$way_id}->{'last_node'};
                printf STDERR "isOneway() : yes for all for Way %d, entry at last Node %d\n", $way_id, $entry_node_id       if ( $debug );
                return $entry_node_id;
            } elsif ( $WAYS{$way_id}->{'tag'}->{'junction'} && $WAYS{$way_id}->{'tag'}->{'junction'} eq 'roundabout' ) {
                $entry_node_id = $WAYS{$way_id}->{'first_node'};
                printf STDERR "isOneway() : yes for all for Way %d, entry at first Node %d\n", $way_id, $entry_node_id       if ( $debug );
                return $entry_node_id;
            }
        }
    }
    printf STDERR "isOneway() : no for all for Way %d\n", $way_id       if ( $debug );
    return 0;
}


#############################################################################################

sub isClosedWay {
    my $way_id  = shift;

    if ( $way_id && $WAYS{$way_id} ) {
        if ( $WAYS{$way_id}->{'first_node'} && $WAYS{$way_id}->{'last_node'} ) {
            if ( $WAYS{$way_id}->{'first_node'} == $WAYS{$way_id}->{'last_node'} ) {
                printf STDERR "isClosedWay() : yes for Way %d\n", $way_id       if ( $debug );
                return 1;
            }
        } else {
            printf STDERR "%s WAYS{%s}->{'first_node'} is undefined\n", get_time(), $way_id     if ( !$WAYS{$way_id}->{'first_node'} );
            printf STDERR "%s WAYS{%s}->{'last_node'}  is undefined\n", get_time(), $way_id     if ( !$WAYS{$way_id}->{'last_node'}  );
        }
    }
    printf STDERR "isClosedWay() : no for Way %d\n", $way_id       if ( $debug );
    return 0;
}


#############################################################################################

sub isNodeArrayClosedWay {
    my @node_array = @_;

    if ( @node_array ) {
        if ( $node_array[0] == $node_array[$#node_array] ) {
            printf STDERR "isNodeArrayClosedWay() : yes\n"       if ( $debug );
            return 1;
        }
    }
    printf STDERR "isNodeArrayClosedWay() : no\n"       if ( $debug );
    return 0;
}


#############################################################################################
#
# check whether the way before or the way after the roundabout has some point(s) inside (geometry) the roundabout
#
# Prerequisites
# - it is a closed way
# - the way before/after is connected to the roundabout
# - so, at least the connecting node of the way is on the roundabout (== geometry: inside)
# - if there is a second one, then this is inside or on the roundabout
#
#############################################################################################

sub doesWayTraverseRoundAbout {
    my $relation_ptr           = shift || undef;
    my $ref_way                = shift || undef;
    my $ref_roundabout         = shift || undef;

    if ( $relation_ptr && $ref_way && $ref_roundabout ) {
        my $count_way_nodes        = scalar( @{$ref_way} );
        my $count_roundabout_nodes = scalar( @{$ref_roundabout} );
        if ( $count_way_nodes > 1 && $count_roundabout_nodes > 2 ) {
            if ( $ref_roundabout->[0] && $ref_roundabout->[$count_roundabout_nodes-1] &&
                 $ref_roundabout->[0] == $ref_roundabout->[$count_roundabout_nodes-1]    ) {
                my @way_polygon        = ();
                my @roundabout_polygon = ();
                my @common_nodes       = ();

                for ( my $i = 0; $i < $count_way_nodes; $i++ ) {
                    if ( $ref_way->[$i] && $NODES{$ref_way->[$i]} ) {
                        if ( isNodeInNodeArray($ref_way->[$i],@{$ref_roundabout}) ) {
                            push( @common_nodes, $ref_way->[$i] );
                        } else {
                            # the other nodes are outside or inside the roundabout
                            if ( exists($NODES{$ref_way->[$i]}) && exists($NODES{$ref_way->[$i]}->{'lat'}) && exists($NODES{$ref_way->[$i]}->{'lon'}) && $NODES{$ref_way->[$i]}->{'lat'} && $NODES{$ref_way->[$i]}->{'lon'} ) {
                                push( @way_polygon, [$NODES{$ref_way->[$i]}->{'lat'},$NODES{$ref_way->[$i]}->{'lon'}] );
                            } else {
                                printf STDERR "doesWayTraverseRoundAbout() relation: 'id' = %s, way_poly has unknwon values \$NODES{%s}->{'lat'} == %s, \$NODES{%s}->{'lon'} == %s\n", $relation_ptr->{'id'}, $ref_way->[$i], exists($NODES{$ref_way->[$i]}->{'lat'})?$NODES{$ref_way->[$i]}->{'lat'}:'?', $ref_way->[$i], exists($NODES{$ref_way->[$i]}->{'lon'})?$NODES{$ref_way->[$i]}->{'lon'}:'?';
                                printf STDERR "\$RELATIONS{%s} = %s", $relation_ptr->{'id'}, Data::Dumper::Dumper($RELATIONS{$relation_ptr->{'id'}});
                                printf STDERR "\$NODES{%s} = %s", $ref_way->[$i], Data::Dumper::Dumper($NODES{$ref_way->[$i]});
                            }
                        }
                    }
                }
                for ( my $i = 0; $i < $count_roundabout_nodes; $i++ ) {
                    if ( $ref_roundabout->[$i] && $NODES{$ref_roundabout->[$i]} ) {
                        if ( exists($NODES{$ref_roundabout->[$i]}) && exists($NODES{$ref_roundabout->[$i]}->{'lat'}) && exists($NODES{$ref_roundabout->[$i]}->{'lon'}) && $NODES{$ref_roundabout->[$i]}->{'lat'} && $NODES{$ref_roundabout->[$i]}->{'lon'} ) {
                            push( @roundabout_polygon, [$NODES{$ref_roundabout->[$i]}->{'lat'},$NODES{$ref_roundabout->[$i]}->{'lon'}] );
                        } else {
                            printf STDERR "doesWayTraverseRoundAbout() relation: 'id' = %s, roundabout_polygon has unknwon values \$NODES{%s}->{'lat'} == %s, \$NODES{%s}->{'lon'} == %s\n", $relation_ptr->{'id'}, $ref_roundabout->[$i], exists($NODES{$ref_roundabout->[$i]}->{'lat'})?$NODES{$ref_roundabout->[$i]}->{'lat'}:'?', $ref_roundabout->[$i], exists($NODES{$ref_roundabout->[$i]}->{'lon'})?$NODES{$ref_roundabout->[$i]}->{'lon'}:'?';
                                printf STDERR "\$RELATIONS{%s} = %s", $relation_ptr->{'id'}, Data::Dumper::Dumper($RELATIONS{$relation_ptr->{'id'}});
                                printf STDERR "\$NODES{%s} = %s", $ref_way->[$i], Data::Dumper::Dumper($NODES{$ref_way->[$i]});
                        }
                    }
                }

                my $count_common_nodes          = scalar( @common_nodes );
                my $number_of_way_points        = scalar( @way_polygon );
                my $number_of_roundabout_points = scalar( @roundabout_polygon );

                if ( $number_of_way_points && $number_of_roundabout_points ) {
                    my $nodes_inside = OSM::Geo::NumberOfPointsInsidePolygon( \@way_polygon, \@roundabout_polygon );

                    if ( $nodes_inside == 0 ) {
                        # handle secant of circle with no node inside the polygon and at least one node outside
                        # handle loop outside the roundabout
                        if ( $count_common_nodes > 1 && $count_way_nodes > 2 ) {
                            my $index1 = -1;
                            my $index2 = -1;
                            printf STDERR "doesWayTraverseRoundAbout() : secant or outer loop?\n"       if ( $debug );
                            for ( my $i = 0; $i < $count_common_nodes -1; $i++ ) {
                                $index1 = IndexOfNodeInNodeArray( $common_nodes[$i], @{$ref_way} );
                                $index2 = IndexOfNodeInNodeArray( $common_nodes[$i+1], @{$ref_way} );
                                if ( $index1 == $index2+1 || $index1 == $index2-1 ) {
                                    printf STDERR "doesWayTraverseRoundAbout() : yes (secant) -> index1 = %d, index2 = %d\n", $index1, $index2       if ( $debug );
                                    return 1;
                                } else {
                                    printf STDERR "doesWayTraverseRoundAbout() : no (outer loop) -> index1 = %d, index2 = %d\n", $index1, $index2       if ( $debug );
                                }
                            }
                        } else {
                            printf STDERR "doesWayTraverseRoundAbout() : no (way ends on rim1) -> on-rim = %d, count_way_nodes = %d, inside = %d\n", $count_common_nodes, $count_way_nodes, $nodes_inside     if ( $debug );
                        }
                    } elsif ( ($count_common_nodes+$nodes_inside) > 1 ) {
                        printf STDERR "doesWayTraverseRoundAbout() : yes (common nodes and inside) -> on-rim = %d, inside = %d\n", $count_common_nodes, $nodes_inside       if ( $debug );
                        return 1;
                    } else {
                        printf STDERR "doesWayTraverseRoundAbout() : no (way ends on rim2) -> on-rim = %d, inside = %d\n", $count_common_nodes, $nodes_inside     if ( $debug );
                    }
                } else {
                    if ( $number_of_roundabout_points && $count_common_nodes == $count_way_nodes ) {
                            printf STDERR "doesWayTraverseRoundAbout() : yes (chord of circle) -> on-rim = %d, count_way_points = %d, count_roundabout_points = %d\n", $count_common_nodes, $number_of_way_points, $number_of_roundabout_points       if ( $debug );
                            return 1;
                    } else {
                        printf STDERR "doesWayTraverseRoundAbout() : ?? -> on-rim = %d, count_way_points = %d, count_roundabout_points = %d\n", $count_common_nodes, $number_of_way_points, $number_of_roundabout_points       if ( $debug );
                    }
                }
            } else {
                printf STDERR "doesWayTraverseRoundAbout() : ?? -> roundabout is not closed way\n"       if ( $debug );
            }
        } else {
            printf STDERR "doesWayTraverseRoundAbout() : ?? -> count_way_nodes = %d, count_roundabout_nodes = %d\n", $count_way_nodes, $count_roundabout_nodes       if ( $debug );
        }
    } else {
        printf STDERR "doesWayTraverseRoundAbout() : ?? -> parameter(s) not defined\n"       if ( $debug );
    }
    return 0;
}


#############################################################################################

sub CheckThisWayTypeForThisVehicle {
    my $way_id          = shift;
    my $vehicle_type    = shift;
    my $help_string     = '';
    my $waykey_list     = '';

    if ( $way_id && $WAYS{$way_id} && $WAYS{$way_id}->{'tag'} && $vehicle_type ) {
        if ( !$WAYS{$way_id}->{'tag'}->{'public_transport'} ||
             ($WAYS{$way_id}->{'tag'}->{'public_transport'} ne 'stop_position' &&
              $WAYS{$way_id}->{'tag'}->{'public_transport'} ne 'platform'        )  ) {
            if ( $transport_type_uses_way_type{$vehicle_type} ) {
                foreach my $waykey ( keys( %{$transport_type_uses_way_type{$vehicle_type}} ) ) {
                    if ( $WAYS{$way_id}->{'tag'}->{$waykey} ) {
                        foreach my $wayvalue ( @{${$transport_type_uses_way_type{$vehicle_type}}{$waykey}}) {
                            if ( $wayvalue eq $WAYS{$way_id}->{'tag'}->{$waykey} ) {
                                printf STDERR "CheckThisWayTypeForThisVehicle() : way %d has appropriate '%s' = '%s' for vehicle '%s'\n", $way_id, $waykey, $wayvalue, $vehicle_type       if ( $debug );
                                return '';
                            }
                        }
                        printf STDERR "CheckThisWayTypeForThisVehicle() : way %d has wrong '%s' = '%s' for vehicle '%s'\n", $way_id, $waykey, $WAYS{$way_id}->{'tag'}->{$waykey}, $vehicle_type       if ( $debug );
                        return detail('way.wrong_value', $waykey, $WAYS{$way_id}->{'tag'}->{$waykey});
                    }
                }
                if ( $WAYS{$way_id}->{'tag'}->{'route'} && $WAYS{$way_id}->{'tag'}->{'route'} eq 'ferry' ) {
                    if ( $vehicle_type eq 'bus' || $vehicle_type eq 'trolleybus' || $vehicle_type eq 'share_taxi' || $vehicle_type eq 'coach' ) {
                        foreach my $v ( $vehicle_type, 'psv', 'motor_vehicle', 'vehicle', 'taxi', 'motorcar' ) {
                            if ( $WAYS{$way_id}->{'tag'}->{$v} &&
                                ($WAYS{$way_id}->{'tag'}->{$v} eq 'yes'        ||
                                 $WAYS{$way_id}->{'tag'}->{$v} eq 'permissive' ||
                                 $WAYS{$way_id}->{'tag'}->{$v} eq 'designated' ||
                                 $WAYS{$way_id}->{'tag'}->{$v} eq 'official'      ) ) {
                                printf STDERR "CheckThisWayTypeForThisVehicle() : way %d has appropriate 'route' = 'ferry' for vehicle '%s': '%s' = '%s'\n", $way_id, $vehicle_type, $v, $WAYS{$way_id}->{'tag'}->{$v}       if ( $debug );
                                return '';
                            }
                        }
                    }
                }
                $waykey_list = list_msg( 'or', sort ( keys( %{$transport_type_uses_way_type{$vehicle_type}} ) ) );
                printf STDERR "CheckThisWayTypeForThisVehicle() : way %d has missing key(s) '%s' for vehicle '%s'\n", $way_id, $waykey_list, $vehicle_type       if ( $debug );
                return detail('way.missing_key', $waykey_list);
            }
        }
    }

    printf STDERR "CheckThisWayTypeForThisVehicle() : way %d is globally appropriate for vehicle '%s'\n", $way_id, $vehicle_type       if ( $debug );
    return '';
}


#############################################################################################

sub CheckThisWaySubTypeForThisVehicle {
    my $way_id          = shift;
    my $vehicle_type    = shift;

    if ( $way_id                                                       &&
         $WAYS{$way_id}                                                &&
         $WAYS{$way_id}->{'tag'}                                       &&
         $WAYS{$way_id}->{'tag'}->{'highway'}                          &&
         $WAYS{$way_id}->{'tag'}->{'service'}                          &&
         $WAYS{$way_id}->{'tag'}->{'highway'} eq 'service'             &&
         ($WAYS{$way_id}->{'tag'}->{'service'} eq 'driveway'        ||
          $WAYS{$way_id}->{'tag'}->{'service'} eq 'parking_aisle'   ||
          $WAYS{$way_id}->{'tag'}->{'service'} eq 'drive-trough'    ||
          $WAYS{$way_id}->{'tag'}->{'service'} eq 'alley'           ||
          $WAYS{$way_id}->{'tag'}->{'service'} eq 'emergency_access'  )    ) {
        printf STDERR "CheckThisWaySubTypeForThisVehicle() : way %d has wrong 'highway' = 'service' and 'service' = '%s' for vehicle '%s'\n", $way_id, $WAYS{$way_id}->{'tag'}->{'service'}, $vehicle_type       if ( $debug );
        return detail('way.suspicious_sub_type', 'service', $WAYS{$way_id}->{'tag'}->{'service'});
    }
    return '';
}


#############################################################################################

sub noAccessOnWay {
    my $way_id              = shift;
    my $vehicle_type        = shift;        # optional !
    my $ptv                 = shift;        # optional !
    my $forward_or_backward = shift || '';
    my $more_info           = shift || '';
    my $access_type         = $vehicle_type;
    my $tag_suffix          = $forward_or_backward || '';

    my @ret_val             = ();

    my @list_of_access_levels = ( 'psv', 'motorcar', 'motor_vehicle', 'vehicle', 'access' );
    my $tmp_access_level      = undef;

    if ( $vehicle_type && $transport_type_to_restriction_type{$vehicle_type} ) {
        $access_type = $transport_type_to_restriction_type{$vehicle_type};
    }
    if ( $access_type ) {
        unshift( @list_of_access_levels, $access_type );
    }
    if ( $vehicle_type && $vehicle_type eq 'bus' && $more_info =~ m/;school=yes;/ ) {
        unshift( @list_of_access_levels, 'school_bus' );
    }

    if ( $way_id && $WAYS{$way_id} && $WAYS{$way_id}->{'tag'} ) {
        my $way_tag_ref = $WAYS{$way_id}->{'tag'};

        if ( $vehicle_type ) {
            if ( $vehicle_type eq 'ferry' && $way_tag_ref->{'route'} && ($way_tag_ref->{'route'} eq 'ferry' || $way_tag_ref->{'route'} eq 'boat') ) {
                #
                # fine for ferries on ferry ways
                #
                printf STDERR "noAccessOnWay() : access for %s for way %d\n", $vehicle_type, $way_id       if ( $debug );
                return @ret_val;
            } elsif ( ($vehicle_type eq 'tram' || $vehicle_type eq 'train' || $vehicle_type eq 'light_rail' || $vehicle_type eq 'subway') &&
                       $way_tag_ref->{'railway'}                                                                                          &&
                      ($way_tag_ref->{'railway'} eq 'tram' || $way_tag_ref->{'railway'} eq 'train' || $way_tag_ref->{'railway'} eq 'light_rail' || $way_tag_ref->{'railway'} eq 'subway' || $way_tag_ref->{'railway'} eq 'rail')  ) {
                #
                # fine for rail bounded vehicles rails
                #
                printf STDERR "noAccessOnWay() : access for %s for way %d railway=%s)\n", $vehicle_type, $way_id, $way_tag_ref->{'railway'}       if ( $debug );
                return @ret_val;
            }
        }
        foreach my $access_level ( @list_of_access_levels ) {
            if ( $tag_suffix ) {
                $tmp_access_level = $access_level . ':' . $tag_suffix;
                if ( $way_tag_ref->{$tmp_access_level} ) {
                    if ( $way_tag_ref->{$tmp_access_level} =~ m/^[a-z; ]*(yes|permissive|permit|official|destination|designated)[a-z; ]*$/ ) {
                        # fine, we have access permission
                        return @ret_val;
                    } else {
                        printf STDERR "noAccessOnWay() : no access for way %d (%s=%s)\n", $way_id, $tmp_access_level, $way_tag_ref->{$tmp_access_level}       if ( $debug );
                        push ( @ret_val, tags( $tmp_access_level, $way_tag_ref->{$tmp_access_level} ) );
                        return @ret_val;
                    }
                }
                $tmp_access_level = $access_level . ':' . $tag_suffix . ':conditional';
                if ( $way_tag_ref->{$tmp_access_level} ) {
                    printf STDERR "noAccessOnWay() : unclear access for way %d\n", $way_id       if ( $debug );
                    push ( @ret_val, tags( $tmp_access_level, $way_tag_ref->{$tmp_access_level} ) );
                    if ( $way_tag_ref->{$tmp_access_level} =~ m/^(yes|permissive|permit|official|destination|designated)/ ) {
                        return @ret_val;
                    }
                }
            }
            $tmp_access_level = $access_level;
            if ( $way_tag_ref->{$tmp_access_level} ) {
                if ( $way_tag_ref->{$tmp_access_level} =~ m/^[a-z; ]*(yes|permissive|permit|official|destination|designated)[a-z; ]*$/ ) {
                    # fine, we have access permission
                    return @ret_val;
                } else {
                    printf STDERR "noAccessOnWay() : no access for way %d (%s=%s)\n", $way_id, $tmp_access_level, $way_tag_ref->{$tmp_access_level}       if ( $debug );
                    push ( @ret_val, tags( $tmp_access_level, $way_tag_ref->{$tmp_access_level} ) );
                    return @ret_val;
                }
            }
            $tmp_access_level = $access_level . ':conditional';
            if ( $way_tag_ref->{$tmp_access_level} ) {
                printf STDERR "noAccessOnWay() : unclear access for way %d\n", $way_id       if ( $debug );
                push ( @ret_val, tags( $tmp_access_level, $way_tag_ref->{$tmp_access_level} ) );
                if ( $way_tag_ref->{$tmp_access_level} =~ m/^(yes|permissive|permit|official|destination|designated)/ ) {
                    return @ret_val;
                }
            }
        }
        if (  ($way_tag_ref->{'busway'} || $way_tag_ref->{'busway:both'} || $way_tag_ref->{'busway:right'} || $way_tag_ref->{'busway:left'}) &&
               $way_tag_ref->{'highway'}                                                                                                     &&
               $way_tag_ref->{'highway'} ne 'construction'                                                                                      ) {
            #
            # fine as this implies 'psv' = 'designated' (or 'bus' = 'designated')
            # except if this is a 'highway' = 'construction'
            #
            printf STDERR "noAccessOnWay() : access for all psv for busway on non construction highway %d\n", $way_id       if ( $debug );
            return @ret_val;
        } elsif ( (!defined($ptv) || $ptv ne '2') && $way_tag_ref->{'public_transport'} && $way_tag_ref->{'public_transport'} eq 'platform' ) {
            #
            # don't check for public_transport=platform (for PTv2 defined only) even if PTv2 is not defined or not '2'
            #
            printf STDERR "noAccessOnWay() : access for %s for way %d for non-PTv2 on Platforms\n", $vehicle_type, $way_id       if ( $debug );
            return @ret_val;
        } else {
            foreach my $highway_type ( 'pedestrian', 'footway', 'cycleway', 'path', 'construction' ) {
                if ( $way_tag_ref->{'highway'} && $way_tag_ref->{'highway'} eq $highway_type ) {
                    my $have_access = 0;
                    foreach my $access_level ( @list_of_access_levels ) {
                        if ( $tag_suffix ) {
                            $tmp_access_level = $access_level . ':' . $tag_suffix;
                            if ( $way_tag_ref->{$tmp_access_level} && $way_tag_ref->{$tmp_access_level} =~ m/^[a-z; ]*(yes|permissive|permit|official|destination|designated)[a-z; ]*$/ ) {
                                printf STDERR "noAccessOnWay() : access for way %d (%s=%s) because of '%s'='%s'\n", $way_id, 'highway', $highway_type, $tmp_access_level, $way_tag_ref->{$tmp_access_level}      if ( $debug );
                                # fine, we have access permission, check next highway_type
                                $have_access = 1;
                                next;
                            }
                            $tmp_access_level = $access_level . ':' . $tag_suffix . ':conditional';
                            if ( $way_tag_ref->{$tmp_access_level} ) {
                                printf STDERR "noAccessOnWay() : access for way %d (%s=%s) because of '%s'='%s'\n", $way_id, 'highway', $highway_type, $tmp_access_level, $way_tag_ref->{$tmp_access_level}      if ( $debug );
                                push ( @ret_val, tags( $tmp_access_level, $way_tag_ref->{$tmp_access_level} ) );
                                # assume, we have access permission, report this and check next highway_type
                                if ( $way_tag_ref->{$tmp_access_level} =~ m/^(yes|permissive|permit|official|destination|designated)/ ) {
                                    $have_access = 1;
                                    next;
                                }
                            }
                        }
                        $tmp_access_level = $access_level;
                        if ( $way_tag_ref->{$tmp_access_level} && $way_tag_ref->{$tmp_access_level} =~ m/^[a-z; ]*(yes|permissive|permit|official|destination|designated)[a-z; ]*$/ ) {
                            printf STDERR "noAccessOnWay() : access for way %d (%s=%s) because of '%s'='%s'\n", $way_id, 'highway', $highway_type, $tmp_access_level, $way_tag_ref->{$tmp_access_level}      if ( $debug );
                            # fine, we have access permission, check next highway_type
                            $have_access = 1;
                            next;
                        }
                        $tmp_access_level = $access_level . ':conditional';
                        if ( $way_tag_ref->{$tmp_access_level} ) {
                            printf STDERR "noAccessOnWay() : access for way %d (%s=%s) because of '%s'='%s'\n", $way_id, 'highway', $highway_type, $tmp_access_level, $way_tag_ref->{$tmp_access_level}      if ( $debug );
                            push ( @ret_val, tags( $tmp_access_level, $way_tag_ref->{$tmp_access_level} ) );
                            # assume, we have access permission, report this and check next highway_type
                            if ( $way_tag_ref->{$tmp_access_level} =~ m/^(yes|permissive|permit|official|destination|designated)/ ) {
                                $have_access = 1;
                                next;
                            }
                        }
                    }
                    if ( $have_access > 0 ) {
                        next;
                    } else {
                        printf STDERR "noAccessOnWay() : no access for way %d (%s=%s) - '%s'='%s'\n", $way_id, 'highway', $highway_type, $tmp_access_level?$tmp_access_level:'', $way_tag_ref->{$tmp_access_level}?$way_tag_ref->{$tmp_access_level}:''       if ( $debug );
                        push ( @ret_val, tags( 'highway', $highway_type ) );
                        return @ret_val;
                    }
                }
            }
            if ( $way_tag_ref->{'construction'}               &&
                 $way_tag_ref->{'highway'}                    &&
                 $way_tag_ref->{'highway'} ne 'construction'  &&
                 $way_tag_ref->{'construction'} ne 'no'       &&
                 $way_tag_ref->{'construction'} ne 'minor'    &&
                 $way_tag_ref->{'construction'} ne 'widening'    ) {
                printf STDERR "noAccessOnWay(%s) : suspicious 'construction' = '%s' on 'highway' = '%s'\n", $way_id, $way_tag_ref->{'construction'}, $way_tag_ref->{'highway'}      if ( $debug );
                push ( @ret_val, tags( 'construction', $way_tag_ref->{'construction'} ) );
                return @ret_val;
            }
        }
    }
    printf STDERR "noAccessOnWay() : access for all for way %d\n", $way_id       if ( $debug );
    return @ret_val;
}


#############################################################################################

sub noAccessOnNode {
    my $node_id         = shift;
    my $vehicle_type    = shift;        # optional !

    my @list_of_access_levels = ( 'psv', 'motorcar', 'motor_vehicle', 'vehicle', 'access' );

    if ( $node_id && $NODES{$node_id} && $NODES{$node_id}->{'tag'}&& $NODES{$node_id}->{'tag'}->{'barrier'} ) {

        my $node_tag_ref = $NODES{$node_id}->{'tag'};

        if ( $vehicle_type ) {
            unshift( @list_of_access_levels, $transport_type_to_restriction_type{$vehicle_type} ? $transport_type_to_restriction_type{$vehicle_type} : $vehicle_type );
        }

        foreach my $access_type ( @list_of_access_levels ) {
            if ( $access_type eq 'bus' && $node_tag_ref->{'barrier'} eq 'bus_trap' ) {
                printf STDERR "noAccessOnNode() : implied access for node %d (barrier=bus_trap, bus=yes)\n", $node_id   if ( $debug );
                return ();
            } elsif ( $node_tag_ref->{$access_type} ) {
                if ( $node_tag_ref->{$access_type} eq 'yes'         ||
                     $node_tag_ref->{$access_type} eq 'destination' ||
                     $node_tag_ref->{$access_type} eq 'designated'  ||
                     $node_tag_ref->{$access_type} eq 'permissive'  ||
                     $node_tag_ref->{$access_type} eq 'official'       ) {
                    printf STDERR "noAccessOnNode() : access for node %d (barrier=%s, %s=%s)\n", $node_id, $node_tag_ref->{'barrier'}, $access_type, $node_tag_ref->{$access_type}       if ( $debug );
                    return ();
                } elsif ( $node_tag_ref->{$access_type} eq 'no'      ||
                          $node_tag_ref->{$access_type} eq 'private'    ) {
                    if ( $access_type eq 'psv' && $node_tag_ref->{$access_type} eq 'private' ) {
                        printf STDERR "noAccessOnNode() : access for node %d (barrier=%s, %s=%s)\n", $node_id, $node_tag_ref->{'barrier'}, $access_type, $node_tag_ref->{$access_type}       if ( $debug );
                        return ();
                    }
                    printf STDERR "noAccessOnNode() : no access for node %d (barrier=%s, %s=%s)\n", $node_id, $node_tag_ref->{'barrier'}, $access_type, $node_tag_ref->{$access_type}       if ( $debug );
                    return ( tags( 'barrier', $node_tag_ref->{'barrier'}, $access_type, $node_tag_ref->{$access_type} ) );
                }
            }
        }

        if ( $node_tag_ref->{'barrier'} eq 'no'          || $node_tag_ref->{'barrier'} eq 'kerb'              ||
             $node_tag_ref->{'barrier'} eq 'entrance'    || $node_tag_ref->{'barrier'} eq 'toll_booth'        ||
             $node_tag_ref->{'barrier'} eq 'bus_trap'    || $node_tag_ref->{'barrier'} eq 'height_restrictor' ||
             $node_tag_ref->{'barrier'} eq 'cattle_grid' || $node_tag_ref->{'barrier'} eq 'border_control'    ||
             $node_tag_ref->{'barrier'} eq 'sally_port'  || $node_tag_ref->{'barrier'} eq 'coupure'              ) {
            printf STDERR "noAccessOnNode() : access for node %d (barrier=%s with implied access=yes)\n", $node_id, $node_tag_ref->{'barrier'}       if ( $debug );
            return ();
        } else {
            printf STDERR "noAccessOnNode() : no access for node %d (barrier=%s, implied access=no)\n", $node_id, $node_tag_ref->{'barrier'}       if ( $debug );
            return ( detail( 'access.barrier_implied_no', $node_tag_ref->{'barrier'} ) );
        }
    }
    printf STDERR "noAccessOnNode() : access for all for node %d\n", $node_id       if ( $debug );
    return ();
}


#############################################################################################

sub noAccessOnPlatform {
    my $platform_id         = shift;
    my $platform_type       = shift;
    my $vehicle_type        = shift || 'bus';
    my $is_school_bus       = shift || 0;
    my $access_type         = $vehicle_type;

    printf STDERR "Check: noAccessOnPlatform() : access %s for %s %d\n", $vehicle_type?$vehicle_type:'?', $platform_type?$platform_type:'?', $platform_id?$platform_id:-99999       if ( $debug );

    my $ret_val             = '';

    my @list_of_access_levels = ( 'psv', 'motorcar', 'motor_vehicle', 'vehicle', 'access' );

    if ( $vehicle_type && $transport_type_to_restriction_type{$vehicle_type} ) {
        $access_type = $transport_type_to_restriction_type{$vehicle_type};
    }
    if ( $access_type ) {
        unshift( @list_of_access_levels, $access_type );
    }
    if ( $is_school_bus ) {
        unshift( @list_of_access_levels, 'school_bus' );
    }

    if ( defined($platform_id) && defined($platform_type) ) {
        my $platform_tag_ref = undef;
        if ( $platform_type eq 'node' && $NODES{$platform_id} ) {
            $platform_tag_ref = $NODES{$platform_id}->{'tag'};
        } elsif ( $platform_type eq 'way' &&  $WAYS{$platform_id} ) {
            $platform_tag_ref = $WAYS{$platform_id}->{'tag'};
        } elsif ( $platform_type eq 'relation' && $RELATIONS{$platform_id} ) {
            $platform_tag_ref = $RELATIONS{$platform_id}->{'tag'};
        } else {
            if ( $platform_type ne 'node' && $platform_type ne 'way' && $platform_type ne 'relation' ) {
                return msg("Internal error: unknown object type '%s' for object ID '%s'", $platform_type, $platform_id );
            } else {
                return msg("Internal error: object type '%s' and unknown object ID '%s'", $platform_type, $platform_id );
            }
        }

        printf STDERR "Details: noAccessOnPlatform() : platform name = %s\n", $platform_tag_ref->{'name'}?$platform_tag_ref->{'name'}:'?'       if ( $debug );

        if ( $vehicle_type ne 'bus' ) {
            if ( $vehicle_type eq 'foot' ) {
                @list_of_access_levels = ( 'foot', 'access' );
            } elsif ( $vehicle_type eq 'ferry' && $platform_tag_ref->{'route'} && ($platform_tag_ref->{'route'} eq 'ferry' || $platform_tag_ref->{'route'} eq 'boat') ) {
                #
                # fine for ferries on ferry ways
                #
                printf STDERR "noAccessOnPlatform() : access for %s for %s %d\n", $vehicle_type, $platform_type, $platform_id       if ( $debug );
                return $ret_val;
            } elsif ( ($vehicle_type eq 'tram' || $vehicle_type eq 'train' || $vehicle_type eq 'light_rail' || $vehicle_type eq 'subway') &&
                       $platform_tag_ref->{'railway'}                                                                                          &&
                      ($platform_tag_ref->{'railway'} eq 'tram' || $platform_tag_ref->{'railway'} eq 'train' || $platform_tag_ref->{'railway'} eq 'light_rail' || $platform_tag_ref->{'railway'} eq 'subway' || $platform_tag_ref->{'railway'} eq 'rail')  ) {
                #
                # fine for rail bounded vehicles rails
                #
                printf STDERR "noAccessOnPlatform() : access for %s for %s %d railway=%s)\n", $vehicle_type, $platform_type, $platform_id, $platform_tag_ref->{'railway'}       if ( $debug );
                return $ret_val;
            }
        }
        foreach my $access_level ( @list_of_access_levels ) {
            if ( $platform_tag_ref->{$access_level} ) {
                if ( $platform_tag_ref->{$access_level} =~ m/^[a-z; ]*(yes|permissive|permit|official|destination|designated)[a-z; ]*$/ ) {
                    # fine, we have access permission
                    return $ret_val;
                } else {
                    printf STDERR "noAccessOnPlatform() : no access %s for %s %d (%s=%s)\n", $vehicle_type, $platform_type, $platform_id, $access_level, $platform_tag_ref->{$access_level}       if ( $debug );
                    return tags( $access_level, $platform_tag_ref->{$access_level} );
                }
            }
        }
    }
    printf STDERR "noAccessOnPlatform() : access %s for %s %d\n", $vehicle_type?$vehicle_type:'?', $platform_type?$platform_type:'?', $platform_id?$platform_id:-99999       if ( $debug );
    return $ret_val;
}


#############################################################################################
#
# for syntax of 'name' with 'ref', 'from', 'to' and maybe 'via' included (also ref:*)
#
#############################################################################################

sub CheckNameRefFromViaToPTV2 {
    my $relation_ptr = shift;
    my $return_code  = 0;

    if ( $relation_ptr && $relation_ptr->{'tag'} ) {
        my $preconditions_failed = 0;
        my $name = $relation_ptr->{'tag'}->{'name'} || '';
        my $ref  = defined($relation_ptr->{'tag'}->{'ref'}) ? $relation_ptr->{'tag'}->{'ref'} : '';
        my $from = $relation_ptr->{'tag'}->{'from'} || '';
        my $to   = $relation_ptr->{'tag'}->{'to'}   || '';
        my $via  = $relation_ptr->{'tag'}->{'via'}  || '';

        my $number_of_ref_colon_tags = 0;
        my $ref_string               = '';

        if ( $name ne '' ) {
            #
            # basic checks for 'name' w/o any other dependencies to 'ref', 'from', 'to' and 'via'
            #
            if ( $name =~ m/<=>/ ) {
                push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_deprecated_bidir_arrow') );
                $preconditions_failed++;
                $return_code++;
            }
            if ( $name =~ m/==>/ ) {
                push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_deprecated_arrow') );
                $preconditions_failed++;
                $return_code++;
            }
        }

        if ( $name ne '' && $ref ne '' && $preconditions_failed == 0) {

            if ( $name =~ m/^(.*):\s{0,1}(.*?)\s{0,1}=>\s{0,1}(.*)\s{0,1}=>\s{0,1}(.*)$/ ||
                 $name =~ m/^(.*):\s{0,1}(.*?)\s{0,1}=>\s{0,1}(.*)$/                     ||
                 ( $check_name_relaxed &&
                    ( $name =~ m/^(.*):\s*(.*?)\s*(?:=>|->|→|⇒)\s*(.*)\s*(?:=>|->|→|⇒)\s*(.*)$/ ||
                      $name =~ m/^(.*):\s*(.*?)\s*(?:=>|->|→|⇒)\s*(.*)$/
                    )
                 )
               ) {

                my $ref_in_name       = $1;
                my $from_in_name      = $2;
                my $vias_in_name      = $3;
                my $to_in_name        = $4;
                my @via_parts_in_name = ();

                if ( $to_in_name) {
                    if ( $check_name_relaxed ) {
                        @via_parts_in_name = split( '(?:=>|->|→|⇒)', $vias_in_name );
                    } else {
                        @via_parts_in_name = split( '=>', $vias_in_name );
                   }
                    foreach ( @via_parts_in_name ) {
                       s/^\s*//;
                       s/\s*$//;
                    }
                } else {
                    $to_in_name        = $vias_in_name;
                    $vias_in_name      = undef;
                    @via_parts_in_name = ();
                }

                if ( index($ref_in_name,$ref) == -1 ) {
                    #
                    # this will check only combinations of verious refs:  ref='025/9567/11'
                    #                                                     name='Bus LAVV 025/RVO 9567/VLK 11 .....'
                    #                                                     ref:LAV='025'
                    #                                                     ref:RVO='9567'
                    #                                                     ref:VLK='11'
                    my $ref_in_name_w_boundary = ';' . $ref_in_name . ';';
                    foreach my $tag ( sort ( keys ( %{$relation_ptr->{'tag'}} ) ) ) {
                        if ( $tag =~ m/^ref:(\S+)$/ && $tag !~ m/^ref:FR:STIF/ ) {
                            $number_of_ref_colon_tags++;
                            $ref_string = $relation_ptr->{'tag'}->{$tag};
                            if ( $ref_in_name_w_boundary !~ m|[ ;/]$ref_string[ ;/:]| ) {
                                push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_lacks_value', foreign($ref_string), foreign($tag), foreign($relation_ptr->{'tag'}->{$tag})) );
                                $return_code++;
                            }
                        }
                    }
                    if ( $number_of_ref_colon_tags == 0 ) {     # there are no 'ref:*' tags, so check 'ref' being present in 'name'
                        push( @{$relation_ptr->{'__notes__'}}, note('ptv2.ref_not_in_name') );
                        $return_code++;
                    }
                }

                if ( $from ) {
                    if ( $from_in_name ne $from ) {
                        if ( $check_name_relaxed ) {
                            if ( !TagNameMatchesOtherName($from,$from_in_name) ) {
                                push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_from_mismatch', foreign($from_in_name), foreign($from)) );
                                $return_code++;
                            }
                        } else {
                            push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_from_differs', foreign($from_in_name), foreign($from)) );
                            $return_code++;
                        }
                    }
                } else {
                    push( @{$relation_ptr->{'__notes__'}}, note('ptv2.from_not_set') );
                    $return_code++;
                }

                if ( $to ) {
                    if ( $to_in_name ne $to ) {
                        if ( $check_name_relaxed ) {
                            if ( !TagNameMatchesOtherName($to,$to_in_name) ) {
                                push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_to_mismatch', foreign($to_in_name), foreign($to)) );
                                $return_code++;
                            }
                        } else {
                            push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_to_differs', foreign($to_in_name), foreign($to)) );
                            $return_code++;
                        }
                    }
                } else {
                    push( @{$relation_ptr->{'__notes__'}}, note('ptv2.to_not_set') );
                    $return_code++;
                }

                if ( scalar(@via_parts_in_name) ) {
                    if ( $via ) {
                        my @via_values  = split( ";", $via );

                        if ( scalar(@via_parts_in_name) == scalar(@via_values) ) {
                            for ( my $index = 0; $index < scalar(@via_parts_in_name); $index++ ) {
                                if ( $via_parts_in_name[$index] ne $via_values[$index] ) {
                                    if ( $check_name_relaxed ) {
                                        #printf STDERR "check %d via = %s against %s\n", $index, $via_values[$index], $via_parts_in_name[$index];
                                        if ( !TagNameMatchesOtherName($via_values[$index],$via_parts_in_name[$index]) ) {
                                            push( @{$relation_ptr->{'__notes__'}}, note('ptv2.via_part_mismatch', $index+1, foreign($via_parts_in_name[$index]), $index+1, foreign($via_values[$index])) );
                                            $return_code++;
                                        }
                                    } else {
                                        push( @{$relation_ptr->{'__notes__'}}, note('ptv2.via_part_differs', $index+1, foreign($via_parts_in_name[$index]), $index+1, foreign($via_values[$index])) );
                                        $return_code++;
                                    }
                                }
                            }
                        } elsif ( scalar(@via_parts_in_name) > scalar(@via_values) ) {
                            push( @{$relation_ptr->{'__notes__'}}, note('ptv2.via_name_more', scalar(@via_parts_in_name), scalar(@via_values)) );
                            $return_code++;
                        } else {
                            push( @{$relation_ptr->{'__notes__'}}, note('ptv2.via_name_fewer', scalar(@via_parts_in_name), scalar(@via_values)) );
                            $return_code++;
                        }
                    } else {
                        push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_multi_arrow_no_via') );
                        $return_code++;
                    }
                } elsif ( $via ) {
                    push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_no_via_but_via_set') );
                    $return_code++;
                }
            } else {
                if ( $check_name_relaxed ) {
                    push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_form_similar') );
                } else {
                    push( @{$relation_ptr->{'__notes__'}}, note('ptv2.name_form_required') );
                }
                $return_code++;
            }
        } else {
            if ( $name eq '' ) {
                # already checked at a very early position, but must increase return_code here
                #$issues_string = gettext( "'name' is not set" );
                #push( @{$relation_ptr->{'__issues__'}}, $issues_string );
                $return_code++;
            }
            if ( $ref eq '' ) {
                # already checked at a very early position, but must increase return_code here
                #$issues_string = gettext( "'ref' is not set" );
                #push( @{$relation_ptr->{'__issues__'}}, $issues_string );
                $return_code++;
            }
        }
    }

    return $return_code;
}


#############################################################################################
#
# does value of 'from', 'via' or 'to' match (relaxed) other 'name'
#
#############################################################################################

sub TagNameMatchesOtherName {
    my $tag_name   = shift || '';
    my $other_name = shift || '';

    $tag_name   =~ s/\s*\(.*?\)//;
    $other_name =~ s/\s*\(.*?\)//;
    return 1    if ( $tag_name   eq $other_name );
    return 1    if ( $other_name =~ m|^\Q$tag_name\E\.$|           );
    return 1    if ( $tag_name   =~ m|^\Q$other_name\E\.$|         );
    return 1    if ( $other_name =~ m|^\Q$tag_name\E[ /,-]\s*\S|   );
    return 1    if ( $tag_name   =~ m|^\Q$other_name\E[ /,-]\s*\S| );
    return 1    if ( $other_name =~ m|\S\s*[ /,-]\Q$tag_name\E$|   );
    return 1    if ( $tag_name   =~ m|\S\s*[ /,-]\Q$other_name\E$| );
    return 1    if ( $other_name =~ m|\S\s*[ /,-]\Q$tag_name\E[ /,-]\s*\S|   );
    return 1    if ( $tag_name   =~ m|\S\s*[ /,-]\Q$other_name\E[ /,-]\s*\S| );

    if ( $tag_name =~ m|[ /,-]| && $other_name =~ m|[ /,-]| ) {
        my @tag_name_array   = split( '\s*[ /,-]\s*', $tag_name,   2 );
        my @other_name_array = split( '\s*[ /,-]\s*', $other_name, 2 );
        if ( ($tag_name_array[0] eq $other_name_array[0] &&
              $tag_name_array[1] eq $other_name_array[1]   ) ||
             ($tag_name_array[0] eq $other_name_array[1] &&
              $tag_name_array[1] eq $other_name_array[0]   )    ) {
            return 1;
        }
    }
#    return 1    if ( index($other_name,$tag_name.' ')  == 0 );                       # tag_name="City" other_name="City ..."
#    return 1    if ( index($tag_name,$other_name.' ')  == 0 );                       # tag_name="City ..." other_name="City"
#    return 1    if ( index($other_name,$tag_name.',')  == 0 );                       # tag_name="City" other_name="City, Street"
#    return 1    if ( index($tag_name,$other_name.',')  == 0 );                       # tag_name="City, Street" other_name="City"
#    return 1    if ( index($other_name,','.$tag_name)  >  0 );                       # tag_name="Street" other_name="City,Street"
#    return 1    if ( index($tag_name,','.$other_name)  >  0 );                       # tag_name="City,Street" other_name="Street"
#    return 1    if ( index($other_name,', '.$tag_name) >  0 );                       # tag_name="Street" other_name="City, Street"
#    return 1    if ( index($tag_name,', '.$other_name) >  0 );                       # tag_name="City, Street" other_name="Street"
#    return 1    if ( index($other_name,' '.$tag_name)  >  0 );                       # tag_name="Street" other_name="City Street"
#    return 1    if ( index($tag_name,' '.$other_name)  >  0 );                       # tag_name="City Street" other_name="Street"
    return 0;
}


#############################################################################################
#
# check values of 'from', 'via' and 'to' against 'name' of platforms
#
#############################################################################################

sub CheckFromViaToPlatformNamesPTV2 {
    my $relation_ptr = shift;
    my $return_code  = 0;

    printf STDERR "CheckFromViaToPlatformNamesPTV2() : %s, ref = %s\n", $relation_ptr->{'id'}, $relation_ptr->{'tag'}->{'ref'} ? $relation_ptr->{'tag'}->{'ref'} : ''       if ( $debug );
    if ( $relation_ptr && $relation_ptr->{'tag'} ) {
        my $from                = $relation_ptr->{'tag'}->{'from'} || '';
        my $to                  = $relation_ptr->{'tag'}->{'to'}   || '';
        my $via                 = $relation_ptr->{'tag'}->{'via'}  || '';
        my $number_of_platforms = scalar(@{$relation_ptr->{'role_platform'}});

        if ( $check_from_to && $from ) {
            printf STDERR "    CheckFromViaToPlatformNamesPTV2() : from = %s, number of platforms = %d\n", $relation_ptr->{'tag'}->{'from'}, $number_of_platforms       if ( $debug );
            # > 0: there must at least be one platform, the 'from' one
            if ( $number_of_platforms                        > 0 &&
                 ${$relation_ptr->{'role_platform'}}[0]          &&
                 ${$relation_ptr->{'role_platform'}}[0]->{'ref'}    ) {
                my $platform_id   = ${$relation_ptr->{'role_platform'}}[0]->{'ref'};
                my $platform_type = ${$relation_ptr->{'role_platform'}}[0]->{'type'};
                my $platform_name = '';
                printf STDERR "        CheckFromViaToPlatformNamesPTV2() : platform id = %s, plattform type = %s\n", $platform_id, $platform_type       if ( $debug );
                if ( $platform_type eq 'relation'                &&
                     $RELATIONS{$platform_id}                    &&
                     $RELATIONS{$platform_id}->{'tag'}           &&
                     $RELATIONS{$platform_id}->{'tag'}->{'name'}    ) {
                    $platform_name = $RELATIONS{$platform_id}->{'tag'}->{'name'} || '';
                    printf STDERR "            CheckFromViaToPlatformNamesPTV2() Relation : platform name = %s\n", $platform_name       if ( $debug );
                } elsif ( $platform_type eq 'way'                &&
                          $WAYS{$platform_id}                    &&
                          $WAYS{$platform_id}->{'tag'}           &&
                          $WAYS{$platform_id}->{'tag'}->{'name'}    ) {
                    $platform_name = $WAYS{$platform_id}->{'tag'}->{'name'} || '';
                    printf STDERR "            CheckFromViaToPlatformNamesPTV2() Way : platform name = %s\n", $platform_name       if ( $debug );
                } elsif ( $platform_type eq 'node'                &&
                          $NODES{$platform_id}                    &&
                          $NODES{$platform_id}->{'tag'}           &&
                          $NODES{$platform_id}->{'tag'}->{'name'}    ) {
                    $platform_name = $NODES{$platform_id}->{'tag'}->{'name'} || '';
                    printf STDERR "            CheckFromViaToPlatformNamesPTV2() : platform name = %s\n", $platform_name       if ( $debug );
                }
                printf STDERR "                CheckFromViaToPlatformNamesPTV2() : from = %s, platform name = %s\n", $from, $platform_name       if ( $debug );
                if ( $platform_name && $from ne $platform_name ) {
                    if ( $check_from_to eq 'relaxed' ) {
                        if ( !TagNameMatchesOtherName($from,$platform_name) ) {
                            push( @{$relation_ptr->{'__notes__'}}, note('ptv2.from_mismatch_platform', $from, printXxxTemplate($platform_type,$platform_id,'name;ref')) );
                            $return_code++;
                        }
                    } else {    # strict check for being identical
                        push( @{$relation_ptr->{'__notes__'}}, note('ptv2.from_differs_platform', $from, printXxxTemplate($platform_type,$platform_id,'name;ref')) );
                        $return_code++;
                    }
                }
            }
        } else {
            if ( ! $check_name ) {
                push( @{$relation_ptr->{'__notes__'}}, note('ptv2.from_not_set') );
                $return_code++;
            }
        }

        if ( $check_from_to && $to ) {
            printf STDERR "    CheckFromViaToPlatformNamesPTV2() : to = %s, number of platforms = %d\n", $relation_ptr->{'tag'}->{'to'}, $number_of_platforms       if ( $debug );
            # > 1 : first platform is always considered as representing 'from'
            if ( $number_of_platforms                                             > 1 &&
                 ${$relation_ptr->{'role_platform'}}[$number_of_platforms-1]          &&
                 ${$relation_ptr->{'role_platform'}}[$number_of_platforms-1]->{'ref'}    ) {
                my $platform_id   = ${$relation_ptr->{'role_platform'}}[$number_of_platforms-1]->{'ref'};
                my $platform_type = ${$relation_ptr->{'role_platform'}}[$number_of_platforms-1]->{'type'};
                my $platform_name = '';
                printf STDERR "        CheckFromViaToPlatformNamesPTV2() : platform id = %s, plattform type = %s\n", $platform_id, $platform_type       if ( $debug );
                if ( $platform_type eq 'relation'                &&
                     $RELATIONS{$platform_id}                    &&
                     $RELATIONS{$platform_id}->{'tag'}           &&
                     $RELATIONS{$platform_id}->{'tag'}->{'name'}    ) {
                    $platform_name = $RELATIONS{$platform_id}->{'tag'}->{'name'} || '';
                    printf STDERR "            CheckFromViaToPlatformNamesPTV2() Relation : platform name = %s\n", $platform_name       if ( $debug );
                } elsif ( $platform_type eq 'way'                &&
                          $WAYS{$platform_id}                    &&
                          $WAYS{$platform_id}->{'tag'}           &&
                          $WAYS{$platform_id}->{'tag'}->{'name'}    ) {
                    $platform_name = $WAYS{$platform_id}->{'tag'}->{'name'} || '';
                    printf STDERR "            CheckFromViaToPlatformNamesPTV2() Way : platform name = %s\n", $platform_name       if ( $debug );
                } elsif ( $platform_type eq 'node'                &&
                          $NODES{$platform_id}                    &&
                          $NODES{$platform_id}->{'tag'}           &&
                          $NODES{$platform_id}->{'tag'}->{'name'}    ) {
                    $platform_name = $NODES{$platform_id}->{'tag'}->{'name'} || '';
                    printf STDERR "            CheckFromViaToPlatformNamesPTV2() Node : platform name = %s\n", $platform_name       if ( $debug );
                }
                printf STDERR "                CheckFromViaToPlatformNamesPTV2() : to = %s, platform name = %s\n", $to, $platform_name       if ( $debug );
                if ( $platform_name && $to ne $platform_name ) {
                    if ( $check_from_to eq 'relaxed' ) {
                        if ( !TagNameMatchesOtherName($to,$platform_name) ) {
                            push( @{$relation_ptr->{'__notes__'}}, note('ptv2.to_mismatch_platform', $to, printXxxTemplate($platform_type,$platform_id,'name;ref')) );
                            $return_code++;
                        }
                    } else {    # strict check for being identical
                        push( @{$relation_ptr->{'__notes__'}}, note('ptv2.to_differs_platform', $to, printXxxTemplate($platform_type,$platform_id,'name;ref')) );
                        $return_code++;
                    }
                }
            }
        } else {
            if ( ! $check_name ) {
                push( @{$relation_ptr->{'__notes__'}}, note('ptv2.to_not_set') );
                $return_code++;
            }
        }

        if ( $check_via && $via ) {
            printf STDERR "    CheckFromViaToPlatformNamesPTV2() : via = %s, number of platforms = %d\n", $relation_ptr->{'tag'}->{'via'}, $number_of_platforms       if ( $debug );
            my @via_parts     = split( ";", $via );
            my $via_number    = scalar(@via_parts);
            # > 2: via platforms cannot be first ('from') and last ('to')
            if ( $number_of_platforms > 2 ) {                   # we have more than first and last platform
                my @via_parts     = split( ";", $via );
                my $via_number    = scalar(@via_parts);
                my $via_part      = '';
                my $platform_id   = '';
                my $platform_type = '';
                my $platform_name = '';
                my @via_matches   = ();
                # collect the information
                for ( my $vindex = 0; $vindex < $via_number; $vindex++ ) {
                    $via_part = $via_parts[$vindex];
                    $via_part =~ s/^\s*//;
                    $via_part =~ s/\s*$//;
                    printf STDERR "        CheckFromViaToPlatformNamesPTV2() via index = %d, via part = %s\n", $vindex, $via_part       if ( $debug );
                    for ( my $pindex = 1; $pindex < $number_of_platforms-1; $pindex++ ) {
                        $platform_id   = ${$relation_ptr->{'role_platform'}}[$pindex]->{'ref'};
                        $platform_type = ${$relation_ptr->{'role_platform'}}[$pindex]->{'type'};
                        $platform_name = '';
                        printf STDERR "            CheckFromViaToPlatformNamesPTV2() : platform index = %d, platform id = %s, plattform type = %s\n", $pindex, $platform_id, $platform_type       if ( $debug );
                        if ( $platform_type eq 'relation'                &&
                             $RELATIONS{$platform_id}                    &&
                             $RELATIONS{$platform_id}->{'tag'}           &&
                             $RELATIONS{$platform_id}->{'tag'}->{'name'}    ) {
                            $platform_name = $RELATIONS{$platform_id}->{'tag'}->{'name'} || '';
                            printf STDERR "                    CheckFromViaToPlatformNamesPTV2() Relation : platform name = %s\n", $platform_name       if ( $debug );
                        } elsif ( $platform_type eq 'way'                &&
                                  $WAYS{$platform_id}                    &&
                                  $WAYS{$platform_id}->{'tag'}           &&
                                  $WAYS{$platform_id}->{'tag'}->{'name'}    ) {
                            $platform_name = $WAYS{$platform_id}->{'tag'}->{'name'} || '';
                            printf STDERR "                    CheckFromViaToPlatformNamesPTV2() Way : platform name = %s\n", $platform_name       if ( $debug );
                        } elsif ( $platform_type eq 'node'                &&
                                  $NODES{$platform_id}                    &&
                                  $NODES{$platform_id}->{'tag'}           &&
                                  $NODES{$platform_id}->{'tag'}->{'name'}    ) {
                            $platform_name = $NODES{$platform_id}->{'tag'}->{'name'} || '';
                            printf STDERR "                    CheckFromViaToPlatformNamesPTV2() Node : platform name = %s\n", $platform_name       if ( $debug );
                        }
                        printf STDERR "                        CheckFromViaToPlatformNamesPTV2() : via-part = %s, platform name = %s\n", $via_part, $platform_name       if ( $debug );
                        if ( $platform_name ) {
                            #
                            # a platform_id may appear more than once with different pindex if the platform name matches and the vehicle stops there more than once
                            #
                            if ( $via_part eq $platform_name ) {
                                $via_matches[$vindex]->{$pindex}->{$platform_id}->{$platform_type} = $platform_name;
                            } else {
                                if ( $check_via eq 'relaxed' ) {
                                    if ( TagNameMatchesOtherName($via_part,$platform_name) ) {
                                        $via_matches[$vindex]->{$pindex}->{$platform_id}->{$platform_type} = $platform_name;
                                    }
                                }
                            }
                        }
                    }
                }
                # print report
                my $total_single_matches = 0;
                for ( my $vindex = 0; $vindex < $via_number; $vindex++ ) {
                    my @vindex_pindex  = sort ( keys ( %{$via_matches[$vindex]} ) );
                    my @vindex_pnumber = map { $_ + 1 } @vindex_pindex;
                    my $matches        = scalar ( @vindex_pindex );

                    if ( $matches == 0 ) {
                        printf STDERR "    CheckFromViaToPlatformNamesPTV2(): no match for via index = %d, via part = %s\n", $vindex, $via_parts[$vindex]       if ( $debug );
                        push( @{$relation_ptr->{'__notes__'}}, note('ptv2.via_part_no_platform', $vindex+1, $via_parts[$vindex]) );
                        $return_code++;
                    } elsif ( $matches > 1 ) {
                        printf STDERR "    CheckFromViaToPlatformNamesPTV2(): multiple matches for via index = %d, via part = %s with platforms = %s\n", $vindex, $via_parts[$vindex], jointext( ',', @vindex_pindex)       if ( $debug );
                        #my $helpstring    = msg( $notes_string, $vindex+1, $via_parts[$vindex], jointext( ', ',@vindex_pnumber) );
                        #my @help_array    = map { ${$relation_ptr->{'role_platform'}}[$_] } ( @vindex_pindex );
                        #my $num_of_errors = scalar(@help_array);
                        #if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                        #    push( @{$relation_ptr->{'__notes__'}}, msg(gettext("%s: %s and %d more ..."), $helpstring, jointext(', ', map { printXxxTemplate($_->{'type'},$_->{'ref'},'name;ref'); } splice(@help_array,0,$max_error) ), ($num_of_errors-$max_error) ) );
                        #} else {
                        #    push( @{$relation_ptr->{'__notes__'}}, msg("%s: %s", $helpstring, jointext(', ', map { printXxxTemplate($_->{'type'},$_->{'ref'},'name;ref'); } @help_array )) );
                        #}
                        #$return_code++;
                    } else {
                        $total_single_matches++;
                        printf STDERR "    CheckFromViaToPlatformNamesPTV2(): match for %d. via-part, via part = %s with platform index = %d\n", $vindex+1, $via_parts[$vindex], $vindex_pindex[0]       if ( $debug );
                    }

                    if ( $total_single_matches == $via_number ) {
                        ; # check the sequence of the via parts
                    }
                }
            } else {
                printf STDERR "    CheckFromViaToPlatformNamesPTV2(): 'via' is set (%d parts), but there are only %d platforms\n", $via_number, $number_of_platforms       if ( $debug );
                if ( $via_number == 1 ) {
                        push( @{$relation_ptr->{'__notes__'}}, note('ptv2.via_few_platforms', $number_of_platforms) );
                } else {
                        push( @{$relation_ptr->{'__notes__'}}, note('ptv2.via_few_platforms_n', $via_number, $via_number+2, $number_of_platforms) );
                }
                $return_code++;
           }
        }
    }

    return $return_code;
}


#############################################################################################
#
# for WAYS used by vehicles             vehicles must use the right way type
#
#############################################################################################

sub CheckWayType {
    my $relation_ptr = shift;
    my $ret_val      = 0;

    if ( $relation_ptr ) {
        my $this_is_wrong            = '';
        my %using_wrong_way_type     = ();
        my %using_wrong_way_sub_type = ();
        my $PTv2                     = undef;
        my $helpstring               = '';
        my @help_array               = ();
        my $num_of_errors            = 0;

        if ( $relation_ptr                                               &&
             $relation_ptr->{'tag'}                                      &&
             $relation_ptr->{'tag'}->{'public_transport:version'}        &&
             $relation_ptr->{'tag'}->{'public_transport:version'} eq '2'    ) {
            $PTv2 = 1;
        }

        foreach my $route_highway ( @{$relation_ptr->{'route_highway'}} ) {
            if ( $PTv2 ) {
                $this_is_wrong = CheckThisWayTypeForThisVehicle( $route_highway->{'ref'}, $relation_ptr->{'route_type_value'} );
                if ( $this_is_wrong ) {
                    $using_wrong_way_type{mkey($this_is_wrong)}->{$route_highway->{'ref'}} = 1;
                    $ret_val++;
                }
            }
            if ( $check_service_type ) {
                $this_is_wrong = CheckThisWaySubTypeForThisVehicle( $route_highway->{'ref'}, $relation_ptr->{'route_type_value'} );
                if ( $this_is_wrong ) {
                    $using_wrong_way_sub_type{mkey($this_is_wrong)}->{$route_highway->{'ref'}} = 1;
                    $ret_val++;
                }
            }
        }
        if ( $PTv2 && scalar(keys(%using_wrong_way_type)) ) {
            foreach $this_is_wrong ( sort(keys(%using_wrong_way_type)) ) {
                $helpstring    = issue('ptv2.wrong_way_type', unkey($this_is_wrong));
                @help_array    = sort(keys(%{$using_wrong_way_type{$this_is_wrong}}));
                $num_of_errors = scalar(@help_array);
                if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                    push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                } else {
                    push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                }
            }
        }
        if ( scalar(keys(%using_wrong_way_sub_type)) ) {
            foreach $this_is_wrong ( sort(keys(%using_wrong_way_sub_type)) ) {
                $helpstring    = note('route.way_type', unkey($this_is_wrong));
                @help_array    = sort(keys(%{$using_wrong_way_sub_type{$this_is_wrong}}));
                $num_of_errors = scalar(@help_array);
                if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                    push( @{$relation_ptr->{'__notes__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                } else {
                    push( @{$relation_ptr->{'__notes__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                }
            }
        }
    }
}


#############################################################################################
#
# for WAYS used by vehicles             vehicles must have access permission
# for NODES of WAYS used by vehicles    vehicles must have access permission on barrier NODES
#
#############################################################################################

sub CheckAccessOnWaysAndNodes {
    my $relation_ptr = shift;
    my $ret_val      = 0;
    my $more_info    = '';

    if ( $relation_ptr ) {
        if ( $relation_ptr->{'route_type_value'} ne 'aerialway' &&
             $relation_ptr->{'route_type_value'} ne 'funicular' &&
             $relation_ptr->{'route_type_value'} ne 'monorail'     ) {
            my $access_restriction                  = undef;
            my @access_restrictions                 = ();
            my %restricted_access_on_ways           = ();
            my %restricted_access_on_nodes          = ();
            my %restricted_access_on_platforms      = ();
            my %restricted_foot_access_on_platforms = ();

            if ( $relation_ptr->{'route_type_value'} eq 'bus' ) {
                my $is_school_bus = 0;
                if ( $relation_ptr->{'tag'}->{'school'} && $relation_ptr->{'tag'}->{'school'} eq 'yes' ) {
                    $more_info .= ';school=' . $relation_ptr->{'tag'}->{'school'} . ';';
                    $is_school_bus = 1;
                }
                if ( scalar(@{$relation_ptr->{'role_platform'}}) ) {
                    my $number_of_platforms = scalar(@{$relation_ptr->{'role_platform'}});
                    for ( my $pindex = 0; $pindex < $number_of_platforms; $pindex++ ) {
                        my $platform_id   = ${$relation_ptr->{'role_platform'}}[$pindex]->{'ref'};
                        my $platform_type = ${$relation_ptr->{'role_platform'}}[$pindex]->{'type'};
                        $access_restriction = noAccessOnPlatform( $platform_id,
                                                                  $platform_type,
                                                                  $relation_ptr->{'route_type_value'},
                                                                  $is_school_bus                       );
                        if ( $access_restriction ) {
                            $restricted_access_on_platforms{mkey($access_restriction)}->{$platform_id}->{'type'} = $platform_type;
                        }
                        $access_restriction = noAccessOnPlatform( $platform_id,
                                                                  $platform_type,
                                                                  'foot',
                                                                  $is_school_bus );
                        if ( $access_restriction ) {
                            $restricted_foot_access_on_platforms{mkey($access_restriction)}->{$platform_id}->{'type'} = $platform_type;
                        }
                    }
                }
            }
            foreach my $route_highway ( @{$relation_ptr->{'route_highway'}} ) {
                if ( $relation_ptr->{'ways_used_with_relevant_forward_backward_tags'} &&
                     $relation_ptr->{'ways_used_with_relevant_forward_backward_tags'}->{$route_highway->{'ref'}} ) {
                    foreach my $forward_or_backward ( keys ( %{$relation_ptr->{'ways_used_with_relevant_forward_backward_tags'}->{$route_highway->{'ref'}}} ) ) {
                        printf STDERR "Calling 'noAccessOnWay( way_id = %s, route = %s, ptv =  %s, fw/bw = %s, more = %s )'\n", $route_highway->{'ref'}, $relation_ptr->{'route_type_value'}, $relation_ptr->{'tag'}->{'public_transport:version'}, $forward_or_backward, $more_info    if ($debug );
                        @access_restrictions = noAccessOnWay( $route_highway->{'ref'},
                                                              $relation_ptr->{'route_type_value'},
                                                              $relation_ptr->{'tag'}->{'public_transport:version'},
                                                              $forward_or_backward,
                                                              $more_info                                            );
                        foreach $access_restriction ( @access_restrictions ) {
                            printf STDERR "noAccessOnWay() = '%s'\n", $access_restriction    if ($debug );
                            $restricted_access_on_ways{mkey($access_restriction)}->{$route_highway->{'ref'}} = 1;
                            $ret_val++;
                        }
                    }
                } else {
                    printf STDERR "Calling 'noAccessOnWay( way_id = %s, route = %s, ptv = %s, fw/bw = '', more = %s )'\n", $route_highway->{'ref'}, $relation_ptr->{'route_type_value'}, $relation_ptr->{'tag'}->{'public_transport:version'}?$relation_ptr->{'tag'}->{'public_transport:version'}:'', $more_info    if ($debug );
                    @access_restrictions = noAccessOnWay( $route_highway->{'ref'},
                                                          $relation_ptr->{'route_type_value'},
                                                          $relation_ptr->{'tag'}->{'public_transport:version'},
                                                          '',
                                                          $more_info                                                );
                    foreach $access_restriction ( @access_restrictions ) {
                        printf STDERR "noAccessOnWay() = '%s'\n", $access_restriction    if ($debug );
                        $restricted_access_on_ways{mkey($access_restriction)}->{$route_highway->{'ref'}} = 1;
                        $ret_val++;
                    }
                }

                foreach my $highway_node_ID ( @{$WAYS{$route_highway->{'ref'}}->{'chain'}} ) {
                    @access_restrictions = noAccessOnNode( $highway_node_ID,
                                                           $relation_ptr->{'route_type_value'} );
                     foreach $access_restriction ( @access_restrictions ) {
                        $restricted_access_on_nodes{mkey($access_restriction)}->{$highway_node_ID} = 1;
                        $ret_val++;
                    }
                }
            }
            if ( scalar(keys(%restricted_access_on_ways)) ) {
                my $helpstring     = '';
                my @help_array     = ();
                my $num_of_errors  = 0;
                foreach $access_restriction ( sort(keys(%restricted_access_on_ways)) ) {
                    @help_array     = sort(keys(%{$restricted_access_on_ways{$access_restriction}}));
                    $num_of_errors  = scalar(@help_array);
                    if ( $access_restriction =~ m/conditional/ ) {
                        foreach my $way_id ( @help_array ) {
                            $conditional_access{$access_restriction}->{'ways'}->{$way_id}->{$relation_ptr->{'id'}} = 1;
                            $conditional_access{$access_restriction}->{'relations'}->{$relation_ptr->{'id'}}->{$way_id} = 1;
                        }
                        unless ( exists($relation_ptr->{'notes_on_conditional_access_added'}) ) {
                            $helpstring   = note('route.see_conditional', foreign(note('route.see')), anchor_msg( 'conditional_on_ways', foreign(gettext("Conditional access statements found on ways")) ));
                            push( @{$relation_ptr->{'__notes__'}}, $helpstring );
                            $relation_ptr->{'notes_on_conditional_access_added'} = 1;
                        }
                        #$notes_string = ngettext( "Route: unclear access (%s) to way", "Route: unclear access (%s) to ways", $num_of_errors );
                        #$helpstring   = foreign(msg( $notes_string, $access_restriction ));
                        #if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                        #    push( @{$relation_ptr->{'__notes__'}}, msg(gettext("%s: %s and %d more ..."), $helpstring, jointext(', ', map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error) ), ($num_of_errors-$max_error) ) );
                        #} else {
                        #    push( @{$relation_ptr->{'__notes__'}}, msg("%s: %s", $helpstring, jointext(', ', map { printWayTemplate($_,'name;ref'); } @help_array )) );
                        #}
                    } elsif ( $access_restriction =~ m/^'([^']+)'='(.*\|.*)'$/ ) {
                        my $access_type = $1;
                        my $restriction = $2;
                        my $tag_suffix  = '';
                        if ( $access_type =~ m/^([^:]+)(:.*)/ ) {
                            $access_type = $1;
                            $tag_suffix  = $2;
                        }
                        $helpstring    = foreign(issue('access.way_suspicious_lanes', $num_of_errors, unkey($access_restriction), $transport_type_to_restriction_type{$access_type} ? $transport_type_to_restriction_type{$access_type} : $access_type, $tag_suffix, $restriction));
                        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                        } else {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                        }
                    } elsif ( $access_restriction =~ m/^'(bus.*?)'='school'$/ ) {
                        unless ( $relation_ptr->{'route_type_value'} eq 'bus'   &&
                                 $relation_ptr->{'tag'}->{'bus'}                &&
                                 $relation_ptr->{'tag'}->{'bus'}   eq 'school'     ) {
                            $helpstring    = foreign(issue('access.way_school', $num_of_errors, $1));
                            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                                push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                            } else {
                                push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                            }
                        }
                    } elsif ( $access_restriction =~ m/^'bus.*?'='(.*lane.*)'$/ ) {
                        $helpstring    = foreign(issue('access.way_busway', $num_of_errors, unkey($access_restriction), $1));
                        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                        } else {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                        }
                    } elsif ( $access_restriction =~ m/^'(bus.*?)'='(.*)'$/ ) {
                        my $access_type = $1;
                        my $restriction = $2;
                        if ( $restriction eq 'no' ) {
                            $helpstring = foreign(issue('access.way_psv_included', $num_of_errors, unkey($access_restriction), $access_type));
                        } else {
                            $helpstring = foreign(issue('access.way_designated', $num_of_errors, unkey($access_restriction), $access_type, $access_type));
                        }
                        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                        } else {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                        }
                    } elsif ( $access_restriction =~ m/^'([^']+)'='(trolleybus|share_taxi|bus|coach|psv)'$/ ) {
                        $helpstring    = foreign(issue('access.way_no_yes', $num_of_errors, unkey($access_restriction), 'motor_vehicle', $transport_type_to_restriction_type{$2} ? $transport_type_to_restriction_type{$2} : $2));
                        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                        } else {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                        }
                    } elsif ( $access_restriction =~ m/^'(trolleybus|share_taxi|coach)'=/ ) {
                        my $vehicle = $1;
                        $helpstring    = foreign(issue('access.way_suspicious_psv', $num_of_errors, unkey($access_restriction), $transport_type_to_restriction_type{$vehicle} ? $transport_type_to_restriction_type{$vehicle} : $vehicle));
                        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                        } else {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                        }
                    } elsif ( $access_restriction =~ m/^\'construction\'=\'/ ) {
                        $helpstring   = foreign(note('route.suspicious_construction', $num_of_errors, unkey($access_restriction)));
                        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                            push( @{$relation_ptr->{'__notes__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                        } else {
                            push( @{$relation_ptr->{'__notes__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                        }
                    } else {
                        my $vehicle = $relation_ptr->{'route_type_value'};
                        $helpstring    = foreign(issue('access.way_no_psv', $num_of_errors, unkey($access_restriction), $transport_type_to_restriction_type{$vehicle} ? $transport_type_to_restriction_type{$vehicle} : $vehicle, $transport_type_to_restriction_type{$vehicle} ? $transport_type_to_restriction_type{$vehicle} : $vehicle));
                        if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                        } else {
                            push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printWayTemplate($_,'name;ref'); } @help_array]) );
                        }
                    }
                }
            }
            if ( scalar(keys(%restricted_access_on_nodes)) ) {
                my $helpstring     = '';
                my @help_array     = ();
                my $num_of_errors  = 0;
                my $vehicle        = $relation_ptr->{'route_type_value'};
                foreach $access_restriction ( sort(keys(%restricted_access_on_nodes)) ) {
                    @help_array     = sort(keys(%{$restricted_access_on_nodes{$access_restriction}}));
                    $num_of_errors  = scalar(@help_array);
                    $helpstring     = foreign(issue('access.barrier', $num_of_errors, unkey($access_restriction), $transport_type_to_restriction_type{$vehicle} ? $transport_type_to_restriction_type{$vehicle} : $vehicle, $transport_type_to_restriction_type{$vehicle} ? $transport_type_to_restriction_type{$vehicle} : $vehicle));
                    if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                        push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printNodeTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printNodeTemplate($_,'name;ref'); } @help_array]) );
                    }
                }
            }
            if ( scalar(keys(%restricted_access_on_platforms)) ) {
                my $helpstring     = '';
                my @help_array     = ();
                my $num_of_errors  = 0;
                my $vehicle        = $relation_ptr->{'route_type_value'};
                foreach $access_restriction ( sort(keys(%restricted_access_on_platforms)) ) {
                    @help_array     = sort(keys(%{$restricted_access_on_platforms{$access_restriction}}));
                    $num_of_errors  = scalar(@help_array);
                    if ( $access_restriction =~ m/school_bus/ ) {
                        $helpstring     = foreign(issue('access.platform_school_bus', $num_of_errors, unkey($access_restriction)));
                    } else {
                        $helpstring     = foreign(issue('access.platform', $num_of_errors, unkey($access_restriction), $transport_type_to_restriction_type{$vehicle} ? $transport_type_to_restriction_type{$vehicle} : $vehicle, $transport_type_to_restriction_type{$vehicle} ? $transport_type_to_restriction_type{$vehicle} : $vehicle));
                    }
                    if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                        push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printXxxTemplate($restricted_access_on_platforms{$access_restriction}->{$_}->{'type'},$_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printXxxTemplate($restricted_access_on_platforms{$access_restriction}->{$_}->{'type'},$_,'name;ref'); } @help_array]) );
                    }
                }
            }
            if ( scalar(keys(%restricted_foot_access_on_platforms)) ) {
                my $helpstring     = '';
                my @help_array     = ();
                my $num_of_errors  = 0;
                foreach $access_restriction ( sort(keys(%restricted_foot_access_on_platforms)) ) {
                    @help_array     = sort(keys(%{$restricted_foot_access_on_platforms{$access_restriction}}));
                    $num_of_errors  = scalar(@help_array);
                    $helpstring     = foreign(issue('access.platform_foot', $num_of_errors, unkey($access_restriction)));
                    if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                        push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printXxxTemplate($restricted_foot_access_on_platforms{$access_restriction}->{$_}->{'type'},$_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                    } else {
                        push( @{$relation_ptr->{'__issues__'}}, listed($helpstring, [map { printXxxTemplate($restricted_foot_access_on_platforms{$access_restriction}->{$_}->{'type'},$_,'name;ref'); } @help_array]) );
                    }
                }
            }
        }
    }
}


#############################################################################################
#
# all WAYS          must not have "highway" = "bus_stop" set - allowed only on nodes
# all RELATIONS     must not have "highway" = "bus_stop" set - allowed only on nodes
#
#############################################################################################

sub CheckBusStopOnWaysAndRelations {
    my $relation_ptr = shift;
    my $ret_val      = 0;

    if ( $relation_ptr ) {
        my %bus_stop_ways = ();

        foreach my $highway_ref ( @{$relation_ptr->{'way'}} ) {
            if ( $WAYS{$highway_ref->{'ref'}}->{'tag'}->{'highway'} && $WAYS{$highway_ref->{'ref'}}->{'tag'}->{'highway'} eq 'bus_stop' ) {
                $bus_stop_ways{$highway_ref->{'ref'}} = 1;
            }
        }
        if ( %bus_stop_ways ) {
            my @help_array     = sort(keys(%bus_stop_ways));
            my $num_of_errors  = scalar(@help_array);
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed(issue('route.bus_stop_on_way', $num_of_errors), [map { printWayTemplate($_,'name;ref'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, listed(issue('route.bus_stop_on_way', $num_of_errors), [map { printWayTemplate($_,'name;ref'); } @help_array]) );
            }
            $ret_val       += $num_of_errors;
        }
    }

    return $ret_val;
}


#############################################################################################
#
# check the 'route_ref' tag on all highway=bus_stop or all public_transport=platform members of this route to have 'ref' of this route included
# check for tags 'bus_lines', 'bus_routes, 'lines', 'line' and 'routes' on stops and propose converting them to 'route_ref'
#
#############################################################################################

sub CheckRouteRefOnStops {
    my $relation_ptr = shift;
    my $ret_val      = 0;

    if ( $relation_ptr ) {
        if ( $relation_ptr->{'tag'} && exists($relation_ptr->{'tag'}->{'ref'}) ) {
            my $ref                     = defined($relation_ptr->{'tag'}->{'ref'}) ? $relation_ptr->{'tag'}->{'ref'} : '';
            my $object_ref              = undef;
            my $platform_or_stop        = undef;
            my $temp_route_ref          = undef;
            my $temp_stop_ref           = undef;
            my $num_of_errors           = undef;
            my $replace_by              = undef;
            my %not_set_on              = ();
            my %separator_with_blank_on = ();
            my %comma_as_separator      = ();
            my %to_be_replaced          = ();
            my %to_be_deleted           = ();
            my %included_refs           = ();
            my @help_array              = ();

            foreach $member ( @{$relation_ptr->{'members'}} ) {
                if ( $member->{'ref'} && $member->{'type'} ) {
                    if ( $member->{'type'} eq 'node' ) {
                        $object_ref = $NODES{$member->{'ref'}};
                    } elsif ( $member->{'type'} eq 'way' ) {
                        $object_ref = $WAYS{$member->{'ref'}};
                    } elsif ( $member->{'type'} eq 'relation' ) {
                        $object_ref = $RELATIONS{$member->{'ref'}};
                    } else {
                        $object_ref = undef;
                    }
                    if ( $object_ref && $object_ref->{'tag'} ) {
                        if ( $object_ref->{'tag'}->{'public_transport'} && $object_ref->{'tag'}->{'public_transport'} eq 'platform' ) {
                            $platform_or_stop = "'public_transport' = 'platform'";
                        } elsif ( $object_ref->{'tag'}->{'highway'} && $object_ref->{'tag'}->{'highway'} eq 'bus_stop') {
                            $platform_or_stop = "'highway' = 'bus_stop'";
                        } elsif ( $object_ref->{'tag'}->{'public_transport'} && $object_ref->{'tag'}->{'public_transport'} eq 'stop_position') {
                            $platform_or_stop = "'public_transport' = 'stop_position'";
                        } else {
                            $platform_or_stop = undef;
                        }
                        if ( $platform_or_stop ) {
                            if ( $object_ref->{'tag'}->{'route_ref'} ) {
                                $temp_route_ref =  ';' . $object_ref->{'tag'}->{'route_ref'} . ';';
                                $temp_route_ref =~ s/\s*;\s*/;/g;

                                foreach my $sub_ref ( split( $ref_separator, $ref ) ) {
                                    if ( $temp_route_ref =~ m/;\Q$sub_ref\E;/ ) {
                                        ; # fine
                                    } else {
                                        $not_set_on{mkey(issue(($object_ref->{'tag'}->{'route_ref'} =~ m/,/) ? 'stop_ref.lacks_route_ref_comma' : 'stop_ref.lacks_route_ref', foreign($object_ref->{'tag'}->{'route_ref'}), foreign($sub_ref)))}->{$member->{'ref'}} = $member->{'type'};

                                        if ( exists($object_ref->{'tag'}->{'ref'}) ) {
                                            $temp_stop_ref =  ';' . $object_ref->{'tag'}->{'ref'} . ';';
                                            $temp_stop_ref =~ s/\s*;\s*/;/g;

                                            foreach my $sub_ref ( split( $ref_separator, $ref ) ) {
                                                if ( $temp_stop_ref =~ m/;\Q$sub_ref\E;/ ) {
                                                    $to_be_replaced{mkey(note('stop_ref.represents_stop_add', foreign($object_ref->{'tag'}->{'ref'}), foreign($sub_ref), foreign($sub_ref)))}->{$member->{'ref'}} = $member->{'type'};
                                                }
                                            }
                                        }
                                    }
                                }

                                if ( $check_osm_separator ) {
#                                    if ( $object_ref->{'tag'}->{'route_ref'} =~ m/\s+;/ ||
#                                         $object_ref->{'tag'}->{'route_ref'} =~ m/;\s+/    ) {
#                                        $notes_string = gettext( "Route: 'route_ref' = '%s' of stop includes the separator value ';' (semi-colon) with sourrounding blank" );
#                                        $separator_with_blank_on{mkey(msg($notes_string,foreign($object_ref->{'tag'}->{'route_ref'})))}->{$member->{'ref'}} = $member->{'type'};
#                                    }
                                    if ( $object_ref->{'tag'}->{'route_ref'} =~ m/,/ ) {
                                        $comma_as_separator{mkey(note('stop_ref.comma_separator', foreign($object_ref->{'tag'}->{'route_ref'})))}->{$member->{'ref'}} = $member->{'type'};
                                    }
                                }

                                foreach my $tag ( 'bus_lines', 'bus_routes', 'lines', 'routes', 'line' ) {
                                    if ( $object_ref->{'tag'}->{$tag} ) {
                                        $to_be_deleted{mkey(note('stop_ref.delete', $tag, foreign($object_ref->{'tag'}->{$tag}), foreign($object_ref->{'tag'}->{'route_ref'})))}->{$member->{'ref'}} = $member->{'type'};
                                    }
                                }
                            } else {
                                foreach my $tag ( 'bus_lines', 'bus_routes', 'lines', 'routes', 'line' ) {
                                    if ( $object_ref->{'tag'}->{$tag} ) {
                                        $replace_by     =  $object_ref->{'tag'}->{$tag};
                                        $replace_by     =~ s/\s*[;,]\s*/;/g;
                                        %included_refs  =  ();
                                        foreach my $set_ref ( split( ';', $replace_by ) ) {
                                            $included_refs{$set_ref} = 1;
                                        }
                                        foreach my $sub_ref ( split( $ref_separator, $ref ) ) {
                                            $included_refs{$sub_ref} = 1;
                                        }
                                        delete( $included_refs{'yes'} );
                                        $replace_by = jointext( ';', sort( { if ( $a =~ m/^[0-9]+$/ && $b =~ m/^[0-9]+$/ ) { $a <=> $b } else { $a cmp $b } } keys( %included_refs ) ) );
                                        $to_be_replaced{mkey(note('stop_ref.replace', $tag, foreign($object_ref->{'tag'}->{$tag}), foreign($replace_by)))}->{$member->{'ref'}} = $member->{'type'};
                                    }
                                }
                                if ( exists($object_ref->{'tag'}->{'ref'}) ) {
                                    $temp_stop_ref =  ';' . $object_ref->{'tag'}->{'ref'} . ';';
                                    $temp_stop_ref =~ s/\s*;\s*/;/g;

                                    foreach my $sub_ref ( split( $ref_separator, $ref ) ) {
                                        if ( $temp_stop_ref =~ m/;\Q$sub_ref\E;/ ) {
                                            $to_be_replaced{mkey(note('stop_ref.represents_stop_create', foreign($object_ref->{'tag'}->{'ref'}), foreign($sub_ref), foreign($sub_ref)))}->{$member->{'ref'}} = $member->{'type'};
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            foreach my $message ( sort( keys( %not_set_on ) ) ) {
                @help_array     = sort( keys( %{$not_set_on{$message}} ) );
                $num_of_errors  = scalar( @help_array );
                $ret_val       += $num_of_errors;
                if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                    push( @{$relation_ptr->{'__issues__'}}, listed(unkey($message), [map { printXxxTemplate($not_set_on{$message}->{$_},$_,'name'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                } else {
                    push( @{$relation_ptr->{'__issues__'}}, listed(unkey($message), [map { printXxxTemplate($not_set_on{$message}->{$_},$_,'name'); } @help_array]) );
                }
            }
            foreach my $message ( sort( keys( %separator_with_blank_on ) ) ) {
                @help_array     = sort( keys( %{$separator_with_blank_on{$message}} ) );
                $num_of_errors  = scalar( @help_array );
                $ret_val       += $num_of_errors;
                if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                    push( @{$relation_ptr->{'__notes__'}}, listed(unkey($message), [map { printXxxTemplate($separator_with_blank_on{$message}->{$_},$_,'name'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                } else {
                    push( @{$relation_ptr->{'__notes__'}}, listed(unkey($message), [map { printXxxTemplate($separator_with_blank_on{$message}->{$_},$_,'name'); } @help_array]) );
                }
            }
            foreach my $message ( sort( keys( %comma_as_separator ) ) ) {
                @help_array     = sort( keys( %{$comma_as_separator{$message}} ) );
                $num_of_errors  = scalar( @help_array );
                $ret_val       += $num_of_errors;
                if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                    push( @{$relation_ptr->{'__notes__'}}, listed(unkey($message), [map { printXxxTemplate($comma_as_separator{$message}->{$_},$_,'name'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                } else {
                    push( @{$relation_ptr->{'__notes__'}}, listed(unkey($message), [map { printXxxTemplate($comma_as_separator{$message}->{$_},$_,'name'); } @help_array]) );
                }
            }
            foreach my $message ( sort( keys( %to_be_replaced ) ) ) {
                @help_array     = sort( keys( %{$to_be_replaced{$message}} ) );
                $num_of_errors  = scalar( @help_array );
                $ret_val       += $num_of_errors;
                if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                    push( @{$relation_ptr->{'__notes__'}}, listed(unkey($message), [map { printXxxTemplate($to_be_replaced{$message}->{$_},$_,'name'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                } else {
                    push( @{$relation_ptr->{'__notes__'}}, listed(unkey($message), [map { printXxxTemplate($to_be_replaced{$message}->{$_},$_,'name'); } @help_array]) );
                }
            }
            foreach my $message ( sort( keys( %to_be_deleted ) ) ) {
                @help_array     = sort( keys( %{$to_be_deleted{$message}} ) );
                $num_of_errors  = scalar( @help_array );
                $ret_val       += $num_of_errors;
                if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                    push( @{$relation_ptr->{'__notes__'}}, listed(unkey($message), [map { printXxxTemplate($to_be_deleted{$message}->{$_},$_,'name'); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
                } else {
                    push( @{$relation_ptr->{'__notes__'}}, listed(unkey($message), [map { printXxxTemplate($to_be_deleted{$message}->{$_},$_,'name'); } @help_array]) );
                }
            }
        }
    }

    return $ret_val;
}


#############################################################################################
#
# for all WAYS  check for completeness of data
# for all NODES  check for completeness of data
#
#############################################################################################

sub CheckCompletenessOfData {
    my $relation_ptr = shift;
    my $ret_val      = 0;

    #
    # for all RELATIONS  check for completeness of data
    #
    if ( $xml_has_relations ) {
        my %incomplete_data_for_relations   = ();
        foreach my $rel_ref ( @{$relation_ptr->{'relation'}} ) {
            if ( $RELATIONS{$rel_ref->{'ref'}} ) {
                ;
            } else {
                $incomplete_data_for_relations{$rel_ref->{'ref'}} = 1;
            }
        }
        if ( keys(%incomplete_data_for_relations) ) {
            my @help_array     = sort(keys(%incomplete_data_for_relations));
            my $num_of_errors  = scalar(@help_array);
               $ret_val       += $num_of_errors;
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed(issue('data.insufficient_relations'), [map { printRelationTemplate($_); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, listed(issue('data.insufficient_relations'), [map { printRelationTemplate($_); } @help_array]) );
            }
            $relation_ptr->{'missing_relation_data'}   = 1;
            printf STDERR "%s Error in input data (%s): insufficient data for relations of route 'ref' = '%s' : %s\n", get_time(), $section, ( $relation_ptr->{'tag'}->{'ref'} ? $relation_ptr->{'tag'}->{'ref'} : 'no ref', jointext( ' ', map { msg("r%s", $_) } @help_array ) );
        }
    }
    #
    # for all WAYS  check for completeness of data
    #
    if ( $xml_has_ways ) {
        my %incomplete_data_for_ways   = ();
        foreach my $highway_ref ( @{$relation_ptr->{'way'}} ) {
            if ( $WAYS{$highway_ref->{'ref'}} ) {
                # way exists in downloaded data
                # check for more
                $incomplete_data_for_ways{$highway_ref->{'ref'}} = 1    if ( !$WAYS{$highway_ref->{'ref'}}->{'tag'} );
                $incomplete_data_for_ways{$highway_ref->{'ref'}} = 1    if ( !$WAYS{$highway_ref->{'ref'}}->{'chain'} || scalar @{$WAYS{$highway_ref->{'ref'}}->{'chain'}} == 0 );
            } else {
                $incomplete_data_for_ways{$highway_ref->{'ref'}} = 1;
            }
        }
        if ( keys(%incomplete_data_for_ways) ) {
            my @help_array     = sort(keys(%incomplete_data_for_ways));
            my $num_of_errors  = scalar(@help_array);
               $ret_val       += $num_of_errors;
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed(issue('data.insufficient_ways'), [map { printWayTemplate($_); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, listed(issue('data.insufficient_ways'), [map { printWayTemplate($_); } @help_array]) );
            }
            $relation_ptr->{'missing_way_data'}   = 1;
            printf STDERR "%s Error in input data (%s): insufficient data for ways of route 'ref' = '%s' : %s\n", get_time(), $section, ( $relation_ptr->{'tag'}->{'ref'} ? $relation_ptr->{'tag'}->{'ref'} : 'no ref', jointext( ' ', map { msg("w%s", $_) } @help_array ) );
        }
    }
    #
    # for all NODES  check for completeness of data
    #
    if ( $xml_has_nodes ) {
        my %incomplete_data_for_nodes   = ();
        foreach my $node_ref ( @{$relation_ptr->{'node'}} ) {
            if ( $NODES{$node_ref->{'ref'}} ) {
                # node exists in downloaded data
                # check for more
                # $incomplete_data_for_nodes{$node_ref->{'ref'}} = 1    if ( !$NODES{$node_ref->{'ref'}}->{'tag'} );
            } else {
                $incomplete_data_for_nodes{$node_ref->{'ref'}} = 1;
            }
        }
        if ( keys(%incomplete_data_for_nodes) ) {
            my @help_array     = sort(keys(%incomplete_data_for_nodes));
            my $num_of_errors  = scalar(@help_array);
               $ret_val       += $num_of_errors;
            if ( $max_error && $max_error > 0 && $num_of_errors > $max_error ) {
                push( @{$relation_ptr->{'__issues__'}}, listed(issue('data.insufficient_nodes'), [map { printNodeTemplate($_); } splice(@help_array,0,$max_error)], ($num_of_errors-$max_error)) );
            } else {
                push( @{$relation_ptr->{'__issues__'}}, listed(issue('data.insufficient_nodes'), [map { printNodeTemplate($_); } @help_array]) );
            }
            $relation_ptr->{'missing_node_data'}   = 1;
            printf STDERR "%s Error in input data (%s): insufficient data for nodes of route 'ref' = '%s' : %s\n", get_time(), $section, ( $relation_ptr->{'tag'}->{'ref'} ? $relation_ptr->{'tag'}->{'ref'} : 'no ref', jointext( ' ', map { msg("n%s", $_) } @help_array ) );
        }
    }

    return $ret_val;
}


#############################################################################################
#
#
#############################################################################################

sub getRelationType {
    my $relation_ptr  = shift;
    my $ret_val       = '';

    if ( $relation_ptr && $relation_ptr->{'tag'} ) {
        if ( $relation_ptr->{'tag'}->{'type'} ) {
            $ret_val = $relation_ptr->{'tag'}->{'type'};
        } else {
            my @found_types = ();
            foreach my $key ( sort( keys(%{$relation_ptr->{'tag'}}) ) ) {
                if ( $key =~ m/type/ ) {
                    push( @found_types, msg( "'%s' = '%s'", $key, $relation_ptr->{'tag'}->{$key} ) );
                }
            }
            $ret_val = jointext( '__separator__', @found_types );
        }
    }

    return $ret_val;
}


#############################################################################################
#
#
#############################################################################################

sub getRelationRouteType {
    my $relation_ptr  = shift;
    my $ret_val       = '';
    my $type          = '';

    if ( $relation_ptr && $relation_ptr->{'tag'} ) {
        if ( $relation_ptr->{'tag'}->{'type'} ) {
            if ( $relation_ptr->{'tag'}->{'type'} =~ m/route_master/ ) {
                $type = 'route_master';
            } elsif ( $relation_ptr->{'tag'}->{'type'} =~ m/route/ ) {
                $type = 'route';
            }
            if ( $type eq $relation_ptr->{'tag'}->{'type'} ) {
                if ( $relation_ptr->{'tag'}->{$relation_ptr->{'tag'}->{'type'}} ) {
                    $ret_val = $relation_ptr->{'tag'}->{$relation_ptr->{'tag'}->{'type'}};
                }
            }
        }
        if ( !$ret_val ) {
            my @found_route_types = ();
            foreach my $key ( sort( keys(%{$relation_ptr->{'tag'}}) ) ) {
                if ( $key =~ m/route/ ) {
                    if ( $key ne 'gtfs:route_id' ) {
                        push( @found_route_types, msg( "'%s' = '%s'", $key, $relation_ptr->{'tag'}->{$key} ) );
                    }
                }
            }
            $ret_val = jointext( '__separator__', @found_route_types );
        }
    }

    return $ret_val;
}


#############################################################################################
#
#
#############################################################################################

sub getGtfsInfos {
    my $relation_ptr  = shift;

    my %gtfs_feed_info = ();
    my @feed_suffix    = ( '' );        # that's the generic one, if keys "gtfs:feed" or "operator:guid" or "network:guid" or option "--gtfs-feed" are used
    my $key;
    my $value;

    my $gtfs_feed         = '';
    my $feed_info_from    = '';
    my $gtfs_release_date = '';
    my $release_date_from = '';
    my @gtfs_infos        = ();


    if ( $relation_ptr && $relation_ptr->{'tag'} ) {
        if ( $relation_ptr->{'tag'}->{'gtfs:feed'} ) {
            $gtfs_feed      = $relation_ptr->{'tag'}->{'gtfs:feed'};
            $feed_info_from = 'gtfs:feed';
        } elsif ( $relation_ptr->{'tag'}->{'operator:guid'} ) {
            $gtfs_feed      = $relation_ptr->{'tag'}->{'operator:guid'};
            $feed_info_from = 'operator:guid';
        } elsif ( $relation_ptr->{'tag'}->{'network:guid'} ) {
            $gtfs_feed      = $relation_ptr->{'tag'}->{'network:guid'};
            $feed_info_from = 'network:guid';
        } elsif ( $opt_gtfs_feed ) {
            $gtfs_feed      = $opt_gtfs_feed;
            $feed_info_from = '--gtfs-feed';
        } else {
            $gtfs_feed      = '__undefined__';
            $feed_info_from = '__undefined__';
        }

        $gtfs_feed_info{'explicit'}->{$gtfs_feed} = $feed_info_from;

        foreach $key ( keys(%{$relation_ptr->{'tag'}}) ) {
            if ( $key =~ m/^gtfs:[rst]/ ) {
                # GTFS feed names always start with ISO two letter code of country in capital letters
                if ( $key =~ m/^gtfs:route_id:([A-Z][A-Z][a-zA-Z0-9_.-]+)$/ ) {
                    $gtfs_feed_info{'implicit'}->{$1} = 1;
                } elsif ( $key =~ m/^gtfs:trip_id:sample:([A-Z][A-Z][a-zA-Z0-9_.-]+)$/ ) {
                    $gtfs_feed_info{'implicit'}->{$1} = 1;
                } elsif ( $key =~ m/^gtfs:trip_id:like:([A-Z][A-Z][a-zA-Z0-9_.-]+)$/ ) {
                    $gtfs_feed_info{'implicit'}->{$1} = 1;
                } elsif ( $key =~ m/^gtfs:trip_id:([A-Z][A-Z][a-zA-Z0-9_.-]+)$/ ) {
                    $gtfs_feed_info{'implicit'}->{$1} = 1;
                } elsif ( $key =~ m/^gtfs:shape_id:([A-Z][A-Z][a-zA-Z0-9_.-]+)$/ ) {
                    $gtfs_feed_info{'implicit'}->{$1} = 1;
                } elsif ( $key =~ m/^gtfs:release_date:([A-Z][A-Z][a-zA-Z0-9_.-]+)$/ ) {
                    $gtfs_feed_info{'implicit'}->{$1} = 1;
                }
            }
        }
        foreach $key ( sort ( keys ( %{$gtfs_feed_info{'implicit'}} ))) {
            push( @feed_suffix, ':'.$key );
        }

        printf STDERR "gtfs_feed_info = %s\n", Data::Dumper::Dumper(\%gtfs_feed_info)   if ( $debug );
        printf STDERR "feed_suffix = %s\n", Data::Dumper::Dumper(\@feed_suffix)   if ( $debug );

        foreach my $feed_suffix ( @feed_suffix ) {
            if ( $feed_suffix ) {
                $gtfs_feed =  $feed_suffix;
                $gtfs_feed =~ s/^://;
            } else {
                $gtfs_feed      = (keys(%{$gtfs_feed_info{'explicit'}}))[0];
                $feed_info_from = $gtfs_feed_info{'explicit'}->{$gtfs_feed};
                if ( $gtfs_feed eq '__undefined__' ) {
                    $gtfs_feed      = '';
                    $feed_info_from = '';
                }
            }
            if ( $relation_ptr->{'tag'}->{'gtfs:release_date'.$feed_suffix} ) {
                $gtfs_release_date = $relation_ptr->{'tag'}->{'gtfs:release_date'.$feed_suffix};
                $release_date_from = 'gtfs:release_date'.$feed_suffix;
            } else {
                $gtfs_release_date = '';
                $release_date_from = '';
            }

            printf STDERR "feed_suffix = %s, gtfs_feed = %s, feed_info_from = %s, release_date = %s, release_date_from = %s\n", $feed_suffix, $gtfs_feed, $feed_info_from, $gtfs_release_date, $release_date_from    if ( $debug );
            my $gtfs_info_created = 0;
            my $last_gtfs_info    = '';
            my $add_gtfs_info     = sub {
                my $info = shift;
                local $Data::Dumper::Sortkeys = 1;
                local $Data::Dumper::Indent   = 0;
                my $this_gtfs_info = Data::Dumper::Dumper( $info );
                if ( $this_gtfs_info ne $last_gtfs_info ) {
                    # do not report same things twice or more times
                    push( @gtfs_infos, $info );
                    $gtfs_info_created++;
                    $last_gtfs_info = $this_gtfs_info;
                }
            };
            if ( $relation_ptr->{'tag'}->{'type'} eq 'route' ) {
                if ( defined($relation_ptr->{'tag'}->{'gtfs:trip_id'.$feed_suffix}) && $relation_ptr->{'tag'}->{'gtfs:trip_id'.$feed_suffix} ne '' ) {
                    $feed_info_from = 'gtfs:trip_id'.$feed_suffix if ( $feed_suffix );
                    printf STDERR "key = %s, value = %s\n", 'gtfs:trip_id'.$feed_suffix, $relation_ptr->{'tag'}->{'gtfs:trip_id'.$feed_suffix}    if ( $debug );
                    $relation_ptr->{'tag'}->{'gtfs:trip_id'.$feed_suffix} =~ s/\s*;\s*/;/g;
                    foreach my $link ( map { GTFS::PtnaSQLite::getGtfsTripIdLink( $gtfs_feed, $gtfs_release_date, $_, undef, 'gtfs:trip_id'.$feed_suffix ); } split ( ';', $relation_ptr->{'tag'}->{'gtfs:trip_id'.$feed_suffix} ) ) {
                        $add_gtfs_info->( gtfsTripInfo( $link, $relation_ptr->{'id'} ) );
                    }
                } elsif ( defined($relation_ptr->{'tag'}->{'gtfs:trip_id:sample'.$feed_suffix}) && $relation_ptr->{'tag'}->{'gtfs:trip_id:sample'.$feed_suffix} ne '' ) {
                    $feed_info_from = 'gtfs:trip_id:sample'.$feed_suffix if ( $feed_suffix );
                    printf STDERR "key = %s, value = %s\n", 'gtfs:trip_id:sample'.$feed_suffix, $relation_ptr->{'tag'}->{'gtfs:trip_id:sample'.$feed_suffix}    if ( $debug );
                    $relation_ptr->{'tag'}->{'gtfs:trip_id:sample'.$feed_suffix} =~ s/\s*;\s*/;/g;
                    foreach my $link ( map { GTFS::PtnaSQLite::getGtfsTripIdLink( $gtfs_feed, $gtfs_release_date, $_, undef, 'gtfs:trip_id:sample'.$feed_suffix ); } split ( ';', $relation_ptr->{'tag'}->{'gtfs:trip_id:sample'.$feed_suffix} ) ) {
                        $add_gtfs_info->( gtfsTripInfo( $link, $relation_ptr->{'id'} ) );
                    }
                } elsif ( defined($relation_ptr->{'tag'}->{'gtfs:shape_id'.$feed_suffix}) && $relation_ptr->{'tag'}->{'gtfs:shape_id'.$feed_suffix} ne '' ) {
                    $feed_info_from = 'gtfs:shape_id'.$feed_suffix if ( $feed_suffix );
                    printf STDERR "key = %s, value = %s\n", 'gtfs:shape_id'.$feed_suffix, $relation_ptr->{'tag'}->{'gtfs:shape_id'.$feed_suffix}    if ( $debug );
                    $relation_ptr->{'tag'}->{'gtfs:shape_id'.$feed_suffix} =~ s/\s*;\s*/;/g;
                    foreach my $link ( map { GTFS::PtnaSQLite::getGtfsShapeIdLink( $gtfs_feed, $gtfs_release_date, $_, undef, 'gtfs:shape_id'.$feed_suffix ); } split ( ';', $relation_ptr->{'tag'}->{'gtfs:shape_id'.$feed_suffix} ) ) {
                        $add_gtfs_info->( { 'link' => $link } );
                    }
                } elsif ( defined($relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix}) && $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix} ne '' ) {
                    $feed_info_from = 'gtfs:route_id'.$feed_suffix if ( $feed_suffix );
                    printf STDERR "key = %s, value = %s\n", 'gtfs:route_id'.$feed_suffix, $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix}    if ( $debug );
                    $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix} =~ s/\s*;\s*/;/g;
                    foreach my $link ( map { GTFS::PtnaSQLite::getGtfsRouteIdLink( $gtfs_feed, $gtfs_release_date, $_, undef, 'gtfs:route_id'.$feed_suffix ); } split ( ';', $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix} ) ) {
                        # we do expect a trip_id or shape_id here, mark that route_id is used here
                        $link->{'route_only'} = JSON::PP::true;
                        $add_gtfs_info->( gtfsRouteInfo( $link, $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix}, $relation_ptr->{'id'}, $gtfs_release_date ) );
                    }
                }
            } elsif ( defined($relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix}) && $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix} ne '' ) {
                $feed_info_from = 'gtfs:route_id'.$feed_suffix if ( $feed_suffix );
                printf STDERR "key = %s, value = %s\n", 'gtfs:route_id'.$feed_suffix, $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix}    if ( $debug );
                $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix} =~ s/\s*;\s*/;/g;
                foreach my $link ( map { GTFS::PtnaSQLite::getGtfsRouteIdLink( $gtfs_feed, $gtfs_release_date, $_, undef, 'gtfs:route_id'.$feed_suffix ); } split ( ';', $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix} ) ) {
                    $add_gtfs_info->( gtfsRouteInfo( $link, $relation_ptr->{'tag'}->{'gtfs:route_id'.$feed_suffix}, $relation_ptr->{'id'}, $gtfs_release_date ) );
                }
            }
            if ( $gtfs_info_created ) {
                my $gf  = $gtfs_feed         ? $gtfs_feed         : ' empty ';
                my $fif = $feed_info_from    ? $feed_info_from    : ' empty ';
                my $grd = $gtfs_release_date ? $gtfs_release_date : ' latest ';
                my $rdf = $release_date_from ? $release_date_from : ' empty ';
                $gtfs_relation_info_from{$gf}{$fif}{$grd}{$rdf}{$relation_ptr->{'id'}} = 1;
            }
        }
    }

    return @gtfs_infos;
}


#############################################################################################
#
# GTFS information: { 'link' => data of the link to the GTFS object, 'compare' => data of the comparison with the OSM relation }
#
#############################################################################################

sub gtfsLinkIsBad {
    my $link = shift;

    return ( $link->{'status'} =~ m/^(?:missing|no_shapes|no_id|no_db|no_feed)$/ ) ? 1 : 0;
}


sub gtfsCompare {
    my ( $what, $feed, $release_date, $id, $relation_id ) = @_;

    return { 'what' => $what, 'feed' => $feed, 'release_date' => $release_date, 'id' => $id, 'relation' => $relation_id };
}


sub gtfsTripInfo {
    my ( $link, $relation_id ) = @_;
    my $info = { 'link' => $link };

    if ( $relation_id && !gtfsLinkIsBad( $link ) ) {
        $info->{'compare'} = gtfsCompare( 'trip', $link->{'feed'}, $link->{'release_date'}, $link->{'id'}, $relation_id );
    }
    return $info;
}


sub gtfsRouteInfo {
    my ( $link, $route_ids, $relation_id, $release_date ) = @_;
    my $info = { 'link' => $link };

    if ( !gtfsLinkIsBad( $link ) && ( $route_ids !~ m/;/ || $link->{'status'} ne 'previous' ) && defined($route_ids) && $route_ids ne '' && $relation_id ) {
        $info->{'compare'} = gtfsCompare( 'route', $link->{'feed'}, ( $link->{'status'} eq 'previous' ) ? 'previous' : $release_date, $route_ids, $relation_id );
    }
    return $info;
}


sub gtfsInfoMsg {
    my $info = shift;

    return $info->{'compare'} ? gtfs_msg( $info->{'link'} ) . gtfs_compare_msg( $info->{'compare'} ) : gtfs_msg( $info->{'link'} );
}


#############################################################################################
#
# functions for building the document which is handed over to the output renderer
#
# nothing in here knows anything about HTML (or any other output format), see
# modules/PtnaOutput/Html.pm for the description of the document and for the rendering
#
#############################################################################################

my %DOCUMENT                    = ( 'meta' => {}, 'routes' => [] );
my $no_of_columns               = 0;
my @columns                     = ();
my @paragraph_lines             = ();                   # lines of the paragraph which is currently being collected by printText()
my $paragraph_open              = 0;
my $current_table               = undef;
my $current_blocks              = undef;                # (the routes list if not set) receives the blocks (paragraphs, lists, tables)
my $current_topic               = undef;
my $current_tables              = 0;                    # the blocks of the topic are tables without 'type'
my %id_markers                  = ();                   # printTableSubHeader() auto-generates id='' strings based on 'route_type' and 'ref'; they may appear multiple times


sub addNode {
    my $node = shift;
    $current_blocks = $DOCUMENT{'routes'} //= []    unless ( $current_blocks );
    push( @{$current_blocks}, $node );
    return $node;
}


#############################################################################################

sub printInitialHeader {
    my $title       = shift;
    my $osm_base    = shift;
    my $areas       = shift;

    $no_of_columns  = 0;
    @columns        = ();

    $DOCUMENT{'meta'}->{'title'}     = $title       if ( defined( $title ) );
    $DOCUMENT{'meta'}->{'osm_base'}  = $osm_base    if ( $osm_base );
    $DOCUMENT{'meta'}->{'areas'}     = $areas       if ( $areas );

}


#############################################################################################

sub printFinalFooter {

    flushParagraph();

    PtnaOutput::Html::init( 'language'            => $opt_language,
                            'test'                => $opt_test,
                            'coloured_sketchline' => $coloured_sketchline,
                            'debug'               => $debug,
                            'labels'              => \%column_name,
                            'colours'             => \%colour_table,
                            'no_additional_navigation' => $no_additional_navigation,
                          );
    PtnaOutput::Json::write_file( \%DOCUMENT, $opt_json_file )     if ( $opt_json_file );
    PtnaOutput::Html::render( \%DOCUMENT );
}


#############################################################################################

sub flushParagraph {

    if ( $paragraph_open ) {
        addNode( { 'type' => 'paragraph', 'markup' => 'wiki', 'loose' => JSON::PP::true, 'lines' => [ @paragraph_lines ] } );
        @paragraph_lines = ();
        $paragraph_open  = 0;
    }
}


#############################################################################################

sub addList {
    return addNode( { 'type' => 'list', 'items' => [ @_ ] } );
}


#############################################################################################

sub listItem {
    my $text     = shift;
    my @children = @_;
    return { 'text' => $text, 'children' => [ @children ] };
}


#############################################################################################

#############################################################################################

sub printHintSuspiciousRelations {
    my $hswkort = scalar( keys ( %have_seen_well_known_other_route_types ) );
    my $hswknt  = scalar( keys ( %have_seen_well_known_network_types ) );
    my $hswkot  = scalar( keys ( %have_seen_well_known_other_types ) );

    if ( $hswkort || $hswknt || $hswkot ) {
        my @items = ();
        if ( $hswkort ) {
            push( @items, listItem( "'type' = 'route_master', 'type' = 'route'",
                                    map { listItem( msg( "'route_master' = '%s', 'route' = '%s'", $_, $_ ) ); } sort ( keys %have_seen_well_known_other_route_types ) ) );
        }
        if ( $hswknt ) {
            push( @items, listItem( "'type' = 'network'",
                                    map { listItem( msg( "'network' = '%s'", $_ ) ); } sort ( keys %have_seen_well_known_network_types ) ) );
        }
        if ( $hswkot ) {
            push( @items, map { listItem( msg( "'type' = '%s'", $_ ) ); } sort ( keys %have_seen_well_known_other_types ) );
        }
        addList( @items );
    }
}


#############################################################################################

sub printHintNetworks {

    if ( $network_long_regex || $network_short_regex ) {
        my @items = ();
        push( @items, map { listItem( foreign($_) ); } split( '\|', $network_long_regex  ) )     if ( $network_long_regex  );
        push( @items, map { listItem( foreign($_) ); } split( '\|', $network_short_regex ) )     if ( $network_short_regex );
        push( @items, listItem( gettext("'network' is not set") ) )                                     if ( !$strict_network );
        addList( @items );
    }

    if ( $operator_regex ) {
        my @items = map { listItem( foreign($_) ); } split( '\|', $operator_regex );
        push( @items, listItem( gettext("'operator' is not set") ) )                                    if ( !$strict_operator );
        addList( @items );
    }
}


#############################################################################################
#
# one line of a table with 'number' and 'relations' columns:
# at most 10 relations are listed, the rest is hidden behind "and more ..."
#
#############################################################################################

sub printTableLineOfRelations {
    my $column      = shift;
    my $value       = shift;
    my @relations   = @_;

    $value = ''     if ( $value eq '__unset_network__' || $value eq '__unset_operator__' );

    if ( scalar @relations <= 10 ) {
        printTableLine( $column     =>  $value,
                        'number'    =>  scalar @relations,
                        'relations' =>  jointext( ',', @relations )
                      );
    } else {
        printTableLine( $column     =>  $value,
                        'number'    =>  scalar @relations,
                        'relations' =>  jointext( ',', splice( @relations, 0, 10 ) ),
                        'and more'  =>  1
                      );
    }
}


#############################################################################################

sub printHintUsedNetworks {

    my @relations_of_network  = ();

    foreach my $network ( sort( keys( %used_networks ) ) ) {
        push( @relations_of_network, keys( %{$used_networks{$network}} ) );
    }

    if ( scalar @relations_of_network > 0 ) {
        printTopic( 'considerednetworks', 1 );

        printTableInitialization( 'network', 'number', 'relations' );
        printTableHeader();
        foreach my $network ( sort( keys( %used_networks ) ) ) {
            printTableLineOfRelations( 'network', $network, sort( keys( %{$used_networks{$network}} ) ) );
        }
        printTableFooter();

        if ( scalar keys (%unused_operators) ) {
            printTableInitialization( 'operator', 'number', 'relations' );
            printTableHeader();
            foreach my $operator ( sort( keys( %unused_operators ) ) ) {
                # the limit of 10 has always been checked against the relations of the networks above
                my @relations_of_operator = sort( keys( %{$unused_operators{$operator}} ) );
                my @limited               = ( scalar @relations_of_network <= 10 ) ? @relations_of_operator : splice( @relations_of_operator, 0, 10 );
                my %line                  = ( 'operator'  => ( $operator eq '__unset_operator__' ? '' : $operator ),
                                              'number'    => scalar( keys( %{$unused_operators{$operator}} ) ),
                                              'relations' => jointext( ',', @limited ) );
                $line{'and more'}         = 1     if ( scalar @relations_of_network > 10 );
                printTableLine( %line );
            }
            printTableFooter();
        }
    }
}


#############################################################################################

sub printHintAddedNetworks {

    my @relations_of_network  = ();

    foreach my $network ( sort( keys( %added_networks ) ) ) {
        push( @relations_of_network, keys( %{$added_networks{$network}} ) );
    }

    if ( scalar @relations_of_network > 0 ) {
        printTopic( 'addednetworks', 1 );

        printTableInitialization( 'network', 'number', 'relations' );
        printTableHeader();
        foreach my $network ( sort( keys( %added_networks ) ) ) {
            printTableLineOfRelations( 'network', $network, sort( keys( %{$added_networks{$network}} ) ) );
        }
        printTableFooter();
    }
}


#############################################################################################

sub printHintUnusedNetworks {

    my @relations_of_network = ();

    foreach my $network ( sort( keys( %unused_networks ) ) ) {
        push( @relations_of_network, keys( %{$unused_networks{$network}} ) );
    }

    if ( scalar @relations_of_network > 0 ) {
        printTopic( 'notconsiderednetworks' );

        printTableInitialization( 'network', 'number', 'relations' );
        printTableHeader();
        foreach my $network ( sort( keys( %unused_networks ) ) ) {
            printTableLineOfRelations( 'network', $network, sort( keys( %{$unused_networks{$network}} ) ) );
        }
        printTableFooter();
    }
}


#############################################################################################

sub printHintSeenOperators {

    my @relations_of_operator = ();

    foreach my $operator ( sort( keys( %seen_operators ) ) ) {
        push( @relations_of_operator, keys( %{$seen_operators{$operator}} ) );
    }

    if ( scalar @relations_of_operator > 0 ) {
        printTableInitialization( 'operator', 'number', 'relations' );
        printTableHeader();
        foreach my $operator ( sort( keys( %seen_operators ) ) ) {
            printTableLineOfRelations( 'operator', $operator, sort( keys( %{$seen_operators{$operator}} ) ) );
        }
        printTableFooter();
    }
}


#############################################################################################

sub printGtfsReferences {

    if ( scalar(keys(%gtfs_csv_info_from)) ) {
        printTopic( 'gtfsreferences_csv' );

        printTableInitialization( 'gtfs_feed', 'date' );
        printTableHeader();
        foreach my $gtfs_feed ( sort( keys( %gtfs_csv_info_from ) ) ) {
            foreach my $gtfs_release_date (  sort( keys( %{$gtfs_csv_info_from{$gtfs_feed}} ) ) ) {
                $gtfs_release_date =~ s/ latest //;
                printTableLine( 'gtfs_feed'    =>  $gtfs_feed,
                                'date'         =>  $gtfs_release_date
                              );
            }
        }
        printTableFooter();
    }

    if ( scalar(keys(%gtfs_relation_info_from)) ) {

        my @relations_of_feed = ();

        printTopic( 'gtfsreferences_relations' );

        printTableInitialization( 'gtfs_feed', 'feed_from', 'date', 'date_from', 'number', 'relations' );
        printTableHeader();
        foreach my $gtfs_feed ( sort( keys( %gtfs_relation_info_from ) ) ) {
            my $gf  = $gtfs_feed;
               $gf  =~ s/ empty //;
            foreach my $feed_from ( sort( keys( %{$gtfs_relation_info_from{$gtfs_feed}} ) ) ) {
                my $ff  = $feed_from;
                   $ff  =~ s/ empty //;
                foreach my $gtfs_release_date ( sort( keys( %{$gtfs_relation_info_from{$gtfs_feed}{$feed_from}} ) ) ) {
                    my $grd = $gtfs_release_date;
                       $grd =~ s/ latest //;
                    foreach my $date_from ( sort( keys( %{$gtfs_relation_info_from{$gtfs_feed}{$feed_from}{$gtfs_release_date}} ) ) ) {
                        my $df  = $date_from;
                           $df  =~ s/ empty //;
                        @relations_of_feed    = sort( keys( %{$gtfs_relation_info_from{$gtfs_feed}{$feed_from}{$gtfs_release_date}{$date_from}} ) );
                        my %line = ( 'gtfs_feed' =>  $gf,
                                     'feed_from' =>  $ff,
                                     'date'      =>  $grd,
                                     'date_from' =>  $df,
                                     'number'    =>  scalar @relations_of_feed,
                                   );
                        if ( scalar @relations_of_feed <= 10 ) {
                            $line{'relations'} = jointext( ',', @relations_of_feed );
                        } else {
                            $line{'relations'} = jointext( ',', splice(@relations_of_feed,0,10) );
                            $line{'and more'}  = 1;
                        }
                        printTableLine( %line );
                    }
                }
            }
        }
        printTableFooter();
    }
}


#############################################################################################

sub printConditionalAccessOnWays {

    printTableInitialization( 'conditional_access', 'ways', 'relations' );
    printTableHeader();
    foreach my $access_restriction ( sort( keys( %conditional_access ) ) ) {
        printTableLine( 'conditional_access' =>  $access_restriction,
                        'ways'               =>  jointext( ',', sort( keys( %{$conditional_access{$access_restriction}->{'ways'}} ) ) ),
                        'relations'          =>  jointext( ',', sort( keys( %{$conditional_access{$access_restriction}->{'relations'}} ) ) )
                      );
    }
    printTableFooter();

}


#############################################################################################

sub printExcludedRelations {

    printTableInitialization( 'key', 'value', 'number', 'relations' );
    printTableHeader();
    foreach my $key ( sort( keys( %excluded_key_value_relations ) ) ) {
        foreach my $value ( sort( keys( %{$excluded_key_value_relations{$key}} ))) {
            printTableLine( 'key'       =>  $key,
                            'value'     =>  $value,
                            'number'    =>  scalar(keys( %{$excluded_key_value_relations{$key}{$value}})),
                            'relations' =>  jointext( ',', sort( keys( %{$excluded_key_value_relations{$key}{$value}} ) ) )
                          );
        }
    }
    printTableFooter();

}


#############################################################################################

# a header of the routes list (free text), it is part of the list of the routes
sub printHeader {
    my $text  = shift;
    my $level = shift || 1;

    flushParagraph();

    $level = 1   if ( $level < 1 );
    $level = 6   if ( $level > 6 );

    printf STDERR "%s %s %s\n", get_time(), $level, $text    if ( $verbose && $text );

    addNode( { 'type' => 'header', 'level' => $level, 'text' => $text } );
}


# the following blocks belong to the collection of the topic, the renderer decides title and place
sub printTopic {
    my $topic  = shift;
    my $tables = shift;     # the topic is just a list of tables

    flushParagraph();

    printf STDERR "%s %s\n", get_time(), $topic    if ( $verbose );

    $current_topic  = $topic;
    $current_tables = $tables;
    $current_blocks = $tables ? ( $DOCUMENT{$topic} = [] ) : ( $DOCUMENT{$topic}->{'content'} = [] );
}


# the following blocks belong to the routes list again
sub printRoutesList {
    flushParagraph();
    $current_tables = 0;
    $current_blocks = $DOCUMENT{'routes'} //= [];
}


# the following blocks belong to the lines of the route type of the current topic
sub printRouteType {
    my $route_type = shift;

    flushParagraph();

    $current_tables = 0;
    $current_blocks = $DOCUMENT{$current_topic}->{'route_types'}->{$route_type} = [];
}


#############################################################################################

sub printText {
    my $text = shift;

    $paragraph_open = 1;

    if ( $text ) {
        push( @paragraph_lines, $text );
    } else {
        flushParagraph();
    }
}


#############################################################################################

sub printFooter {
    ;
}


#############################################################################################

sub printTableInitialization
{
    $no_of_columns = scalar( @_ );
    @columns       = ( @_ );
}


#############################################################################################

sub printTableHeader {
    flushParagraph();

    if ( scalar(@columns) ) {
        $current_table = addNode( { ( $current_tables ? () : ( 'type' => 'table' ) ), 'columns' => [ @columns ], 'rows' => [] } );
    }
}


#############################################################################################

sub printTableSubHeader {
    my %hash                = ( @_ );
    my $ref                 = defined($hash{'ref'}) ? $hash{'ref'} : '';
    my $ref_or_list         = $hash{'ref-or-list'};
    my $network             = $hash{'network'}       || '';
    my $relation_id         = $hash{'relation'}      || '';
    my $operator            = $hash{'operator'}      || '';
    my $pt_type             = $hash{'pt_type'}       || '';
    my $colour              = $hash{'colour'}        || '';
    my $text_colour         = $hash{'colour:text'}   || '';
    my $gtfs_text           = '';       # GTFS information comming from the CSV input file
    my @ref_or_array        = ();
    my $nav_label           = undef;

    if ( $ref_or_list ) {
        @ref_or_array = @{$ref_or_list};
    } elsif ( $ref ne '' ) {
        push( @ref_or_array, $ref );
    }

    printf STDERR "printTableSubHeader(): ref_or_list_text = '%s'\n", jointext(' ', @ref_or_array )    if ( $debug );

    if ( scalar @ref_or_array && $pt_type ) {
        my $id_label  = msg( "%s_%s", $pt_type, jointext('_', @ref_or_array ) );
           $id_label  =~ s/[^0-9A-Za-z_.-]/_/g;                                # other characters are not allowed in 'id'
        if ( $id_markers{$id_label} ) {                                        # if the same combination appears more than one, add a number as suffix (e.g. "Bus A" of VMS in Saxony, Germany
            $id_markers{$id_label}++;
            $nav_label = msg( "%s-%d", $id_label, $id_markers{$id_label} );
        } else {
            $id_markers{$id_label} = 1;
            $nav_label = $id_label;
        }
    }

    if ( $hash{'GTFS-Feed'} && $hash{'GTFS-Route-Id'} ) {
        my $release_date = $hash{'GTFS-Release-Date'} || '';
        if ( $release_date ) {
            printf STDERR "printTableSubHeader(1): \$gtfs_csv_info_from{$hash{'GTFS-Feed'}}{$hash{'GTFS-Release-Date'}} = 1;\n" if ( $debug );
            $gtfs_csv_info_from{$hash{'GTFS-Feed'}}{$hash{'GTFS-Release-Date'}} = 1;
        } else {
            printf STDERR "printTableSubHeader(1): \$gtfs_csv_info_from{$hash{'GTFS-Feed'}}{' latest } = 1;\n" if ( $debug );
            $gtfs_csv_info_from{$hash{'GTFS-Feed'}}{' latest '} = 1;
        }
        my @links = map { GTFS::PtnaSQLite::getGtfsRouteIdLink( $hash{'GTFS-Feed'}, $release_date, $_, $relation_id, 'GTFS-Route-Id' ); } split( ';', $hash{'GTFS-Route-Id'} );
        $gtfs_text .= jointext( ', ', map { gtfs_msg( $_ ); } @links );
        if ( !grep { gtfsLinkIsBad( $_ ); } @links ) {
            my $any_previous = grep { $_->{'status'} eq 'previous'; } @links;
            if ( $hash{'GTFS-Route-Id'} !~ m/;/ || !$any_previous ) {
                my $grd = $any_previous ? 'previous' : $release_date;
                $gtfs_text .= gtfs_compare_msg( gtfsCompare( 'route', $hash{'GTFS-Feed'}, $grd, $hash{'GTFS-Route-Id'}, $relation_id ) )    if ( $relation_id );
            }
        }
        if ( $hash{'GTFS-Scores'} ) {
            $gtfs_text .= ', ' . gtfs_scores_msg( $hash{'GTFS-Scores'} );
        }
    } else {
        if ( $hash{'GTFS-Feed'} ) {
            if ( $hash{'GTFS-Release-Date'} ) {
                printf STDERR "printTableSubHeader(2): \$gtfs_csv_info_from{$hash{'GTFS-Feed'}}{$hash{'GTFS-Release-Date'}} = 1;\n" if ( $debug );
                $gtfs_csv_info_from{$hash{'GTFS-Feed'}}{$hash{'GTFS-Release-Date'}} = 1;
                $gtfs_text .= gtfs_msg( GTFS::PtnaSQLite::getGtfsRouteIdLink( $hash{'GTFS-Feed'}, $hash{'GTFS-Release-Date'}, '', $relation_id, 'GTFS-Route-Id' ) );
            } else {
                printf STDERR "printTableSubHeader(2): \$gtfs_csv_info_from{$hash{'GTFS-Feed'}}{' latest } = 1;\n" if ( $debug );
                $gtfs_csv_info_from{$hash{'GTFS-Feed'}}{' latest '} = 1;
                $gtfs_text .= gtfs_msg( GTFS::PtnaSQLite::getGtfsRouteIdLink( $hash{'GTFS-Feed'}, '', '', $relation_id, 'GTFS-Route-Id' ) );
            }
        } elsif ( $hash{'GTFS-Route-Id'} ) {
            $gtfs_text .= jointext( ', ', map { msg( "%s: %s; ", ( $column_name{'GTFS-Route-Id'} ? $column_name{'GTFS-Route-Id'} : 'GTFS-Route-Id' ), foreign($_) ); } split( ';', $hash{'GTFS-Route-Id'} ) );
        }
    }

    if ( $current_table ) {
        push( @{$current_table->{'rows'}}, { 'type'        => 'subheader',
                                             'refs'        => [ @ref_or_array ],
                                             'network'     => $network,
                                             'operator'    => $operator,
                                             'pt_type'     => $pt_type,
                                             'colour'      => $colour,
                                             'text_colour' => $text_colour,
                                             ( defined( $nav_label ) ? ( 'id' => $nav_label ) : () ),
                                             'csv'         => { 'gtfs' => $gtfs_text,
                                                                map { defined( $hash{$_->[0]} ) ? ( $_->[1] => $hash{$_->[0]} ) : (); }
                                                                    ( [ 'CSV-Comment', 'comment' ], [ 'CSV-From', 'from' ], [ 'CSV-To', 'to' ], [ 'CSV-Operator', 'operator' ] )
                                                              },
                                           } );
    }
}


#############################################################################################

sub printTableLine {
    my %hash        = ( @_ );
    my $ref         = $hash{'ref'} || '???';
    my $info        = $hash{'relation'} ? $hash{'relation'}       : ( $hash{'network'} ? $hash{'network'} : $ref);
    my %cells       = ();

    if ( !$hash{'relation'} && $hash{'gtfs_feed'} ) {
        $info = 'GTFS';
        if ( $hash{'date'} ) {
            $ref  = $hash{'gtfs_feed'} . '-' . $hash{'date'};
        } else {
            $ref  = $hash{'gtfs_feed'};
        }
    }

    $info =~ s/\"/_/g;

    # empty cells are not part of the data, the renderer knows how to display them
    foreach my $column ( @columns ) {
        my $val = ($column && defined($hash{$column})) ? $hash{$column} : '';
        if ( $column eq "relation" ) {
            $cells{$column} = { 'id' => $val, 'link' => relationLink( $val ) }     if ( $val );
        } elsif ( $column eq "relations" ) {
            $cells{$column} = { 'links' => [ map { relationLink( $_, 'ref' ); } split( ',', $val ) ], ($hash{'and more'} ? ( 'truncated' => JSON::PP::true ) : ()) }     if ( $val ne '' );
        } elsif ( $column eq "ways" ) {
            $cells{$column} = { 'links' => [ map { wayLink( $_, 'name;ref' ); } split( ',', $val ) ], ($hash{'and more'} ? ( 'truncated' => JSON::PP::true ) : ()) }     if ( $val ne '' );
        } elsif ( $column eq "issues" || $column eq "notes" ) {
            my @lines = ref($val) eq 'ARRAY' ? @{$val} : split( /__separator__/, $val, -1 );
            $cells{$column} = \@lines     if ( scalar(@lines) );
        } elsif ( $column eq "gtfs_feed" ) {
            $cells{$column} = GTFS::PtnaSQLite::getGtfsLinkToRoutes( $hash{'gtfs_feed'}, $hash{'date'} );
        } elsif ( $column eq "type" || $column eq "route_type" ) {
            my @lines = split( /__separator__/, $val, -1 );
            $cells{$column} = \@lines     if ( scalar(@lines) );
        } else {
            $cells{$column} = $val     if ( ref($val) || $val ne '' );
        }
    }

    if ( $current_table ) {
        push( @{$current_table->{'rows'}}, { 'type' => 'line', 'info' => $info, 'ref' => $ref, 'cells' => \%cells } );
    }
}


#############################################################################################

sub printTableFooter {

    $current_table = undef;
}


#############################################################################################
#
# descriptions of OSM objects, they are turned into links by the output renderer
#
#############################################################################################

sub relationLink {
    my $rel_id  = shift;
    my $tags    = shift;
    my $link    = { 'id' => $rel_id };

    if ( $rel_id ) {
        my $rel = $RELATIONS{$rel_id};
        if ( $tags && $rel && $rel->{'tag'} ) {
            foreach my $tag ( split( ';', $tags ) ) {
                if ( exists($rel->{'tag'}->{$tag})  &&
                     defined($rel->{'tag'}->{$tag}) &&
                     $rel->{'tag'}->{$tag} ne ''        ) {
                    $link->{'label'} = $rel->{'tag'}->{$tag};
                    last;
                }
            }
        }
        if ( $rel ) {
            foreach my $key ( [ 'relatify', 'relatify_relation' ], [ 'show', 'show_relation' ], [ 'unroll', 'unroll_relation' ], [ 'gtfs_tag', 'GTFS-HTML-TAG' ] ) {
                next    unless ( defined( $rel->{$key->[1]} ) );
                $link->{$key->[0]} = ( $key->[0] eq 'gtfs_tag' ) ? $rel->{$key->[1]} : ( $rel->{$key->[1]} ? JSON::PP::true : JSON::PP::false );
            }
        }
    }

    return $link;
}


#############################################################################################

sub objectLink {
    my $objects = shift;
    my $id      = shift;
    my $tags    = shift;
    my $link    = { 'id' => $id };

    if ( $id && $tags ) {
        foreach my $tag ( split( ';', $tags ) ) {
            if ( $objects->{$id} && $objects->{$id}->{'tag'} && $objects->{$id}->{'tag'}->{$tag} ) {
                $link->{'label'} = $objects->{$id}->{'tag'}->{$tag};
                last;
            }
        }
    }

    return $link;
}


#############################################################################################

sub wayLink {
    return objectLink( \%WAYS, @_ );
}


#############################################################################################

sub printXxxTemplate {
    my $node_or_way_or_relation  = shift;
    my $val                      = $_[0];

    if ( $val ) {
        if ( $node_or_way_or_relation ) {
            if ( $node_or_way_or_relation eq 'node' ) {
                $val = printNodeTemplate( @_ );
            } elsif ( $node_or_way_or_relation eq 'way' ) {
                $val = printWayTemplate( @_ );
            } elsif ( $node_or_way_or_relation eq 'relation' ) {
                $val = printRelationTemplate( @_ );
            }
        }
    } else {
        $val = '';
    }

    return $val;
}


#############################################################################################

sub printRelationTemplate {
    return $_[0] ? relation_msg( relationLink( @_ ) ) : '';
}


#############################################################################################

sub printWayTemplate {
    return $_[0] ? way_msg( wayLink( @_ ) ) : '';
}


#############################################################################################

sub printNodeTemplate {
    return $_[0] ? node_msg( objectLink( \%NODES, @_ ) ) : '';
}


#############################################################################################

sub printRelationInjectData {
    my $relation_id            = shift;
    my @array_of_key_and_value = @_;
    my $val                    = '';

    if ( $relation_id && $RELATIONS{$relation_id} && scalar(@array_of_key_and_value) > 0 ) {
        printf STDERR ( "printRelationInjectData(%s, ...)\n", $relation_id )    if ( $debug );
        $val = inject_msg( $relation_id, @array_of_key_and_value );
    }

    return $val;
}


#############################################################################################

#############################################################################################

sub ctrl_escape {
    my $text = shift;
    if ( $text ) {
        $text =~ s/\t/<tab>/g;
        $text =~ s/\r/<cr>/g;
        $text =~ s/\n/<lf>/g;
        $text =~ s/ /<blank>/g;
    }
    return text_msg($text);
}


#############################################################################################

sub GetColourFromString {

    my $string      = shift;
    my $ret_value   = undef;

    if ( $string ) {
        $string = lc( $string );
        if ( $string =~ m/^#[a-f0-9]{6}$/ ) {
            $ret_value= $string;
        } elsif ( $string =~ m/^#([a-f0-9])([a-f0-9])([a-f0-9])$/ ) {
            $ret_value= lc("#" . $1 . $1 . $2 . $2 . $3 . $3);
        } else {
            $ret_value = ( $colour_table{$string} ) ? lc($colour_table{$string}) : undef;
        }
    }
    return $ret_value;
}


#############################################################################################

sub get_time {

    my ($sec,$min,$hour,$day,$month,$year) = localtime();

    return msg( "%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $month+1, $day, $hour, $min, $sec );
}
