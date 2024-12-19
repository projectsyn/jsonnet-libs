/* NOTE: This Jsonnet library is intended for use with Commodore
 */
local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();

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

{
  appKeys: appKeys,
  teamForApplication: teamForApplication,
}
