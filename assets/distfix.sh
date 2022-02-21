#!/bin/bash

${YUM} -y install ${PRE_PRE_PACKAGES}

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

if [[ $(rpm -E %{rhel}) == 6 ]]; then
  curl https://www.getpagespeed.com/files/centos6-eol.repo --output /etc/yum.repos.d/CentOS-Base.repo
  rpm --rebuilddb && yum -y install yum-plugin-ovl
  yum -y install yum-plugin-ovl
  yum -y install centos-release-scl
  curl https://www.getpagespeed.com/files/centos6-scl-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl.repo
  curl https://www.getpagespeed.com/files/centos6-scl-rh-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo
  yum -y install yum-plugin-versionlock
  yum -y install epel-release
  curl https://www.getpagespeed.com/files/centos6-epel-eol.repo --output /etc/yum.repos.d/epel.repo
  yum versionlock yum yum-utils epel-release
  yum clean all
fi


if [[ $(rpm -E %{rhel}) == 8 ]]; then
  # mirrorlist service is very often 503. avoid it by direct use
  sed -i 's@^#baseurl@baseurl@g' /etc/yum.repos.d/Rocky-*.repo
  sed -i 's@^mirrorlist@#mirrorlist@g' /etc/yum.repos.d/Rocky-*.repo
fi

sed -ri 's@^default_grabber\.opts\.user_agent\s+.*@default_grabber.opts.user_agent = "rpmbuilder"@' /usr/lib/python2.7/site-packages/yum/__init__.py  ||:
sed -ri 's@^default_grabber\.opts\.user_agent\s+.*@default_grabber.opts.user_agent = "rpmbuilder"@' /usr/lib/python2.6/site-packages/yum/__init__.py  ||:
stat /usr/lib/python3.6/site-packages/dnf-plugins && cp /tmp/rpmbuilder_ua.py /usr/lib/python3.6/site-packages/dnf-plugins/  ||:
rm -rf /usr/lib/yum-plugins/
