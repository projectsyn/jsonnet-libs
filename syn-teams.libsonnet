/* NOTE: This Jsonnet library is intended for use with Commodore
 */
local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();

local param_syn = std.get(inv.parameters, 'syn', {});
local syn_teams = std.get(param_syn, 'teams', {});
local syn_owner = std.get(param_syn, 'owner', null);

/**
 * \brief Returns an array with the (aliased) application name and if aliased the original name in the second position.
 *
 * The application name is translated from kebab-case to snake_case, except if the second parameter is set to true.
 *
 * \arg name
 *    The application name. Can be `name` or `name as alias`.
 * \arg raw
 *    If set to true, the application name is not translated from kebab-case to snake_case.
 * \return
 *    An array with the (aliased) application name and if aliased the original name in the second position.
 */
local appKeys(name, raw=false) =
  local normalized = function(name) if raw then name else std.strReplace(name, '-', '_');
  // can be simplified with jsonnet > 0.19 which would support ' as ' as the substring
  local parts = std.split(name, ' ');
  if std.length(parts) == 1 then
    [ normalized(parts[0]) ]
  else if std.length(parts) == 3 && parts[1] == 'as' then
    [ normalized(parts[2]), normalized(parts[0]) ]
  else
    error 'invalid application name `%s`' % name;


// Extract all instances from `inv.applications`.
// The design doc (SDD-0030) specifies that entries in `syn.<team>.instances`
// must be component instances, so we don't need to worry about the component
// name for instantiated components.
local allInstances = std.set(
  std.map(function(app) appKeys(app, true)[0], inv.applications)
);


/**
 * \brief A map from team names to applications
 *
 * This raises an error if any component instances that are defined in
 * `inv.applications` aren't assigned to a team (and are explicitly removed in
 * the owner team). Note that this function doesn't validate whether any
 * applications are assigned to multiple teams.
 *
 * \returns a map from team names (including the owning team) to component instance names.
 */
local teamApplicationMap =
  local map = {
    [team]: [
      app
      for app in com.renderArray(std.get(syn_teams[team], 'instances', []))
      if std.setMember(app, allInstances)
    ]
    for team in std.objectFields(syn_teams)
    if team != syn_owner
  };

  local teamMap = std.prune(map {
    [syn_owner]: com.renderArray(
      std.get(std.get(syn_teams, syn_owner, {}), 'instances', []) +
      std.setDiff(allInstances, std.set(std.flattenArrays(std.objectValues(map))))
    ),
  });

  local unassigned = std.setDiff(
    allInstances,
    std.set(std.flattenArrays(std.objectValues(teamMap)))
  );

  if std.length(unassigned) > 0 then
    error "Some applications aren't assigned to any team: %s" % [
      std.join(', ', unassigned),
    ]
  else
    teamMap;


/**
 * \brief A map from application instances to the assigned team
 *
 * This raises an error if any component instances that are defined in
 * `inv.applications` aren't assigned to a team (and are explicitly removed in
 * the owner team) or if any instances are assigned to multiple teams.
 *
 * \returns a map from instance names to the assigned team (including the team owning the cluster)
 */
local applicationTeamMap =
  local appMap = std.foldl(
    function(prev, instance)
      prev {
        [instance]: std.foldl(
          function(teams, team)
            if std.member(teamApplicationMap[team], instance) then
              teams + [ team ]
            else
              teams,
          std.objectFields(teamApplicationMap),
          []
        ),
      },
    allInstances,
    {},
  );

  local nonUniqueMap = {
    [app]: appMap[app]
    for app in std.objectFields(appMap)
    if std.length(appMap[app]) > 1
  };
  if std.length(nonUniqueMap) > 0 then
    error 'Some applications are assigned to multiple teams: %s' % [
      std.join(', ', std.map(
        function(app) '%s: %s' % [ app, nonUniqueMap[app] ],
        std.objectFields(nonUniqueMap)
      )),
    ]
  else
    // flatten map values into single values now that we've verified that
    // there's no non-unique assignments
    {
      [app]: appMap[app][0]
      for app in std.objectFields(appMap)
    };


/**
 * \brief Extract the responsible team for an instance from the applicationTeamMap defined above.
 *
 * Raises an error if the cluster contains instances that aren't assigned to
 * any team (taking into account the syn.owner fallback assignment) or if any
 * instances are owned by multiple teams.
 *
 * \arg app the instance name to lookup in the map
 *
 * \returns a list of applications assigned to the team or `null` if the application doesn't exist in the map.
 */
local teamForApplication(app) = std.get(applicationTeamMap, app);


/**
 * \brief Extract the list of applications for the given team from the teamApplicationMap defined above.
 *
 * \arg team the team name to lookup in the map
 *
 * \returns a list of applications assigned to the team or null if the team doesn't exist in the map.
 */
local applicationsForTeam(team) = std.get(teamApplicationMap, team, null);


/**
 * \brief Return list of teams which are responsible for at least one application that's present in the cluster.
 *
 * \arg includeOwner whether to include the owner team in the return value
 *
 * \returns a list of team names which are assigned at least one application that's present in the cluster
 */
local teams(includeOwner=false) =
  [
    team
    for team in std.objectFields(teamApplicationMap)
    if
      (includeOwner || team != inv.parameters.syn.owner) &&
      std.length(teamApplicationMap[team]) > 0
  ];


{
  // Values
  applicationTeamMap: applicationTeamMap,
  teamApplicationMap: teamApplicationMap,

  // Functions
  appKeys: appKeys,
  teamForApplication: teamForApplication,
  applicationsForTeam: applicationsForTeam,
  teams: teams,
}
