#!/bin/bash
# Fix up things so that things work fine and do not break while building
# Ensures required default repos as well

RHEL=$(rpm -E 0%{?rhel})
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
RHEL=${RHEL##+(0)}
echo $RHEL

if ((RHEL >= 0 && RHEL <= 7)); then
  patch /usr/bin/yum-builddep --forward /tmp/yum-builddep.patch
  # because we patched yum, versionlock ше:
  yum -y install yum-plugin-versionlock
  yum versionlock yum-utils
fi

if (( RHEL >= 8 )); then
  dnf config-manager --enable powertools
fi

if test -f /etc/dnf/dnf.conf; then
  sed -i 's@best=True@best=0@' /etc/dnf/dnf.conf
fi

