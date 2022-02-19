#!/bin/bash

if [[ $(rpm -E %{amzn}) == 2 ]]; then
  sed -i "s@redhat/7@amzn/2@g" /etc/yum.repos.d/getpagespeed-extras.repo
fi