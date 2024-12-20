#!/bin/bash

set -e -u -x

testdir=$(dirname "$0")
instance="${testdir}/${1}"

cat > "${testdir}/lib/commodore.libjsonnet" <<EOF
local com = import 'lib/commodore-real.libjsonnet';
com {
  inventory(): std.parseYaml(importstr '${1}.yaml'),
}
EOF

jsonnet -J . -J "${testdir}" "${instance}".jsonnet
