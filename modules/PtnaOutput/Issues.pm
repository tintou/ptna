#
#   Catalog of all issues and notes reported by ptna-routes.pl
#
#   issue( 'codename', [ count, ] args ... )   creates an issue; the count is only for entries with a plural form.
#
#   Each entry has a stable codename, which is what the analysis stores in its data
#   (see PtnaOutput::Msg::issue_msg). The renderers look the codename up here:
#     the HTML renderer translates it, a data renderer can emit the codename itself.
#
#   Entry:  'codename' => [ 'issues' | 'notes' | 'detail', gettext( "msgid" ) ]
#       or  'codename' => [ 'issues' | 'notes', ngettext( "msgid", "plural", 1 ) ]    (count is given by the caller)
#       or  'codename' => [ 'issues' | 'notes', "format" ]         (not translated: data like "'network' = '%s'")
#
#   Codenames are part of the machine-readable output: do not rename them.
#

package PtnaOutput::Issues;

use strict;
use warnings;

use Exporter 'import';
use utf8;

use PtnaOutput::Msg qw( gettext ngettext issue_msg );

our @EXPORT_OK = qw( issue note detail entry codes );

my %CATALOG = (
    'note.tag_value'                        => [ 'notes',  "'%s' = '%s'" ],
    'note.network_equal'                    => [ 'notes',  "'network' = '%s'" ],
    'note.network_similar'                  => [ 'notes',  "'network' ~ '%s'" ],
    'note.network_long_equal'               => [ 'notes',  "'network:long' = '%s'" ],
    'tag.value_issue'                       => [ 'issues', "'%s' = '%s': %s" ],
    'master.members_with_role_list'         => [ 'issues', "%s: 'role' = %s'." ],
    'route.see_conditional'                 => [ 'notes',  "%s %s" ],
    'gtfs.problem'                          => [ 'issues', "%s" ],
    'access.barrier_implied_no'             => [ 'detail', gettext( "'barrier'='%s' with implied 'access'='no'" ) ],
    'way.wrong_value'                       => [ 'detail', gettext( "wrong value: '%s' = '%s'" ) ],
    'way.missing_key'                       => [ 'detail', gettext( "missing key: '%s'" ) ],
    'way.suspicious_sub_type'               => [ 'detail', gettext( "suspicious sub-type: '%s'='%s'" ) ],
    'csv.gtfs_feed_wrong'                   => [ 'issues', gettext( "CSV data: field 'gtfs_feed' (= '%s') is wrong. Line %s of Routes-Data. Contents: '%s'" ) ],
    'csv.release_date_wrong'                => [ 'issues', gettext( "CSV data: field 'release_date' (= '%s') is wrong. Should be a date (YYYY-MM-DD), 'latest', 'previous' or 'long-term'. Line %s of Routes-Data. Contents: '%s'" ) ],
    'csv.first_char_reserved'               => [ 'issues', gettext( "First character of line ('%s') is reserved. Please put the first CSV field into double quotes (\"...\"). Line %s of Routes-Data. Contents: '%s'" ) ],
    'csv.errors'                            => [ 'issues', gettext( "CSV data includes errors. Line %s of Routes-Data. Contents: '%s'" ) ],
    'csv.route_type_unsupported'            => [ 'issues', gettext( "Route-Type is not supported: '%s'. Line %s of Routes-Data. Contents: '%s'" ) ],
    'csv.route_type_not_set'                => [ 'issues', gettext( "Route-Type is not set. Line %s of Routes-Data. Contents: '%s'" ) ],
    'csv.route_ref_not_set'                 => [ 'issues', gettext( "Route-Ref is not set. Line %s of Routes-Data. Contents: '%s'" ) ],
    'tag.comma_separator'                   => [ 'notes', gettext( "'%s' = '%s': ',' (comma) as separator value should be replaced by ';' (semi-colon) without blank" ) ],
    'gtfs.deprecated_key'                   => [ 'issues', gettext( "Deprecated GTFS key '%s'. For valid key names, see the %s" ) ],
    'data.insufficient_nodes'               => [ 'issues', gettext( "Error in input data: insufficient data for nodes" ) ],
    'data.insufficient_relations'           => [ 'issues', gettext( "Error in input data: insufficient data for relations" ) ],
    'data.insufficient_ways'                => [ 'issues', gettext( "Error in input data: insufficient data for ways" ) ],
    'data.insufficient_nodes_dist'          => [ 'issues', gettext( "Error in input data: insufficient data for nodes: %s, %s" ) ],
    'data.insufficient_ways_dist'           => [ 'issues', gettext( "Error in input data: insufficient data for ways: %s, %s" ) ],
    'data.insufficient_relations_dist'      => [ 'issues', gettext( "Error in input data: insufficient data for relations: %s, %s" ) ],
    'colour.missing_hash'                   => [ 'issues', gettext( "'%s' has unknown value '%s'. Add '#' as first character." ) ],
    'colour.unknown_value'                  => [ 'issues', gettext( "'%s' has unknown value '%s'. Choose one of the 140 well defined HTML/CSS colour names or the HTML Hex colour codes '#...' or '#......'." ) ],
    'gtfs.invalid_feed_code'                => [ 'issues', gettext( "Invalid GTFS feed code ('%s') in GTFS key '%s'. For valid feed codes, see the %s" ) ],
    'gtfs.invalid_key'                      => [ 'issues', gettext( "Invalid GTFS key '%s'. For valid key names, see the %s" ) ],
    'gtfs.key_has_feed_suffix'              => [ 'issues', gettext( "Invalid GTFS key '%s'. This key must not have any feed code as suffix." ) ],
    'tag.missing_alternatives'              => [ 'notes', gettext( "'%s' = '%s' is set but neither '%s' nor '%s' is set: consider setting one of them as they provide additional information about stops (their names, sequence and locations)." ) ],
    'route.not_in_data_ref'                 => [ 'issues', gettext( "Missing route for 'ref'='%s' and 'route'='%s'" ) ],
    'gtfs.mixed_feed_suffix'                => [ 'issues', gettext( "Mixed use of GTFS keys with and without feed code as suffix. E.g.: '%s' and '%s'." ) ],
    'route.multiple_no_master'              => [ 'issues', gettext( "Multiple Routes but no Route-Master" ) ],
    'route.multiple_no_ptv2'                => [ 'issues', gettext( "Multiple Routes but 'public_transport:version' is not set to '2'" ) ],
    'route.multiple_not_in_master'          => [ 'issues', gettext( "Multiple Routes but this Route is not a member of any Route-Master" ) ],
    'name.not_set'                          => [ 'issues', gettext( "'name' is not set" ) ],
    'network.long_form_set'                 => [ 'notes', gettext( "'network:long' is long form" ) ],
    'network.matches_long_form'             => [ 'notes', gettext( "'network:long' matches long form" ) ],
    'network.not_set'                       => [ 'issues', gettext( "'network' is not set" ) ],
    'network.differs_from_master'           => [ 'issues', gettext( "'network' = '%s' of Route does not fit to 'network' = '%s' of Route-Master: %s" ) ],
    'network.part_of_master'                => [ 'notes', gettext( "'network' = '%s' of Route is a part of 'network' = '%s' of Route-Master: %s" ) ],
    'network.should_be_long'                => [ 'notes', gettext( "'network' = '%s' should be long form" ) ],
    'network.should_be_short'               => [ 'notes', gettext( "'network' = '%s' should be short form" ) ],
    'tag.differs_from_master'               => [ 'issues', gettext( "'%s' = '%s' of Route does not fit to '%s' = '%s' of Route-Master: %s" ) ],
    'tag.matches_other_route'               => [ 'issues', gettext( "'%s' = '%s' of Route has a match with '%s' = '%s' of other Route(s)" ) ],
    'tag.identical_to_other_route'          => [ 'issues', gettext( "'%s' = '%s' of Route is identical to '%s' of other Route(s)" ) ],
    'tag.not_set_but_on_master'             => [ 'issues', gettext( "'%s' of Route is not set but '%s' = '%s' of Route-Master is set: %s" ) ],
    'tag.set_but_not_on_master'             => [ 'issues', gettext( "'%s' = '%s' of Route is set but '%s' of Route-Master is not set: %s" ) ],
    'operator.differs_from_master'          => [ 'issues', gettext( "'operator' = '%s' of Route does not fit to 'operator' = '%s' of Route-Master: %s" ) ],
    'gtfs.orphaned_key'                     => [ 'issues', gettext( "Orphaned GTFS key '%s' = '%s' with no other GTFS-specific information." ) ],
    'ptv2.way_before_first_stop'            => [ 'issues', gettext( "PTv2 route: consider removing the first way of the route from the relation, it is a way before the first stop position: %s" ) ],
    'ptv2.way_after_last_stop'              => [ 'issues', gettext( "PTv2 route: consider removing the last way of the route from the relation, it is a way after the last stop position: %s" ) ],
    'ptv2.gap_in_route'                     => [ 'issues', ngettext( "PTv2 route: consists of %d segments, has a gap. Gap appears at way", "PTv2 route: consists of %d segments, has gaps. Gaps appear at ways", 1 ) ],
    'ptv2.empty_role_no_pt'                 => [ 'issues', gettext( "PTv2 route: empty 'role' and 'public_transport' is not set on object" ) ],
    'ptv2.empty_role_platform'              => [ 'issues', gettext( "PTv2 route: empty 'role'. Consider setting 'role'='platform' or 'role'='platform_entry_only' or 'role'='platform_exit_only'" ) ],
    'ptv2.empty_role_stop'                  => [ 'issues', gettext( "PTv2 route: empty 'role'. Consider setting 'role'='stop' or 'role'='stop_entry_only' or 'role'='stop_exit_only'" ) ],
    'ptv2.empty_role_stop_relation'         => [ 'issues', gettext( "PTv2 route: empty 'role' for a relation object which has 'public_transport'='stop_position' set. For PTv2, 'public_transport'='stop_position' is allow on nodes only" ) ],
    'ptv2.empty_role_stop_way'              => [ 'issues', gettext( "PTv2 route: empty 'role' for a way object which has 'public_transport'='stop_position' set. For PTv2, 'public_transport'='stop_position' is allow on nodes only" ) ],
    'ptv2.empty_role_unknown_pt'            => [ 'issues', gettext( "PTv2 route: empty 'role'. Unknown value for 'public_transport' on object (='%s')" ) ],
    'ptv2.first_node_oneway_exit_only'      => [ 'issues', gettext( "PTv2 route: first node of oneway way has 'role' = 'stop_exit_only'" ) ],
    'ptv2.first_node_exit_only'             => [ 'issues', gettext( "PTv2 route: first node of way has 'role' = 'stop_exit_only'. Is the route sorted in reverse order?" ) ],
    'ptv2.first_node_not_stop'              => [ 'issues', gettext( "PTv2 route: first node of way is not a stop position of this route: %s" ) ],
    'ptv2.first_node_not_first_stop'        => [ 'issues', gettext( "PTv2 route: first node of way is not the first stop position of this route: %s versus %s" ) ],
    'ptv2.first_stop_not_first'             => [ 'issues', gettext( "PTv2 route: first stop position on first way is not the first stop position of this route: %s versus %s" ) ],
    'ptv2.first_oneway_no_exit'             => [ 'issues', gettext( "PTv2 route: first way is a oneway road and ends in a 'stop_position' of this route and there is no exit. Is the route sorted in reverse order?" ) ],
    'ptv2.from_mismatch_platform'           => [ 'notes', gettext( "PTv2 route: 'from' = '%s' does not match 'name' of first platform: %s" ) ],
    'ptv2.from_differs_platform'            => [ 'notes', gettext( "PTv2 route: 'from' = '%s' is not equal to 'name' of first platform: %s" ) ],
    'ptv2.from_not_set'                     => [ 'notes', gettext( "PTv2 route: 'from' is not set" ) ],
    'ptv2.name_from_mismatch'               => [ 'notes', gettext( "PTv2 route: from-part ('%s') of 'name' does not match 'from' = '%s'" ) ],
    'ptv2.name_from_differs'                => [ 'notes', gettext( "PTv2 route: from-part ('%s') of 'name' is not equal to 'from' = '%s'" ) ],
    'ptv2.roundabout_partial'               => [ 'notes', ngettext( "PTv2 route: includes %d entire roundabout but uses only segments", "PTv2 route: includes %d entire roundabouts but uses only segments", 1 ) ],
    'ptv2.wrong_order'                      => [ 'issues', gettext( "PTv2 route: incorrect order of 'stop_position', 'platform' and 'way' (stop/platform after way)" ) ],
    'ptv2.name_lacks_value'                 => [ 'notes', gettext( "PTv2 route: '%s' is not part of 'name' (derived from '%s' = '%s')" ) ],
    'ptv2.last_node_oneway_entry_only'      => [ 'issues', gettext( "PTv2 route: last node of oneway way has 'role' = 'stop_entry_only'" ) ],
    'ptv2.last_node_entry_only'             => [ 'issues', gettext( "PTv2 route: last node of way has 'role' = 'stop_entry_only'. Is the route sorted in reverse order?" ) ],
    'ptv2.last_node_not_stop'               => [ 'issues', gettext( "PTv2 route: last node of way is not a stop position of this route: %s" ) ],
    'ptv2.last_node_not_last_stop'          => [ 'issues', gettext( "PTv2 route: last node of way is not the last stop position of this route: %s versus %s" ) ],
    'ptv2.last_stop_not_last'               => [ 'issues', gettext( "PTv2 route: last stop position on last way is not the last stop position of this route: %s versus %s" ) ],
    'ptv2.role_pt_mismatch'                 => [ 'issues', gettext( "PTv2 route: mismatch between 'role' = '%s' and 'public_transport' = '%s'" ) ],
    'ptv2.missing_yes_on_pt'                => [ 'issues', gettext( "PTv2 route: missing '%s' = 'yes' on 'public_transport' = '%s'" ) ],
    'ptv2.name_multi_arrow_no_via'          => [ 'notes', gettext( "PTv2 route: 'name' has more than one '=>' but 'via' is not set" ) ],
    'ptv2.name_no_via_but_via_set'          => [ 'notes', gettext( "PTv2 route: 'name' has no via-parts but 'via' is set" ) ],
    'ptv2.name_deprecated_arrow'            => [ 'notes', gettext( "PTv2 route: 'name' includes deprecated '==&gt;'" ) ],
    'ptv2.name_deprecated_bidir_arrow'      => [ 'notes', gettext( "PTv2 route: 'name' includes deprecated '&lt;=&gt;'" ) ],
    'ptv2.name_identical_other'             => [ 'notes', gettext( "PTv2 route: 'name' of Route is identical to 'name' of other Route(s), consider setting an appropriate 'via' value and include that into 'name'" ) ],
    'ptv2.name_form_required'               => [ 'notes', gettext( "PTv2 route: 'name' should (at least) be of the form '... ref ...: from => to'" ) ],
    'ptv2.name_form_similar'                => [ 'notes', gettext( "PTv2 route: 'name' should be similar to the form '... ref ...: from => to'" ) ],
    'ptv2.platform_part_of_way'             => [ 'issues', gettext( "PTv2 route: 'public_transport' = 'platform' is part of way" ) ],
    'ptv2.stop_not_part_of_way'             => [ 'issues', gettext( "PTv2 route: 'public_transport' = 'stop_position' is not part of way" ) ],
    'ptv2.ref_not_in_name'                  => [ 'notes', gettext( "PTv2 route: 'ref' is not part of 'name'" ) ],
    'ptv2.role_suggest_platform'            => [ 'issues', gettext( "PTv2 route: 'role' = '%s' and %s: consider setting 'public_transport' = 'platform'" ) ],
    'ptv2.role_suggest_stop'                => [ 'issues', gettext( "PTv2 route: 'role' = '%s' and %s: consider setting 'public_transport' = 'stop_position'" ) ],
    'ptv2.role_pt_unset_but_set'            => [ 'issues', gettext( "PTv2 route: 'role' = '%s' and 'public_transport' is not set but '%s' is set" ) ],
    'ptv2.role_pt_unset'                    => [ 'issues', gettext( "PTv2 route: 'role' = '%s' but 'public_transport' is not set" ) ],
    'ptv2.roundabout_twice'                 => [ 'issues', ngettext( "PTv2 route: roundabout appears twice, following itself", "PTv2 route: roundabouts appear twice, following themselves", 1 ) ],
    'ptv2.roundtrip_same_stops'             => [ 'issues', gettext( "PTv2 route: 'roundtrip' = '%s' and the first and the last platform stops are the same. Consider setting 'roundtrip' = '%s'%s." ) ],
    'ptv2.roundtrip_not_same_stops'         => [ 'issues', gettext( "PTv2 route: 'roundtrip' = '%s' but the first and the last platform stops are not the same. Consider setting 'roundtrip' = '%s'%s." ) ],
    'ptv2.roundtrip_unset_same_stops'       => [ 'notes', gettext( "PTv2 route: 'roundtrip' is not set and the first and the last platform stops are the same. Consider setting 'roundtrip' = '%s'%s." ) ],
    'ptv2.roundtrip_yes_near'               => [ 'notes', gettext( "PTv2 route: 'roundtrip' = 'yes' and the first and the last platform stops are less than %d metres / %d feet apart (actual distance = %d metres / %d feet). This is considered acceptable." ) ],
    'ptv2.roundtrip_yes_far'                => [ 'issues', gettext( "PTv2 route: 'roundtrip' = 'yes' but the first and the last platform stops are more than %d metres / %d feet apart (actual distance = %d metres / %d feet). Consider setting 'roundtrip' = '%s'%s." ) ],
    'ptv2.start_not_near_first'             => [ 'issues', gettext( "PTv2 route: the beginning of the route on the first way (%s) is not near the first platform stop (%s). Distance = %d metres / %d feet." ) ],
    'ptv2.end_not_near_last'                => [ 'issues', gettext( "PTv2 route: the end of the route on the last way (%s) is not near the last platform stop (%s). Distance = %d metres / %d feet." ) ],
    'ptv2.via_name_fewer'                   => [ 'notes', gettext( "PTv2 route: there are less via-parts in 'name' (%d) than in 'via' (%d)" ) ],
    'ptv2.via_name_more'                    => [ 'notes', gettext( "PTv2 route: there are more via-parts in 'name' (%d) than in 'via' (%d)" ) ],
    'ptv2.no_platform'                      => [ 'notes', gettext( "PTv2 route: there is no 'public_transport' = 'platform' (Node, Way, Area or Relation)" ) ],
    'ptv2.no_stop'                          => [ 'notes', gettext( "PTv2 route: there is no 'public_transport' = 'stop_position' (Node)" ) ],
    'ptv2.no_stop_no_platform'              => [ 'issues', gettext( "PTv2 route: there is no 'public_transport' = 'stop_position' (Node) and no 'public_transport' = 'platform' (Node, Way, Area or Relation)" ) ],
    'ptv2.no_stop_on_first_way'             => [ 'issues', gettext( "PTv2 route: there is no stop position of this route on the first way: %s" ) ],
    'ptv2.no_stop_on_last_way'              => [ 'issues', gettext( "PTv2 route: there is no stop position of this route on the last way: %s" ) ],
    'ptv2.one_platform'                     => [ 'issues', gettext( "PTv2 route: there is only one 'public_transport' = 'platform' (Node, Way, Area or Relation)" ) ],
    'ptv2.one_stop'                         => [ 'issues', gettext( "PTv2 route: there is only one 'public_transport' = 'stop_position' (Node)" ) ],
    'ptv2.to_mismatch_platform'             => [ 'notes', gettext( "PTv2 route: 'to' = '%s' does not match 'name' of last platform: %s" ) ],
    'ptv2.to_differs_platform'              => [ 'notes', gettext( "PTv2 route: 'to' = '%s' is not equal to 'name' of last platform: %s" ) ],
    'ptv2.to_not_set'                       => [ 'notes', gettext( "PTv2 route: 'to' is not set" ) ],
    'ptv2.name_to_mismatch'                 => [ 'notes', gettext( "PTv2 route: to-part ('%s') of 'name' does not match 'to' = '%s'" ) ],
    'ptv2.name_to_differs'                  => [ 'notes', gettext( "PTv2 route: to-part ('%s') of 'name' is not equal to 'to' = '%s'" ) ],
    'ptv2.motorway_link_no_motorway'        => [ 'issues', ngettext( "PTv2 route: using motorway_link way without entering a motorway way", "PTv2 route: using motorway_link ways without entering a motorway way", 1 ) ],
    'ptv2.oneway_wrong_direction'           => [ 'issues', ngettext( "PTv2 route: using oneway way in wrong direction", "PTv2 route: using oneway ways in wrong direction", 1 ) ],
    'ptv2.wrong_way_type'                   => [ 'issues', gettext( "PTv2 route: using wrong way type (%s)" ) ],
    'ptv2.via_few_platforms'                => [ 'notes', gettext( "PTv2 route: 'via' is set, but there are less than 3 platforms (=%d)." ) ],
    'ptv2.via_few_platforms_n'              => [ 'notes', gettext( "PTv2 route: 'via' is set (%d parts), but there are less than %d platforms (=%d)." ) ],
    'ptv2.via_part_no_platform'             => [ 'notes', gettext( "PTv2 route: 'via' is set. %d. via-part ('%s') does not match any platform name." ) ],
    'ptv2.via_part_ambiguous'               => [ 'notes', gettext( "PTv2 route: 'via' is set. %d. via-part ('%s') matches name of more than one platform (platform numbers: %s)" ) ],
    'ptv2.via_part_mismatch'                => [ 'notes', gettext( "PTv2 route: 'via' is set: %d. via-part ('%s') of 'name' does not match %d. via-value = '%s'" ) ],
    'ptv2.via_part_differs'                 => [ 'notes', gettext( "PTv2 route: 'via' is set: %d. via-part ('%s') of 'name' is not equal to %d. via-value = '%s'" ) ],
    'ptv2.way_into_roundabout'              => [ 'issues', ngettext( "PTv2 route: way leads into/through roundabout/closed way %s", "PTv2 route: ways lead into/through roundabout/closed way %s", 1 ) ],
    'ptv2.wrong_role'                       => [ 'issues', gettext( "PTv2 route: wrong 'role' = '%s'" ) ],
    'ptv2.wrong_role_first_platform'        => [ 'issues', gettext( "PTv2 route: wrong 'role' = '%s' for first platform" ) ],
    'ptv2.wrong_role_first_stop'            => [ 'issues', gettext( "PTv2 route: wrong 'role' = '%s' for first stop" ) ],
    'ptv2.wrong_role_last_platform'         => [ 'issues', gettext( "PTv2 route: wrong 'role' = '%s' for last platform" ) ],
    'ptv2.wrong_role_last_stop'             => [ 'issues', gettext( "PTv2 route: wrong 'role' = '%s' for last stop" ) ],
    'ptv2.version_invalid'                  => [ 'issues', gettext( "'public_transport:version' is neither '1' nor '2'" ) ],
    'ptv2.version_not_2'                    => [ 'issues', gettext( "'public_transport:version' is not set to '2'" ) ],
    'ref.not_set'                           => [ 'issues', gettext( "'ref' is not set" ) ],
    'route.bus_stop_on_way'                 => [ 'issues', ngettext( "Route: 'highway' = 'bus_stop' is set on way. Allowed on nodes only!", "Route: 'highway' = 'bus_stop' is set on ways. Allowed on nodes only!", 1 ) ],
    'access.way_busway'                     => [ 'issues', ngettext( "Route: incorrect access restriction (%s) to way. Consider tagging as 'busway'='%s'", "Route: incorrect access restriction (%s) to ways. Consider tagging as 'busway'='%s'", 1 ) ],
    'access.way_no_yes'                     => [ 'issues', ngettext( "Route: incorrect access restriction (%s) to way. Consider tagging as '%s'='no' and '%s'='yes'", "Route: incorrect access restriction (%s) to ways. Consider tagging as '%s'='no' and '%s'='yes'", 1 ) ],
    'stop_ref.delete'                       => [ 'notes', gettext( "Route: '%s' = '%s' of stop should be deleted, 'route_ref' = '%s' exists" ) ],
    'stop_ref.replace'                      => [ 'notes', gettext( "Route: '%s' = '%s' of stop should be replaced by 'route_ref' = '%s'" ) ],
    'stop_ref.represents_stop_add'          => [ 'notes', gettext( "Route: 'ref' = '%s' of stop should represent the reference of the stop, but includes the 'ref' = '%s' of this route (consider adding '%s' to the 'route_ref' tag of the stop)" ) ],
    'stop_ref.represents_stop_create'       => [ 'notes', gettext( "Route: 'ref' = '%s' of stop should represent the reference of the stop, but includes the 'ref' = '%s' of this route (consider creating a 'route_ref' = '%s' tag for the stop)" ) ],
    'access.barrier'                        => [ 'issues', ngettext( "Route: restricted access at barrier (%s) without 'psv'='yes', '%s'='yes', '%s'='designated', or ...", "Route: restricted access at barriers (%s) without 'psv'='yes', '%s'='yes', '%s'='designated', or ...", 1 ) ],
    'access.platform'                       => [ 'issues', ngettext( "Route: restricted access (%s) at platform without 'psv'='yes', '%s'='yes', '%s'='designated', or ...", "Route: restricted access (%s) at platforms without 'psv'='yes', '%s'='yes', '%s'='designated', or ...", 1 ) ],
    'access.platform_school_bus'            => [ 'issues', ngettext( "Route: restricted access (%s) for a school bus at platform", "Route: restricted access (%s) for a school bus at platforms", 1 ) ],
    'access.platform_foot'                  => [ 'issues', ngettext( "Route: restricted access (%s) for pedestrians at platform", "Route: restricted access (%s) for pedestrians at platforms", 1 ) ],
    'access.way_school'                     => [ 'issues', ngettext( "Route: restricted access ('%s'='school') to way for a route relation not tagged with 'bus'='school'", "Route: restricted access ('%s'='school') to ways for a route relation not tagged with 'bus'='school'", 1 ) ],
    'access.way_designated'                 => [ 'issues', ngettext( "Route: restricted access (%s) to way. Consider tagging as '%s'='yes', '%s'=designated, or ... along with 'motor_vehicle='no'", "Route: restricted access (%s) to ways. Consider tagging as '%s'='yes', '%s'=designated, or ... along with 'motor_vehicle='no'", 1 ) ],
    'access.way_psv_included'               => [ 'issues', ngettext( "Route: restricted access (%s) to way. The key '%s' also includes public transport buses", "Route: restricted access (%s) to ways, The key '%s' also includes public transport buses", 1 ) ],
    'access.way_no_psv'                     => [ 'issues', ngettext( "Route: restricted access (%s) to way without 'psv'='yes', '%s'='yes', '%s'='designated', or ...", "Route: restricted access (%s) to ways without 'psv'='yes', '%s'='yes', '%s'='designated', or ...", 1 ) ],
    'stop_ref.comma_separator'              => [ 'notes', gettext( "Route: 'route_ref' = '%s' of stop: ',' (comma) as separator value should be replaced by ';' (semi-colon) without blank" ) ],
    'stop_ref.lacks_route_ref'              => [ 'issues', gettext( "Route: 'route_ref' = '%s' of stop does not include 'ref' = '%s' value of this route" ) ],
    'stop_ref.lacks_route_ref_comma'        => [ 'issues', gettext( "Route: 'route_ref' = '%s' of stop does not include 'ref' = '%s' value of this route (separate multiple values by ';' (semi-colon) without blank)" ) ],
    'route.see'                             => [ 'notes', gettext( "Route: see" ) ],
    'access.way_suspicious_lanes'           => [ 'issues', ngettext( "Route: suspicious access restriction (%s) to way. Check whether this should be '%s:lanes%s'='%s'", "Route: suspicious access restriction (%s) to ways. Check whether this should be '%s:lanes%s'='%s'", 1 ) ],
    'access.way_suspicious_psv'             => [ 'issues', ngettext( "Route: suspicious access restriction (%s) to way. Check whether this should be '%s'='yes' or 'psv'='yes'", "Route: suspicious access restriction (%s) to ways. Check whether this should be '%s'='yes' or 'psv'='yes'", 1 ) ],
    'route.suspicious_construction'         => [ 'notes', ngettext( "Route: suspicious %s along with 'highway' unequal to 'construction' on way", "Route: suspicious %s along with 'highway' unequal to 'construction' on ways", 1 ) ],
    'route.way_type'                        => [ 'notes', gettext( "Route: using way type (%s)" ) ],
    'route.not_in_data'                     => [ 'issues', gettext( "Route does not exist in the given data set: %s" ) ],
    'route.no_ref_in_data'                  => [ 'issues', gettext( "Route exists in the given data set but 'ref' tag is not set: %s" ) ],
    'route.network_differs_master'          => [ 'issues', gettext( "Route has different 'network' = '%s' than Route-Master 'network' = '%s': %s" ) ],
    'route.operator_differs_master'         => [ 'issues', gettext( "Route has different 'operator' = '%s' than Route-Master 'operator' = '%s': %s" ) ],
    'route.type_differs_master'             => [ 'issues', gettext( "Route has different 'route' = '%s' than Route-Master 'route_master' = '%s': %s" ) ],
    'network.irrelevant_value'              => [ 'notes', gettext( "Route has 'network' = '%s' value which is considered as not relevant: %s" ) ],
    'network.part_of_master_value'          => [ 'notes', gettext( "Route has 'network' = '%s' value which is part of 'network' = '%s' of Route-Master: %s" ) ],
    'route.ref_mismatch'                    => [ 'issues', gettext( "Route has not matching 'ref' = '%s': %s" ) ],
    'operator.irrelevant_value'             => [ 'issues', gettext( "Route has 'operator' = '%s' value which is considered as not relevant: %s" ) ],
    'route.value_irrelevant'                => [ 'issues', gettext( "Route has 'route' = '%s' value which is considered as not relevant: %s" ) ],
    'route.not_in_master'                   => [ 'issues', gettext( "Route is not member of Route-Master: %s" ) ],
    'master.no_ref_in_data'                 => [ 'issues', gettext( "Route-Master exists in the given data set but 'ref' tag is not set: %s" ) ],
    'master.fewer_routes'                   => [ 'issues', ngettext( "Route-Master has less Routes than actually match (%d versus %d) in the given data set", "Route-Masters have less Routes than actually match (%d versus %d) in the given data set", 1 ) ],
    'master.members_with_role'              => [ 'issues', ngettext( "Route-Master has %d member with 'role' being set", "Route-Master has %d members with 'role' being set", 1 ) ],
    'master.more_routes'                    => [ 'issues', ngettext( "Route-Master has more Routes than actually match (%d versus %d) in the given data set", "Route-Masters have more Routes than actually match (%d versus %d) in the given data set", 1 ) ],
    'master.ref_mismatch'                   => [ 'issues', gettext( "Route-Master has not matching 'ref' = '%s': %s" ) ],
    'master.other_section_ref'              => [ 'issues', gettext( "Route-Master might be listed with 'ref' = '%s' in a different section or in section 'Not clearly assigned routes' of this analysis: %s" ) ],
    'master.other_section_unknown_ref'      => [ 'issues', gettext( "Route-Master might be listed with unknown 'ref' in section 'Public Transport Lines without 'ref'' of this analysis: %s" ) ],
    'master.has_nodes'                      => [ 'issues', gettext( "Route-Master with Node(s)" ) ],
    'master.has_relations'                  => [ 'issues', gettext( "Route-Master with Relation(s) unequal to 'route'" ) ],
    'master.has_ways'                       => [ 'issues', gettext( "Route-Master with Way(s)" ) ],
    'master.no_routes'                      => [ 'issues', gettext( "Route-Master without Route(s)" ) ],
    'route.other_section_ref'               => [ 'issues', gettext( "Route might be listed with 'ref' = '%s' in a different section or in section 'Not clearly assigned routes' of this analysis: %s" ) ],
    'route.type_not_fit_master'             => [ 'issues', gettext( "'route' = '%s' of Route does not fit to 'route_master' = '%s' of Route-Master: %s" ) ],
    'route.tag_not_set'                     => [ 'issues', gettext( "'route' tag is not set: %s" ) ],
    'route.one_stop'                        => [ 'issues', gettext( "Route with only 1 Stop(Node)" ) ],
    'route.one_way'                         => [ 'issues', gettext( "Route with only 1 Way" ) ],
    'route.has_relations'                   => [ 'issues', gettext( "Route with Relation(s)" ) ],
    'route.no_stops'                        => [ 'issues', gettext( "Route without Stops(Nodes)" ) ],
    'route.no_ways'                         => [ 'issues', gettext( "Route without Way(s)" ) ],
    'data.skipped_incomplete'               => [ 'issues', gettext( "Skipping further analysis. PTNA did not download all needed OSM data." ) ],
    'date.not_exists'                       => [ 'issues', gettext( "The date does not exist" ) ],
    'tag.empty_value'                       => [ 'issues', gettext( "The tag '%s' has an empty value." ) ],
    'tag.problematic_char_key'              => [ 'notes', gettext( "The tag '%s' includes potentially problematic character '%s' in key. Value of tag: '%s'" ) ],
    'tag.whitespace_in_key'                 => [ 'notes', gettext( "The tag '%s' includes whitespace character '%s' (=%#2x) in key. Value of tag: '%s'" ) ],
    'tag.line_reserved'                     => [ 'notes', gettext( "The tag 'line' (='%s') is reserved for 'power' = 'line' related tagging. For public transport 'route_master' and 'route' are used." ) ],
    'ptv2.tag_undefined_for_route'          => [ 'issues', gettext( "The tag 'public_transport' (='%s') is not defined for 'route_master' and 'route' relations. Do you mean 'public_transport:version'='2'%s?" ) ],
    'date.not_iso8601'                      => [ 'notes', gettext( "The value of '%s' (= '%s') should be specified in ISO 8601 format: YYYY-MM-DD" ) ],
    'master.multiple'                       => [ 'issues', gettext( "There is more than one Route-Master" ) ],
    'route.in_multiple_masters'             => [ 'issues', gettext( "This Route is direct member of more than one Route-Master: %s" ) ],
    'route.no_master'                       => [ 'issues', gettext( "This Route is not a member of any Route-Master" ) ],
    'rel.type_not_route'                    => [ 'issues', gettext( "'type' = '%s' is not 'route': %s" ) ],
    'rel.type_not_set'                      => [ 'issues', gettext( "'type' tag is not set: %s" ) ],
);

#############################################################################################

sub _make {
    my ( $type, $code, @args ) = @_;

    die "PtnaOutput::Issues: unknown $type '$code'\n"                  unless ( exists( $CATALOG{$code} ) );
    die "PtnaOutput::Issues: '$code' is a $CATALOG{$code}->[0], not $type\n"    unless ( $CATALOG{$code}->[0] eq $type );
    my $n = ( ref( $CATALOG{$code}->[1] ) && defined( $CATALOG{$code}->[1]->{'plural'} ) ) ? shift( @args ) : undef;
    return issue_msg( $code, $n, @args ? \@args : undef );
}

sub issue { return _make( 'issues', @_ ); }
sub note  { return _make( 'notes',  @_ ); }
sub detail { return _make( 'detail', @_ ); }


#############################################################################################
#
# returns { 'type' => 'issues'|'notes', 'id' => msgid, 'plural' => plural-msgid or undef }
#
#############################################################################################

sub entry {
    my $code = shift;

    return undef    unless ( exists( $CATALOG{$code} ) );
    my ( $type, $tr ) = @{$CATALOG{$code}};
    return { 'type' => $type, 'plain' => $tr } unless ( ref( $tr ) );
    return { 'type' => $type, 'id' => $tr->{'id'}, 'plural' => $tr->{'plural'} };
}


#############################################################################################

sub codes {
    return sort( keys( %CATALOG ) );
}

1;
