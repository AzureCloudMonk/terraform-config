#cloud-config
# vim:filetype=yaml

write_files:
- content: '${base64encode(github_users_env)}'
  encoding: b64
  path: /etc/default/github-users
- content: '${base64encode(nat_config)}'
  encoding: b64
  path: /etc/default/nat
- content: '${base64encode(file("${assets}/nat/travis-nat-health-check"))}'
  encoding: b64
  path: /usr/local/bin/travis-nat-health-check
  permissions: '0750'
- content: '${base64encode(cloud_init_bash)}'
  encoding: b64
  path: /var/lib/cloud/scripts/per-instance/99-nat-cloud-init
  permissions: '0750'
- content: '${base64encode(file("${assets}/nat/travis-nat-health-check.service"))}'
  encoding: b64
  path: /var/tmp/travis-nat-health-check.service
- content: '${base64encode(syslog_address)}'
  encoding: b64
  path: /var/tmp/travis-run.d/syslog-address