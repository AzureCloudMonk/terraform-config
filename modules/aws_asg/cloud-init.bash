#!/usr/bin/env bash
# vim:filetype=sh
set -o errexit
set -o pipefail
shopt -s nullglob

main() {
  : "${ETCDIR:=/etc}"
  : "${VARTMP:=/var/tmp}"
  : "${RUNDIR:=/var/tmp/travis-run.d}"

  local instance_id
  instance_id="$(cat "${RUNDIR}/instance-id")"

  for envfile in "${ETCDIR}/default/travis-worker"*; do
    sed -i "s/___INSTANCE_ID___/${instance_id}/g" "${envfile}"
  done

  __set_aio_max_nr

  chown -R travis:travis "${RUNDIR}"

  if [[ -d "${ETCDIR}/systemd/system" ]]; then
    cp -v "${VARTMP}/travis-worker.service" \
      "${ETCDIR}/systemd/system/travis-worker.service"
    systemctl enable travis-worker || true
  fi

  if [[ -d "${ETCDIR}/init" ]]; then
    cp -v "${VARTMP}/travis-worker.conf" \
      "${ETCDIR}/init/travis-worker.conf"
  fi

  service travis-worker stop || true
  service travis-worker start || true

  iptables -t nat -I PREROUTING -p tcp -d '169.254.169.254' \
    --dport 80 -j DNAT --to-destination '192.0.2.1'

  __wait_for_docker

  local registry_hostname
  registry_hostname="$(cat "${RUNDIR}/registry-hostname")"

  set +o pipefail
  set +o errexit
  dig +short "${registry_hostname}" | while read -r ipv4; do
    iptables -I DOCKER -s "${ipv4}" -j DROP || true
  done

  __install_sysdig
}

get_env() {
  if [[ "$(hostname)" == *"staging"* ]]; then
    echo "staging"
  else
    echo "production"
  fi
}

__install_sysdig() {
  echo "Installing Sysdig..."
  source /etc/default/travis-worker
  source /etc/default/travis-worker-cloud-init
  if [ -z "${TRAVIS_WORKER_SYSDIG_ACCESS_KEY}" ]; then
    echo "TRAVIS_WORKER_SYSDIG_ACCESS_KEY not defined! Aborting."
    exit 1
  fi
  # Note: this is a temporary measure to install Sysdig at runtime.
  # If Sysdig is adopted we should instead install it in packer-templates.
  curl -s https://s3.amazonaws.com/download.draios.com/stable/install-sysdig | sudo bash
  curl -s https://s3.amazonaws.com/download.draios.com/stable/install-agent | sudo bash -s -- --access_key "$TRAVIS_WORKER_SYSDIG_ACCESS_KEY" --tags "site:$TRAVIS_WORKER_TRAVIS_SITE,env:$(get_env)"
  echo "Sysdig installed."
}

__wait_for_docker() {
  local i=0

  while ! docker version; do
    if [[ $i -gt 600 ]]; then
      exit 86
    fi
    start docker &>/dev/null || true
    sleep 10
    let i+=10
  done
}

__set_aio_max_nr() {
  # NOTE: we do this mostly to ensure file IO chatty services like mysql will
  # play nicely with others, such as when multiple containers are running mysql,
  # which is the default on trusty.  The value we set here is 16^5, which is one
  # power higher than the default of 16^4 :sparkles:.
  sysctl -w fs.aio-max-nr=1048576
}

main "$@"
