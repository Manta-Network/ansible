#!/bin/bash

PLAYBOOK_PATH=${PLAYBOOK_PATH:-/home/$(whoami)/ansible}

if [ ! -d ${PLAYBOOK_PATH} ]; then
  echo "missing folder specified by PLAYBOOK_PATH: ${PLAYBOOK_PATH}"
  exit 1
fi

declare -a packages=()
packages+=( ansible )
packages+=( git )
packages+=( jq )
packages+=( python3 )
packages+=( python3-pip )

declare -a pip_packages=()
pip_packages+=( pip )
pip_packages+=( yq )

_decode_property() {
  echo ${1} | base64 --decode | jq -r ${2}
}

# install ansible repository
if [ "$(sha256sum /etc/apt/sources.list.d/ubuntu-ansible-focal.list 2>/dev/null | cut -d' ' -f1 2>/dev/null)" != "e6b8a680bee6f3a23b556cc47bac358069dab91e9c5367a3a7651c10cb9c5d02" ]; then
  sudo sh -c 'echo deb http://ppa.launchpad.net/ansible/ansible/ubuntu focal main > /etc/apt/sources.list.d/ubuntu-ansible-focal.list'
  sudo apt update
fi

# install os package manager packages depended on by this script
for package in ${packages[@]}; do
  if dpkg -l ${package} &>/dev/null; then
    echo "package install validated: ${package}"
  elif sudo apt install -y ${package} &>/dev/null; then
    echo "package installed: ${package}"
  else
    echo "package missing and installation failed: ${package}"
    exit 1
  fi
done

# install pip packages depended on by this script
for package in ${pip_packages[@]}; do
  if pip show ${package} &>/dev/null; then
    echo "pip package install validated: ${package}"
  elif sudo pip install --quiet ${package} &>/dev/null; then
    echo "pip package installed: ${package}"
  else
    echo "pip package missing and installation failed: ${package}"
    exit 1
  fi
done

cd ${PLAYBOOK_PATH}

# update playbooks
git pull > /tmp/ansible-pull.log

list=( $(/usr/local/bin/yq -r '.[] | @base64' ${PLAYBOOK_PATH}/ci/autorun.yml) )
for x in ${list[@]}; do
  playbook=$(_decode_property ${x} .playbook)
  template=$(_decode_property ${x} .template)

  # when template has changed, run playbook
  if grep -q "${template}" /tmp/ansible-pull.log; then
    ansible-playbook ${playbook}.yml
  else
    echo "playbook: ${playbook} skipped. no change detected for template: ${template}"
  fi
done
