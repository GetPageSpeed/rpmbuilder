#!/bin/bash
# Fix up base repos in a way that we can install any packages at all ...

if [ -e /etc/os-release ]; then
   . /etc/os-release
else
   . /usr/lib/os-release
fi

if [ "$ID" = "opensuse-leap" ]; then
    echo "Do something Leap specific"
    zypper --non-interactive install dnf libdnf-repo-config-zypp
    # this repo has None for type=
    rm -rf /etc/zypp/repos.d/repo-backports-debug-update.repo
fi

RHEL=$(rpm -E 0%{?rhel})
# removes leading zeros, e.g. 07 becomes 0, but 0 stays 0
RHEL=${RHEL##+(0)}
echo $RHEL

if [[ $RHEL == 6 ]]; then
  curl https://www.getpagespeed.com/files/centos6-eol.repo --output /etc/yum.repos.d/CentOS-Base.repo
  rpm --rebuilddb && yum -y install yum-plugin-ovl
  yum -y install yum-plugin-ovl
  yum -y install centos-release-scl
  curl https://www.getpagespeed.com/files/centos6-scl-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl.repo
  curl https://www.getpagespeed.com/files/centos6-scl-rh-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo

  yum -y install epel-release
  curl https://www.getpagespeed.com/files/centos6-epel-eol.repo --output /etc/yum.repos.d/epel.repo
fi

if [[ $RHEL == 8 ]]; then
  # mirrorlist service is very often 503. avoid it by direct use
  sed -i 's@^#baseurl@baseurl@g' /etc/yum.repos.d/Rocky-*.repo
  sed -i 's@^mirrorlist@#mirrorlist@g' /etc/yum.repos.d/Rocky-*.repo
fi

