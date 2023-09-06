#!/bin/bash
#
# MIT License
#
# (C) Copyright 2021-2022 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
NEXUS_SETUP_IMAGE="@@cray-nexus-setup-image@@"
NEXUS_SETUP_IMAGE_PATH="@@cray-nexus-setup-path@@"

command -v podman >/dev/null 2>&1 || { echo >&2 "${0##*/}: command not found: podman"; exit 1; }

function usage() {
    echo >&2 "${0##*/} [URL]"
    exit 2
}

[[ $# -le 1 ]] || usage

if [[ $# -eq 0 ]]; then
    # By default, use a hosted configuration
    config="type: hosted"
else
    # If URL is specified, use proxy configuration
    echo >&2 "warning: using proxy configuration: $1"
    config="type: proxy
proxy:
  contentMaxAge: 1440
  metadataMaxAge: 1
  remoteUrl: ${1}
dockerProxy:
  indexType: HUB
  indexUrl: null
httpClient:
  authentication: null
  autoBlock: false
  blocked: false
  connection:
    retries: 5
    userAgentSuffix: null
    timeout: 300
    enableCircularRedirects: false
    enableCookies: false
routingRule: null
negativeCache:
  enabled: false
  timeToLive: 0"
fi

set -x

if ! podman image inspect --type image "$NEXUS_SETUP_IMAGE" &>/dev/null; then
    # load the image
    podman load -i "$NEXUS_SETUP_IMAGE_PATH" || exit
    # get the image id
    CRAY_NEXUS_SETUP_ID=$(podman images --noheading --format "{{.Id}}" --filter label="org.label-schema.name=cray-nexus-setup")
    # tag the image
    podman tag "$CRAY_NEXUS_SETUP_ID" "$NEXUS_SETUP_IMAGE"
fi

# Setup Nexus container (assumes Nexus is at http://localhost:8081)
podman run --rm --network host \
    "$NEXUS_SETUP_IMAGE" \
    /bin/sh -c "
export NEXUS_URL=http://localhost:8081/nexus
while ! nexus-ready; do
  echo >&2 'Waiting for nexus to be ready, trying again in 10 seconds'
  sleep 10
done

# If the script already exists, Nexus API reports failure :-(
nexus-upload-script /usr/local/share/nexus-setup/groovy/*.groovy >&2

nexus-enable-anonymous-access >&2
nexus-remove-default-repos >&2

cat > /tmp/nexus-repositories.yaml << EOF
---
cleanup: null
docker:
  forceBasicAuth: false
  httpPort: 5000
  httpsPort: null
  v1Enabled: false
format: docker
name: registry
online: true
storage:
  blobStoreName: default
  strictContentTypeValidation: false
  writePolicy: ALLOW
${config}
EOF

nexus-repositories-create /tmp/nexus-repositories.yaml >&2
nexus-enable-docker-realm >&2
" || exit
