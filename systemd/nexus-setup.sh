#!/bin/bash

# Copyright 2021 Hewlett Packard Enterprise Development LP

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

if ! podman image inspect "$NEXUS_SETUP_IMAGE" >/dev/null; then
    podman load -i "$NEXUS_SETUP_IMAGE_PATH" "$NEXUS_SETUP_IMAGE" || exit
fi

# Setup Nexus container (assumes Nexus is at http://localhost:8081)
podman run --rm --network host \
    "$NEXUS_SETUP_IMAGE" \
    /bin/sh -c "
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
