# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Detect available updates with `apt-get -s dist-upgrade` instead of
  `apt-get -s upgrade`, matching the resolver `node_upgrade` actually runs.
  Plain `upgrade` holds back changes that need new packages — notably a new
  Proxmox kernel — so affected nodes were reported as having no updates and
  silently dropped from the upgrade sequence.
- Fail fast when the HA CRM (`pve-ha-crm`) is not reporting node states.
  Previously a null/empty `manager_status` made the offline pre-flight check
  silently pass as "all online" (a swallowed `jq` error inside a process
  substitution) and could make the maintenance-mode wait spin forever.
  `node_get_offline_nodes` now checks the CRM service and names the node so the
  health check aborts with a clear message; `node_reached_mode` aborts on a
  null mode instead of waiting indefinitely.
- Log "Node is down." on the `wait_all` health-check path. Under active
  `errexit` the failing SSH pipeline aborted `is_node_up` before its status was
  captured, so the down branch never logged.
- Reboot and follow the shutdown `dmesg` over a single SSH session. The
  previous separate `dmesg -W` connection often could not establish because the
  node was already tearing down, so the shutdown log was lost.

### Changed

- `node_ssh` passes its arguments as `options, host, command` (the conventional
  `ssh [options] host command` form), consistent with `close_ssh_masters`.
  Behavior is unchanged.

## [0.0.1] - 2026-06-10

Initial baseline.

[Unreleased]: https://github.com/thanegill/proxmox-upgrade-cluster/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/thanegill/proxmox-upgrade-cluster/releases/tag/v0.0.1
