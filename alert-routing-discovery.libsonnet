local com = import 'lib/commodore.libjsonnet';
local syn_teams = import 'syn-teams.libsonnet';

local inv = com.inventory();
local params = inv.parameters;

// discoverNS returns the namespace for the given application.
// It looks into the follwing places:
// - params.<app>.namespace
// - params.<app>.namespace.name
// It does respect aliased applications and looks in the instance first and then in the base application.
local discoverNS = function(app, monitoring_instance)
  local f = function(k)
    if std.objectHas(params, k) then
      local p = params[k];
      if !std.isObject(p) then
        std.trace('[WARN] parameters for component instance "%s" not an object!' % k, null)
      else if std.isObject(p) && std.objectHas(p, 'namespace') then
        if std.isString(p.namespace) then
          p.namespace
        else if std.isObject(p.namespace) && std.objectHas(p.namespace, 'name') && std.isString(p.namespace.name) then
          p.namespace.name;

  local ks = syn_teams.appKeys(app);
  local aliased = f(ks[0]);
  local ns =
    if aliased != null then
      aliased
    else if std.length(ks) == 2 then
      f(ks[1]);

  // We tend to use `namespace: ${_instance}` for components where we deploy
  // each instance in a separate namespace (e.g. component-vault,
  // component-openshift4-operators). However, because we read the instance
  // namespaces from openshift4-monitoring's parameters, `${_instance}` is
  // resolved to `openshift4-monitoring` and not to the component instance
  // name.
  //
  // We override the discovered namespace here if we discover a namespace that
  // contains `openshift4-monitoring` for any app other than
  // `openshift4-monitoring` itself.
  if
    ns != null &&
    app != monitoring_instance &&
    std.length(std.findSubstr(monitoring_instance, ns)) > 0
  then
    std.trace(
      'overriding namespace autodiscovery for `%s` (discovered namespace: %s)' % [ app, ns ],
      std.strReplace(ns, monitoring_instance, std.strReplace(ks[0], '_', '-'))
    )
  else
    ns;

local ownerOrFallbackTeam(fallback_team) =
  if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'owner') then
    params.syn.owner
  else
    fallback_team;

// teamToNS is a map from a team to namespaces.
// The inner `std.prune()` is to drop `null` entries from a list that contains
// a mix of null and non-null entries. The outer `std.prune()` drops teams
// for which we haven't discovered any namespaces from the resulting object.
local teamToNS(monitoring_instance) = std.prune(std.mapWithKey(
  function(_, a) std.uniq(std.sort(std.prune(a))),
  std.foldl(
    function(prev, app)
      local instance = syn_teams.appKeys(app, true)[0];
      local team = syn_teams.teamForApplication(instance);
      prev { [team]+: [ discoverNS(app, monitoring_instance) ] },
    inv.applications,
    {}
  )
));

// teamBasedRouting contains discovered routes for teams.
// The routes are set up with `continue: true` so we can route to multiple teams.
// The last route catches all alerts already routed to a team.
local teamBasedRouting(adParams, nullReceiver, monitoring_instance) =
  local teamNSMap = teamToNS(monitoring_instance);
  std.map(
    function(k) {
      receiver: adParams.team_receiver_format % k,
      matchers: adParams.additional_alert_matchers + [
        'namespace =~ "%s"' % std.join('|', teamNSMap[k]),
      ],
      continue: true,
    },
    std.objectFields(teamNSMap)
  ) + [ {
    // catch all alerts already routed to a team
    receiver: nullReceiver,
    matchers: adParams.additional_alert_matchers + [
      'namespace =~ "%s"' % std.join('|', std.foldl(function(prev, nss) prev + nss, std.objectValues(teamNSMap), [])),
    ],
    continue: false,
  } ];

local alertmanagerConfig(adParams, amConfig, nullReceiver, fallback_team, monitoring_instance) =
  local routes = std.get(amConfig.route, 'routes', []);
  local finalRoute =
    if ownerOrFallbackTeam(fallback_team) != null then
      [ {
        receiver: adParams.team_receiver_format % ownerOrFallbackTeam(fallback_team),
      } ]
    else
      [ { receiver: nullReceiver } ];
  std.prune(amConfig) {
    receivers+: [ { name: nullReceiver } ],
    route+: {
      routes:
        adParams.prepend_routes
        + teamBasedRouting(adParams, nullReceiver, monitoring_instance)
        + adParams.append_routes
        + routes
        + finalRoute,
    },
  };

local debugConfigMapData = function(adParams, amConfig, nullReceiver, fallback_team, monitoring_instance)
  {
    local discoveredNamespaces = std.foldl(function(prev, app) prev { [app]: discoverNS(app, monitoring_instance) }, inv.applications, {}),
    local discoveredTeams = std.foldl(function(prev, app) prev { [app]: syn_teams.teamForApplication(syn_teams.appKeys(app, true)[0]) }, inv.applications, {}),
    applications: std.manifestJsonMinified(inv.applications),
    discovered_namespaces: std.manifestYamlDoc(discoveredNamespaces),
    apps_without_namespaces: std.manifestYamlDoc(std.foldl(function(prev, app) if discoveredNamespaces[app] == null then prev + [ app ] else prev, std.objectFields(discoveredNamespaces), [])),
    discovered_teams: std.manifestYamlDoc(discoveredTeams),
    proposed_routes: std.manifestYamlDoc(teamBasedRouting(adParams, nullReceiver, monitoring_instance)),
    alertmanager: std.manifestYamlDoc(alertmanagerConfig(adParams, amConfig, nullReceiver, fallback_team, monitoring_instance)),
  };

{
  debugConfigMapData: debugConfigMapData,
  alertmanagerConfig: alertmanagerConfig,
}
