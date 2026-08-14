local ard = import 'alert-routing-discovery.libsonnet';
local com = import 'lib/commodore.libjsonnet';

local inv = com.inventory();

local expected = inv.expected;

local nullR = '__null';
local fallback_team = inv.parameters.openshift4_monitoring.fallback_team;

local adParams = inv.parameters.openshift4_monitoring.alertManagerAutoDiscovery;
local amConfig = inv.parameters.openshift4_monitoring.alertManagerConfig;

local debugData =
  local rendered = ard.debugConfigMapData(
    adParams, amConfig, nullR, fallback_team,
  );
  local desired = {
    applications: std.manifestJsonMinified(inv.applications),
    discovered_namespaces: std.manifestYamlDoc(expected.discovered_namespaces),
    apps_without_namespaces: std.manifestYamlDoc(expected.apps_without_namespaces),
    discovered_teams: std.manifestYamlDoc(expected.discovered_teams),
    proposed_routes: std.manifestYamlDoc(expected.proposed_routes),
    alertmanager: std.manifestYamlDoc(expected.alertmanagerConfig),
  };
  if rendered != desired then
    error
      'Error rendering debug config map data for alert routing discovery\n' +
      'Expected: %s\n' % [ desired ] +
      'Got: %s\n' % [ rendered ]
  else
    rendered;

local alertmanagerConfig =
  local rendered = ard.alertmanagerConfig(
    adParams, amConfig, nullR, fallback_team,
  );
  if rendered != expected.alertmanagerConfig then
    error
      'Error rendering alertmanager config for alert routing discovery\n' +
      'Expected: %s\n' % [ expected.alertmanagerConfig ] +
      'Got: %s\n' % [ rendered ]
  else
    rendered;

local alertmanagerConfigMultiReceiver =
  local rendered = ard.alertmanagerConfig(
    adParams { team_receiver_formats: [ 'team_default_%s', 'team_legacy_%s' ] }, amConfig, nullR, fallback_team,
  );
  if rendered != expected.alertmanagerConfigMultiReceiver then
    error
      'Error rendering alertmanager config for alert routing discovery with multiple receivers\n' +
      'Expected: %s\n' % [ expected.alertmanagerConfig ] +
      'Got: %s\n' % [ rendered ]
  else
    rendered;

{
  debugData: debugData,
  alertmanagerConfig: alertmanagerConfig,
  alertmanagerConfigMultiReceiver: alertmanagerConfigMultiReceiver,
}
