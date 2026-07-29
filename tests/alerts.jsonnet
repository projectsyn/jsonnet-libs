local com = import 'lib/commodore.libjsonnet';

local inv = com.inventory();

local expected = inv.expected;

local alerts = (import 'alerts.libsonnet') {
  // NOTE(sg): This needs to be documented properly.
  global_alert_params:: inv.parameters.global_config,
};

local testRules = {
  test_group: {
    'alert:FooIsLow': {
      expr: 'foo < 10',
      labels: {
        severity: 'warning',
      },
      annotations: {
        summary: 'Foo < 10',
        description: 'Foo is below 10, check Foo generator pipeline',
      },
    },
    'alert:SYN_FooIsExtremelyLow': {
      expr: 'foo < 2',
      labels: {
        severity: 'critical',
      },
      annotations: {
        summary: 'Foo < 2',
        description: 'Foo is below 2, immediately check Foo generator pipeline',
      },
    },
    'record:sum:foo': {
      expr: 'sum(foo)',
    },
    'alert:IgnoredAlert': {
      expr: 'vector(1)',
    },
  },
};

local testRulesRendered = [
  local rparts = std.splitLimit(r, ':', 1);
  testRules.test_group[r] {
    [rparts[0]]: rparts[1],
  }
  for r in std.objectFields(testRules.test_group)
];

local testPatches = {
  FooIsLow: {
    labels: {
      test: 'label',
    },
  },
  // patches are looked up before the alert name is patched.
  SYN_FooIsLow: {
    labels: {
      test2: 'should be ignored',
    },
  },
  SYN_FooIsExtremelyLow: {
    labels: {
      test: 'prefixed patch',
    },
  },
};

local testPatchRule =
  local rendered = [
    alerts.patchRule(r, patches=testPatches, patchName=true)
    for r in testRulesRendered
  ];

  if rendered != expected.patchedRules then
    error
      'Error in testPatchRule:\n' +
      'Expected: %s\n' % [ expected.patchedRules ] +
      'Got: %s\n' % [ rendered ]
  else
    rendered;

local testPatchRuleOrigName =
  local rendered = [
    alerts.patchRule(r, patches=testPatches, patchName=false)
    for r in testRulesRendered
  ];
  local expectedRules = [
    if std.objectHas(r, 'alert') && r.alert != 'SYN_FooIsExtremelyLow' then
      r {
        alert: std.strReplace(r.alert, 'SYN_', ''),
      }
    else
      r
    for r in expected.patchedRules
  ];

  if rendered != expectedRules then
    error
      'Error in testPatchRuleOrigName:\n' +
      'Expected: %s\n' % [ expectedRules ] +
      'Got: %s\n' % [ rendered ]
  else
    rendered;

local testFilterRules =
  local ignoreNames = [ 'SYN_FooIsExtremelyLow' ];
  local filtered = alerts.filterRules(
    { rules: testRulesRendered },
    ignoreNames=ignoreNames,
    preserveRecordingRules=true
  );
  local expectedFiltered = std.filter(
    function(r)
      !std.member(
        // NOTE(sg): IgnoredAlert is in global ignore list
        [ 'IgnoredAlert' ] + ignoreNames,
        std.get(r, 'alert', '')
      ),
    testRulesRendered
  );

  if filtered.rules != expectedFiltered then
    error
      'Error in testFilterRules:\n' +
      'Expected: %s\n' % [ expectedFiltered ] +
      'Got: %s\n' % [ filtered.rules ]
  else
    filtered;

local testFilterRulesNoRecording =
  local filtered = alerts.filterRules(
    { rules: testRulesRendered },
    ignoreNames=[],
    preserveRecordingRules=false,
  );
  local expectedFiltered = std.filter(
    function(r)
      std.objectHas(r, 'alert') &&
      r.alert != 'IgnoredAlert',
    testRulesRendered
  );

  if filtered.rules != expectedFiltered then
    error
      'Error in testFilterRulesNoRecording:\n' +
      'Expected: %s\n' % [ expectedFiltered ] +
      'Got: %s\n' % [ filtered.rules ]
  else
    filtered;

local testFilterPatchRules =
  local filtered = alerts.filterPatchRules(
    { rules: testRulesRendered },
    ignoreNames=[ 'Ignore2' ],
    patches=testPatches {
      Ignore2: {
        expr: 'vector(2)',
        labels: {
          severity: 'info',
        },
      },
    },
    preserveRecordingRules=true,
    patchNames=true,
  );

  local expectedFiltered = std.filter(
    function(r)
      !std.member(
        // NOTE(sg): IgnoredAlert is in global ignore list; also we need to
        // filter `expected.patchedRules` using the prefixed names.
        [ 'SYN_IgnoredAlert', 'SYN_Ignore2' ],
        std.get(r, 'alert', '')
      ),
    expected.patchedRules
  );

  if filtered.rules != expectedFiltered then
    error
      'Error in testFilterPatchRules:\n' +
      'Expected: %s\n' % [ expectedFiltered ] +
      'Got: %s\n' % [ filtered.rules ]
  else
    filtered;

local testFilterPatchRulesNoRecording =
  local filtered = alerts.filterPatchRules(
    { rules: testRulesRendered },
    ignoreNames=[ 'Ignore2' ],
    patches=testPatches {
      Ignore2: {
        expr: 'vector(2)',
        labels: {
          severity: 'info',
        },
      },
    },
    preserveRecordingRules=false,
    patchNames=true,
  );

  local expectedFiltered = std.filter(
    function(r)
      std.objectHas(r, 'alert') &&
      !std.member(
        // NOTE(sg): IgnoredAlert is in global ignore list; also we need to
        // filter `expected.patchedRules` using the prefixed names.
        [ 'SYN_IgnoredAlert', 'SYN_Ignore2' ],
        std.get(r, 'alert', '')
      ),
    expected.patchedRules
  );

  if filtered.rules != expectedFiltered then
    error
      'Error in testFilterPatchRulesNoRecording:\n' +
      'Expected: %s\n' % [ expectedFiltered ] +
      'Got: %s\n' % [ filtered.rules ]
  else
    filtered;

local testFilterPatchRulesNoRecordingOrigName =
  local filtered = alerts.filterPatchRules(
    { rules: testRulesRendered },
    ignoreNames=[ 'Ignore2' ],
    patches=testPatches {
      Ignore2: {
        expr: 'vector(2)',
        labels: {
          severity: 'info',
        },
      },
    },
    preserveRecordingRules=false,
    patchNames=false,
  );

  local expectedFiltered = [
    if r.alert != 'SYN_FooIsExtremelyLow' then
      r {
        alert: std.strReplace(r.alert, 'SYN_', ''),
      }
    else
      r
    for r in std.filter(
      function(r)
        std.objectHas(r, 'alert') &&
        !std.member(
          // NOTE(sg): IgnoredAlert is in global ignore list; also we need to
          // filter `expected.patchedRules` using the prefixed names.
          [ 'SYN_IgnoredAlert', 'SYN_Ignore2' ],
          std.get(r, 'alert', '')
        ),
      expected.patchedRules
    )
  ];

  if filtered.rules != expectedFiltered then
    error
      'Error in testFilterPatchRulesNoRecordingOrigName:\n' +
      'Expected: %s\n' % [ expectedFiltered ] +
      'Got: %s\n' % [ filtered.rules ]
  else
    filtered;

local testRenderGroups =
  local rendered = alerts.renderGroups(testRules, patches=testPatches);
  local expectedRules = [
    if std.objectHas(r, 'alert') && r.alert != 'SYN_FooIsExtremelyLow' then
      r {
        alert: std.strReplace(r.alert, 'SYN_', ''),
      }
    else
      r
    for r in std.filter(
      function(r) std.get(r, 'alert', '') != 'SYN_IgnoredAlert',
      expected.patchedRules
    )
  ];

  if rendered[0].rules != expectedRules then
    error
      'Error in testRenderGroups:\n' +
      'Expected: %s\n' % [ expectedRules ] +
      'Got: %s\n' % [ rendered[0].rules ]
  else
    rendered;

{
  patchedRules: testPatchRule,
  patchedRulesOrigName: testPatchRuleOrigName,
  filteredRules: testFilterRules,
  filteredRulesNoRecording: testFilterRulesNoRecording,
  filterPatchRules: testFilterPatchRules,
  filterPatchRulesNoRecording: testFilterPatchRulesNoRecording,
  filterPatchRulesNoRecordingOrigName: testFilterPatchRulesNoRecordingOrigName,
  renderedGroups: testRenderGroups,
}
