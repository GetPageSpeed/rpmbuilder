#!/bin/bash

if [[ $(rpm -E %{rhel}) == 6 ]]; then
  curl https://www.getpagespeed.com/files/centos6-eol.repo --output /etc/yum.repos.d/CentOS-Base.repo
  yum -y install centos-release-scl
  curl https://www.getpagespeed.com/files/centos6-scl-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl.repo
  curl https://www.getpagespeed.com/files/centos6-scl-rh-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo
fi

sed -ri 's@^default_grabber\.opts\.user_agent\s+.*@default_grabber.opts.user_agent = "rpmbuilder"@' /usr/lib/python2.7/site-packages/yum/__init__.py  ||:
sed -ri 's@^default_grabber\.opts\.user_agent\s+.*@default_grabber.opts.user_agent = "rpmbuilder"@' /usr/lib/python2.6/site-packages/yum/__init__.py  ||:
stat /usr/lib/python3.6/site-packages/dnf-plugins && cp /tmp/rpmbuilder_ua.py /usr/lib/python3.6/site-packages/dnf-plugins/  ||:
rm -rf /usr/lib/yum-plugins/