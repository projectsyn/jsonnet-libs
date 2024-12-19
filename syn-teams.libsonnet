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
 * \brief Returns the team for the given application or null.
 *
 * It does so by looking at the top level `syn` parameter of a Commodore
 * inventory. The syn parameter should look roughly like this.
 *
 *   syn:
 *     owner: clumsy-donkeys
 *     teams:
 *       chubby-cockroaches:
 *         instances:
 *           - superb-visualization
 *       lovable-lizards:
 *         instances:
 *           - apartment-cats
 *
 * The application is first looked up in the instances of the teams, if no team is found, owner is used as fallback.
 * An error is thrown if the application is found belonging to multiple teams.
 *
 * \arg app
 *    The application name. Can be the merged `inventory().params._instance` or an (aliased) application name.
 * \return
 *    The team name or `null` if no team configuration is present.
 */
local teamForApplication(app) =
  local params = inv.parameters;
  local lookup = function(app)
    if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'teams') then
      local teams = params.syn.teams;
      local teamsForApp = std.foldl(
        function(prev, team)
          if std.objectHas(teams, team) && std.objectHas(teams[team], 'instances') && std.member(com.renderArray(teams[team].instances), app) then
            prev + [ team ]
          else
            prev,
        std.objectFields(teams),
        [],
      );
      if std.length(teamsForApp) == 0 then
        null
      else if std.length(teamsForApp) == 1 then
        teamsForApp[0]
      else
        error 'application `%s` is in multiple teams: %s' % [ app, std.join(', ', teamsForApp) ];

  local teams = std.prune(std.map(lookup, appKeys(app, true)));

  if std.length(teams) > 0 then
    teams[0]
  else if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'owner') then
    params.syn.owner;


/**
 * \brief Extract the list of applications for the given team from the teamApplicationMap defined above.
 *
 * \arg team the team name to lookup in the map
 *
 * \returns a list of applications assigned to the team or null if the team doesn't exist in the map.
 */
local applicationsForTeam(team) = std.get(teamApplicationMap, team, null);


{
  // Values
  teamApplicationMap: teamApplicationMap,

  // Functions
  appKeys: appKeys,
  teamForApplication: teamForApplication,
  applicationsForTeam: applicationsForTeam,
}
