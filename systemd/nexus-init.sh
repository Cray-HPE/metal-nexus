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
# Using sonatype/nexus3:latest introduced an NPE issue with proxying to
# helmrepo.dev.cray.com.
NEXUS_IMAGE="@@sonatype-nexus3-image@@"
NEXUS_IMAGE_PATH="@@sonatype-nexus3-path@@"

command -v podman >/dev/null 2>&1 || { echo >&2 "${0##*/}: command not found: podman"; exit 1; }

if [ $# -lt 2 ]; then
    echo >&2 "usage: nexus-init PIDFILE CIDFILE [CONTAINER [VOLUME]]"
    exit 1
fi

NEXUS_PIDFILE="$1"
NEXUS_CIDFILE="$2"
NEXUS_CONTAINER_NAME="${3-nexus}"
NEXUS_VOLUME_NAME="${4:-${NEXUS_CONTAINER_NAME}-data}"

NEXUS_VOLUME_MOUNT="/nexus-data:rw,exec"

# Create Nexus volume if not already present
if ! podman volume inspect "$NEXUS_VOLUME_NAME" &>/dev/null; then
    # Load busybox image if it doesn't already exist
    if ! podman image inspect "$NEXUS_IMAGE" &>/dev/null; then
        # load the image
        podman load -i "$NEXUS_IMAGE_PATH" || exit
        # get the tag
        NEXUS_IMAGE_ID=$(podman images --noheading --format "{{.Id}}" --filter label="name=Nexus Repository Manager")
        # tag the image
        podman tag "$NEXUS_IMAGE_ID" "$NEXUS_IMAGE"
    fi
    podman run --rm --network host \
        -v "${NEXUS_VOLUME_NAME}:${NEXUS_VOLUME_MOUNT}" \
        "$NEXUS_IMAGE" /bin/sh -c "
mkdir -p /nexus-data/etc
cat > /nexus-data/etc/nexus.properties << EOF
nexus.onboarding.enabled=false
nexus.scripts.allowCreation=true
nexus.security.randompassword=false
EOF
chown -Rv 200:200 /nexus-data
chmod -Rv u+rwX,go+rX,go-w /nexus-data
" || exit
    podman volume inspect "$NEXUS_VOLUME_NAME" || exit
fi

# always ensure pid file is fresh
rm -f "$NEXUS_PIDFILE"

# Create Nexus container
if ! podman inspect --type container "$NEXUS_CONTAINER_NAME" &>/dev/null; then
    rm -f "$NEXUS_CIDFILE" || exit
    # Load nexus image if it doesn't already exist
    if ! podman image inspect "$NEXUS_IMAGE" &>/dev/null; then
        # load the image
        podman load -i "$NEXUS_IMAGE_PATH"
        # get the tag
        NEXUS_IMAGE_ID=$(podman images --noheading --format "{{.Id}}" --filter label="name=Nexus Repository Manager")
        # tag the image
        podman tag "$NEXUS_IMAGE_ID" "$NEXUS_IMAGE"
    fi
    podman create \
        --conmon-pidfile "$NEXUS_PIDFILE" \
        --cidfile "$NEXUS_CIDFILE" \
        --cgroups=no-conmon \
        --network host \
        --volume "${NEXUS_VOLUME_NAME}:${NEXUS_VOLUME_MOUNT}" \
        --name "$NEXUS_CONTAINER_NAME" \
        "$NEXUS_IMAGE" || exit
    podman inspect "$NEXUS_CONTAINER_NAME" || exit
fi
