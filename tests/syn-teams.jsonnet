local com = import 'lib/commodore.libjsonnet';
local syn_teams = import 'syn-teams.libsonnet';

local expected = com.inventory().expected;

local teams =
  local t = std.set(syn_teams.teams());
  local expected_teams = std.set(expected.teams);
  if t != expected_teams then
    error 'Expected teams: %s, got teams: %s' % [
      std.join(', ', teams),
      std.join(', ', expected_teams),
    ]
  else
    t;

local all_teams =
  local t = std.set(syn_teams.teams(true));
  local expected_teams = std.set(expected.all_teams);
  if t != expected_teams then
    error 'Expected teams: %s, got teams: %s' % [
      std.join(', ', teams),
      std.join(', ', expected_teams),
    ]
  else
    t;

local appsForTeam =
  local aft = {
    [t]: syn_teams.applicationsForTeam(t)
    for t in all_teams
  };
  if aft != expected.appsForTeam then
    error 'Mismatch in appsForTeam: got %s, expected %s' % [
      aft,
      expected.appsForTeam,
    ]
  else
    aft;

local teamForApp =
  local inv = com.inventory();
  local applications = std.map(function(app) syn_teams.appKeys(app, true)[0], inv.applications);
  local tfa = {
    [a]: syn_teams.teamForApplication(a)
    for a in applications
  };
  if tfa != expected.teamForApp then
    error 'Mismatch in teamForApp: got %s, expected %s' % [
      tfa,
      expected.teamForApp,
    ]
  else
    tfa;

local appKeys =
  local expected = {
    foo: [ 'foo' ],
    'foo-bar': [ 'foo_bar' ],
    'foo-bar as bar': [ 'bar', 'foo_bar' ],
    'foo-bar as bar-qux': [ 'bar_qux', 'foo_bar' ],
  };

  {
    local ks = syn_teams.appKeys(a),
    [a]: if ks != expected[a] then
      error 'Expected %s for appKeys(%s), got %s' % [
        expected[a],
        a,
        ks,
      ]
    else
      ks
    for a in std.objectFields(expected)
  };

local appKeysRaw =
  local expected = {
    foo: [ 'foo' ],
    'foo-bar': [ 'foo-bar' ],
    'foo-bar as bar': [ 'bar', 'foo-bar' ],
    'foo-bar as bar-qux': [ 'bar-qux', 'foo-bar' ],
  };

  {
    local ks = syn_teams.appKeys(a, true),
    [a]: if ks != expected[a] then
      error 'Expected %s for appKeys(%s), got %s' % [
        expected[a],
        a,
        ks,
      ]
    else
      ks
    for a in std.objectFields(expected)
  };


{
  teams: teams,
  all_teams: all_teams,
  appKeys: appKeys,
  appKeysRaw: appKeysRaw,
  appsForTeam: appsForTeam,
  teamForApp: teamForApp,
}
