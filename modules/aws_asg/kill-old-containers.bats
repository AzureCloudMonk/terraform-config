#!/usr/bin/env bats

load bats_helpers

setup() {
  aws_asg_setup
}

teardown() {
  aws_asg_teardown
}

run_kill_old_containers() {
  bash "${BATS_TEST_DIRNAME}/kill-old-containers.bash"
}

@test "is a no-op if there are no containers" {
  cat >"${BATS_TMPDIR}/returns/docker" <<EOF
EOF

  cat >"${BATS_TMPDIR}/returns/date" <<EOF
20171030T153252
EOF

  run run_kill_old_containers

  [ "${status}" -eq 0 ]
  assert_cmd "kill-old-containers tag=cron time=20171030T153252 level=info msg=\"cron finished\" status=warning killed=0 running=0"
}

@test "is a no-op if only travis-worker container is running" {
  cat >"${BATS_TMPDIR}/returns/date" <<EOF
20171030T153252
EOF

  cat >"${BATS_TMPDIR}/returns/docker" <<EOF
/travis-worker
EOF

  run run_kill_old_containers

  [ "${status}" -eq 0 ]

  assert_cmd "kill-old-containers tag=cron time=20171030T153252 level=info msg=\"cron finished\" status=noop killed=0 running=1"
}
