/**
 * \file alert-routing-discovery.libsonnet
 * \brief Functionality to render an Alertmanager config which routes alerts based on component instance team assignments.
 *
 * NOTE: This Jsonnet library is intended for use with Commodore. The library
 * can be used in component code as well as postprocessing filters.
 *
 * This library is inteded to be used by Commodore components which configure
 * Alertmanager (e.g. openshift4-monitoring or prometheus). The library
 * exposes two functions `alertmanagerConfig` and `debugConfigMapData`. Both
 * functions expect the same set of parameters: `adParams`, `amConfig`,
 * `nullReceiver` and `fallbackTeam`. See the documentation of function
 * `alertmanagerConfig()` for a detailed description of these parameters.
 */
local com = import 'lib/commodore.libjsonnet';
local syn_teams = import 'syn-teams.libsonnet';

local inv = com.inventory();
local params = inv.parameters;

// discoverNS returns the namespace for the given application.
// It looks into the follwing places:
// - params.<app>.namespace
// - params.<app>.namespace.name
// It does respect aliased applications and looks in the instance first and then in the base application.
local discoverNS = function(app)
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
  // namespaces from the monitoring component's parameters, `${_instance}` is
  // resolved to that component's instance name and not to the actual
  // component instance name.
  //
  // We override the discovered namespace here if we discover a namespace that
  // contains `parameters._instance` for any app other than the app using this
  // library.
  //
  // It's safe to use `parameters._instance` here, since that's the value that
  // will be substituted for instantiated components that use `${_instance}`
  // in their namespace definition.
  if
    ns != null &&
    app != params._instance &&
    std.length(std.findSubstr(params._instance, ns)) > 0
  then
    std.trace(
      'overriding namespace autodiscovery for `%s` (discovered namespace: %s)' % [ app, ns ],
      std.strReplace(ns, params._instance, std.strReplace(ks[0], '_', '-'))
    )
  else
    ns;

local ownerOrFallbackTeam(fallbackTeam) =
  if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'owner') then
    params.syn.owner
  else
    fallbackTeam;

// teamToNS is a map from a team to namespaces.
// The inner `std.prune()` is to drop `null` entries from a list that contains
// a mix of null and non-null entries. The outer `std.prune()` drops teams
// for which we haven't discovered any namespaces from the resulting object.
local teamToNS = std.prune(std.mapWithKey(
  function(_, a) std.uniq(std.sort(std.prune(a))),
  std.foldl(
    function(prev, app)
      local instance = syn_teams.appKeys(app, true)[0];
      local team = syn_teams.teamForApplication(instance);
      prev { [team]+: [ discoverNS(app) ] },
    inv.applications,
    {}
  )
));

// teamBasedRouting contains discovered routes for teams.
// The routes are set up with `continue: true` so we can route to multiple teams.
// The last route catches all alerts already routed to a team.
local teamBasedRouting(adParams, nullReceiver) =
  std.map(
    function(k) {
      receiver: adParams.team_receiver_format % k,
      matchers: adParams.additional_alert_matchers + [
        'namespace =~ "%s"' % std.join('|', teamToNS[k]),
      ],
      continue: true,
    },
    std.objectFields(teamToNS)
  ) + [ {
    // catch all alerts already routed to a team
    receiver: nullReceiver,
    matchers: adParams.additional_alert_matchers + [
      'namespace =~ "%s"' % std.join('|', std.foldl(function(prev, nss) prev + nss, std.objectValues(teamToNS), [])),
    ],
    continue: false,
  } ];

local _nullR = '__alert_routing_discovery_null';

/**
 * \brief Returns an Alertmanager config that's suitable to be used to configure Alertmanager via prometheus-operator.
 *
 * \arg adParams
 *   Configuration for the alert routing discovery algorithm.
 *
 *   This parameter is an object which is expected to have fields
 *   `prepend_routes`, `append_routes`, `team_receiver_format`, and
 *   `additional_alert_matchers`.
 *
 *   Fields `prepend_routes` and `append_routes` are added to the final
 *   Alertmanager config before and after the dynamic routes that are
 *   generated by the discovery algorithm.
 *
 *   Field `team_receiver_format` is used to render Alertmanager receiver
 *   names for each discovered team. The library expects that the value of
 *   this field contains exactly one '%s' which is substituted with the target
 *   team's name. Users of the library must ensure that matching receivers are
 *   defined in `amConfig.receivers` (or injected into the result of this
 *   function).
 *
 *   Field `additional_alert_matchers` is used in addition ot the matchers
 *   generated by the discovery logic and allows users to further restrict the
 *   set of alerts that are matched by the generated routes.
 *
 * \arg amConfig
 *   Partial Alertmanager config. The config that's rendered by this function
 *   is merged into this object.
 *
 * \arg nullReceiver (optional)
 *   Name to use for the fallback blackhole receiver for alerts that can't be
 *   assigned to any team. Defaults to `__alert_routing_discovery_null`.
 *
 * \arg fallbackTeam (optional)
 *   Fallback team to which to route alerts which can't be mapped to a team.
 *   Has no effect if `syn.owner` is set for the target cluster.
 *   Defaults to `null`. If neither `syn.owner` nor this argument is set to
 *   non-null, alerts that can't be mapped to a team are blackholed.
 *
 * \return
 *   An object that can be used to configure Alertmanager via prometheus-operator.
 */
local alertmanagerConfig(adParams, amConfig, nullReceiver=_nullR, fallbackTeam=null) =
  local routes = std.get(amConfig.route, 'routes', []);
  local finalRoute =
    if ownerOrFallbackTeam(fallbackTeam) != null then
      [ {
        receiver: adParams.team_receiver_format % ownerOrFallbackTeam(fallbackTeam),
      } ]
    else
      [ { receiver: nullReceiver } ];
  std.prune(amConfig) {
    receivers+: [ { name: nullReceiver } ],
    route+: {
      routes:
        adParams.prepend_routes
        + teamBasedRouting(adParams, nullReceiver)
        + adParams.append_routes
        + routes
        + finalRoute,
    },
  };

/**
 * \brief Returns an object with data that's helpful when debugging the alert routing discovery for a certain cluster.
 *
 * See function `alertmanagerConfig` for a description of this function's
 * parameters.
 *
 * \return
 *   An object containing debug information for the alert routing discovery.
 *   The debug information is formatted as string-string pairs so the debug
 *   information can be deployed in the cluster as a `ConfigMap`.
 */
local debugConfigMapData = function(adParams, amConfig, nullReceiver=_nullR, fallbackTeam=null)
  {
    local discoveredNamespaces = std.foldl(function(prev, app) prev { [app]: discoverNS(app) }, inv.applications, {}),
    local discoveredTeams = std.foldl(function(prev, app) prev { [app]: syn_teams.teamForApplication(syn_teams.appKeys(app, true)[0]) }, inv.applications, {}),
    applications: std.manifestJsonMinified(inv.applications),
    discovered_namespaces: std.manifestYamlDoc(discoveredNamespaces),
    apps_without_namespaces: std.manifestYamlDoc(std.foldl(function(prev, app) if discoveredNamespaces[app] == null then prev + [ app ] else prev, std.objectFields(discoveredNamespaces), [])),
    discovered_teams: std.manifestYamlDoc(discoveredTeams),
    proposed_routes: std.manifestYamlDoc(teamBasedRouting(adParams, nullReceiver)),
    alertmanager: std.manifestYamlDoc(alertmanagerConfig(adParams, amConfig, nullReceiver, fallbackTeam)),
  };

{
  debugConfigMapData: debugConfigMapData,
  alertmanagerConfig: alertmanagerConfig,
}
