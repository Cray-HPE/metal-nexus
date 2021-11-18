# Copyright 2021 Hewlett Packard Enterprise Development LP

Name: cray-nexus
License: MIT
Summary: Daemon for running Nexus repository manager
BuildArch: x86_64
Version: 1.0.0
Release: 1.%(echo ${BUILD_METADATA})
Source0: nexus.service
Source1: nexus-init.sh
Source2: nexus-setup.sh
Vendor: Hewlett Packard Enterprise Development LP
BuildRequires: coreutils
BuildRequires: docker
BuildRequires: sed
BuildRequires: skopeo
BuildRequires: pkgconfig(systemd)
Requires: podman
Requires: podman-cni-config
%{?systemd_ordering}

%define imagedir %{_sharedstatedir}/cray/container-images/%{name}

%define sonatype_nexus3_tag   3.25.0
%define sonatype_nexus3_image artifactory.algol60.net/csm-docker/stable/docker.io/sonatype/nexus3:%{sonatype_nexus3_tag}
%define sonatype_nexus3_file  sonatype-nexus3-%{sonatype_nexus3_tag}.tar

%define cray_nexus_setup_tag   0.5.2
%define cray_nexus_setup_image artifactory.algol60.net/csm-docker/stable/cray-nexus-setup:%{cray_nexus_setup_tag}
%define cray_nexus_setup_file  cray-nexus-setup-%{cray_nexus_setup_tag}.tar

%define skopeo_tag   latest
%define skopeo_image quay.io/skopeo/stable
%define skopeo_file  skopeo-stable-%{skopeo_tag}.tar

%{!?_unitdir:
%define _unitdir /usr/lib/systemd/system
}

%description
This RPM installs the daemon file for Nexus, launched through podman. This allows nexus to launch
as a systemd service on a system.

%prep
rm -fr "%{name}-%{version}"
mkdir "%{name}-%{version}"
cd "%{name}-%{version}"

%build
cp %{SOURCE0} nexus.service
sed -e 's,@@sonatype-nexus3-image@@,%{sonatype_nexus3_image},g' \
    -e 's,@@sonatype-nexus3-path@@,%{imagedir}/%{sonatype_nexus3_file},g' \
    %{SOURCE1} > nexus-init.sh
sed -e 's,@@cray-nexus-setup-image@@,%{cray_nexus_setup_image},g' \
    -e 's,@@cray-nexus-setup-path@@,%{imagedir}/%{cray_nexus_setup_file},g' \
    %{SOURCE2} > nexus-setup.sh
# Consider switching to skopeo copy --all docker://<src> oci-archive:<dest>
skopeo --override-arch amd64 --override-os linux copy docker://%{sonatype_nexus3_image}  docker-archive:%{sonatype_nexus3_file}
skopeo --override-arch amd64 --override-os linux copy docker://%{cray_nexus_setup_image} docker-archive:%{cray_nexus_setup_file}
skopeo --override-arch amd64 --override-os linux copy docker://%{skopeo_image}           docker-archive:%{skopeo_file}

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
