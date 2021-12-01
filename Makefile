# Copyright 2021 Hewlett Packard Enterprise Development LP

ROOTDIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))

BUILD_METADATA ?= 1~development~$(shell git rev-parse --short HEAD)

.PHONY: rpm clean

rpm: pit-nexus.spec systemd/nexus.service systemd/nexus-init.sh systemd/nexus-setup.sh
	BUILD_METADATA="$(BUILD_METADATA)" rpmbuild --nodeps \
	    --define "_topdir $(CURDIR)/build" \
	    --define "_sourcedir $(ROOTDIR)systemd" \
	    -ba pit-nexus.spec

clean:
	$(RM) -r build
