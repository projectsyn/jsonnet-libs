MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

include Makefile.vars.mk

.PHONY: jsonnetfmt_check jsonnetfmt
jsonnetfmt_check: JSONNET_ENTRYPOINT=jsonnetfmt
jsonnetfmt_check:
	$(JSONNET_DOCKER) --test --pad-arrays -- *.libsonnet

jsonnetfmt: JSONNET_ENTRYPOINT=jsonnetfmt
jsonnetfmt:
	$(JSONNET_DOCKER) --in-place --pad-arrays -- *.libsonnet

tests/lib/commodore-real.libjsonnet:
	@mkdir -p "tests/lib"
	curl -fsSLo "tests/lib/commodore-real.libjsonnet" https://raw.githubusercontent.com/projectsyn/commodore/refs/heads/master/commodore/lib/commodore.libjsonnet

.PHONY: gen-golden
gen-golden: tests/lib/commodore-real.libjsonnet
	$(JSONNET_DOCKER) tests/run-instance.sh $(instance) > tests/golden/$(instance).yml

.PHONY: golden-diff
golden-diff: tests/lib/commodore-real.libjsonnet
	@mkdir -p /tmp/golden
	$(JSONNET_DOCKER) tests/run-instance.sh $(instance) > /tmp/golden/$(instance).yml
	@git diff --exit-code --minimal --no-index -- tests/golden/$(instance).yml /tmp/golden/$(instance).yml

.PHONY: golden-diff-all
golden-diff-all: recursive_target=golden-diff
golden-diff-all: $(test_instances)

.PHONY: gen-golden-all
gen-golden-all: recursive_target=gen-golden
gen-golden-all: $(test_instances)

.PHONY: $(test_instances)
$(test_instances):
	$(MAKE) $(recursive_target) -e instance=$(basename $(@F))

.PHONY: list_test_instances
list_test_instances: JSONNET_ENTRYPOINT=jsonnet
list_test_instances:
	$(JSONNET_DOCKER) -J . -J tests --ext-str instances="$(basename $(notdir $(test_instances)))" -e 'std.split(std.extVar("instances"), " ")' | jq -c
