#
# MIT License
#
# (C) Copyright 2022,2024-2025 Hewlett Packard Enterprise Development LP
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
Name: %(echo $NAME)
License: MIT
Summary: Daemon for running Nexus repository manager
BuildArch: x86_64
Version: %(echo $VERSION)
Release: 3.70.4
Source1: nexus.service
Source2: nexus-init.sh
Source3: nexus-setup.sh
Source: %{name}-%{version}.tar.bz2
Vendor: Hewlett Packard Enterprise Development LP
BuildRequires: coreutils
BuildRequires: docker
BuildRequires: sed
BuildRequires: skopeo
BuildRequires: pkgconfig(systemd)
Requires: podman
Requires: podman-cni-config
# Legacy name.
Provides: pit-nexus
%{?systemd_ordering}

%define imagedir %{_sharedstatedir}/cray/container-images/%{name}

%define current_branch %(echo ${GIT_BRANCH} | sed -e 's,/.*$,,')
%define sonatype_nexus3_tag   %(echo %{release} | sed 's/_/-/')
%define sonatype_nexus3_image artifactory.algol60.net/csm-docker/stable/docker.io/sonatype/nexus3:%{sonatype_nexus3_tag}
%define sonatype_nexus3_file  sonatype-nexus3-%{sonatype_nexus3_tag}.tar

%define cray_nexus_setup_tag   0.11.0
%define cray_nexus_setup_image artifactory.algol60.net/csm-docker/stable/cray-nexus-setup:%{cray_nexus_setup_tag}
%define cray_nexus_setup_file  cray-nexus-setup-%{cray_nexus_setup_tag}.tar

%define skopeo_tag          latest
%define skopeo_source_image artifactory.algol60.net/csm-docker/stable/quay.io/skopeo/stable:v1
%define skopeo_image        quay.io/skopeo/stable
%define skopeo_file         skopeo-stable-%{skopeo_tag}.tar

%{!?_unitdir:
%define _unitdir /usr/lib/systemd/system
}

%if "%(echo ${IS_STABLE})" == "true"
%define bucket csm-docker/stable
%else
%define bucket csm-docker/unstable
%endif

%description
This RPM installs the daemon file for Nexus, launched through podman. This allows nexus to launch
as a systemd service on a system.

%prep
rm -fr "%{name}-%{version}"
mkdir "%{name}-%{version}"
cd "%{name}-%{version}"

%build
cp %{SOURCE1} nexus.service
sed -e 's,@@sonatype-nexus3-image@@,%{sonatype_nexus3_image},g' \
    -e 's,@@sonatype-nexus3-path@@,%{imagedir}/%{sonatype_nexus3_file},g' \
    %{SOURCE2} > nexus-init.sh
sed -e 's,@@cray-nexus-setup-image@@,%{cray_nexus_setup_image},g' \
    -e 's,@@cray-nexus-setup-path@@,%{imagedir}/%{cray_nexus_setup_file},g' \
    %{SOURCE3} > nexus-setup.sh
# Consider switching to skopeo copy --all docker://<src> oci-archive:<dest>
skopeo --override-arch amd64 --override-os linux copy --src-creds=%(echo $ARTIFACTORY_USER:$ARTIFACTORY_TOKEN) docker://%{sonatype_nexus3_image}  docker-archive:%{sonatype_nexus3_file}:%{sonatype_nexus3_image}
skopeo --override-arch amd64 --override-os linux copy --src-creds=%(echo $ARTIFACTORY_USER:$ARTIFACTORY_TOKEN) docker://%{cray_nexus_setup_image} docker-archive:%{cray_nexus_setup_file}:%{cray_nexus_setup_image}
skopeo --override-arch amd64 --override-os linux copy --src-creds=%(echo $ARTIFACTORY_USER:$ARTIFACTORY_TOKEN) docker://%{skopeo_source_image}    docker-archive:%{skopeo_file}:%{skopeo_image}:%{skopeo_tag}

%install
install -D -m 0644 -t %{buildroot}%{_unitdir} nexus.service
install -D -m 0755 -t %{buildroot}%{_sbindir} nexus-init.sh nexus-setup.sh
ln -s %{_sbindir}/service %{buildroot}%{_sbindir}/rcnexus
install -D -m 0644 -t %{buildroot}%{imagedir} \
    %{sonatype_nexus3_file} \
    %{cray_nexus_setup_file} \
    %{skopeo_file}

%clean
rm -f \
    nexus.service \
    nexus-init.sh \
    nexus-setup.sh \
    %{sonatype_nexus3_file} \
    %{cray_nexus_setup_file} \
    %{skopeo_file}

%pre
%service_add_pre nexus.service

%post
%service_add_post nexus.service

%preun
%service_del_preun nexus.service

%postun
%service_del_postun nexus.service
podman stop nexus || echo 'No nexus container was running, nothing to stop.'
podman rm nexus || echo 'No nexus container was created, nothing to delete.'
podman rmi %{sonatype_nexus3_image} || echo 'No nexus image was loaded, nothing to remove.'
podman rmi %{cray_nexus_setup_image} || echo 'No nexus image was loaded, nothing to remove.'

# Only delete the volume on an uninstall.
if [ $1 -eq 0 ]; then
podman volume remove nexus-data || echo 'nexus-data volume does not exist, nothing to remove'
fi

%files
%defattr(-,root,root)
%{_unitdir}/nexus.service
%{_sbindir}/nexus-init.sh
%{_sbindir}/nexus-setup.sh
%{_sbindir}/rcnexus
%{imagedir}/%{sonatype_nexus3_file}
%{imagedir}/%{cray_nexus_setup_file}
%{imagedir}/%{skopeo_file}

%changelog
