# proxmox-upgrade-cluster

`proxmox-upgrade-cluster.sh` is a Bash script that performs a rolling upgrade of
a Proxmox cluster. It automates the upgrade and optional reboot of one or more
nodes.

## Features

* Automatically determine cluster members (`-c HOSTNAME`).
* Upgrade all or specific nodes (`-n HOSTNAME`).
* Reboot nodes only when needed, or can optionally force a reboot (`--force-reboot`).
* Optionally force package reinstallation after upgrade (`--pkg-reinstall PACKAGE`).
* No-op mode (`--dry-run`).
* Multiple levels of verbosity (`-v`, `-vv`, `-vvv`).

## Requirements

* Bash 4.4 or newer
* SSH access to all Proxmox nodes
* [jq](https://jqlang.org/) installed on your system and on `PATH`.

## Assumptions, omissions, and possible future features

* Cluster HA is enabled with all guests managed.
* SSH is available to all nodes (outside of reboots) to all nodes while the running.
* That running this script is not stopped mid-run. Currently, it doesn't to any cleanup or checking to make sure the cluster is left in a working state. Manual intervention may be needed if exiting or errors occur.
* SSH Key Auth is set up and working for the root user. Users other than root have not been tested.
* No rebalancing or guest migration outside the cluster HA. Recommended rebalancing after either manually or with other tools.


## Usage
``` man
NAME
    proxmox-upgrade-cluster.sh - Perform a rolling upgrade for a Proxmox cluster

SYNOPSIS
    proxmox-upgrade-cluster.sh [OPTIONS] --cluster-node|-c [NODE]

    proxmox-upgrade-cluster.sh [OPTIONS] --node|-n [NODE] -n [NODE] [...]

    proxmox-upgrade-cluster.sh --help

OPTIONS

    -c HOSTNAME, --cluster-node HOSTNAME
        A node in a cluster to pull all nodes from.

    -n HOSTNAME, --node HOSTNAME
        Node(s) to upgrade. Can be passed multiple times.

    -u USER, --ssh-user USER
        SSH user to authenticate with. Defaults to "root".

    -o SSH_OPT, --ssh-opt SSH_OPT
        Options to pass to ssh. Can be passed multiple times.

    --ssh-allow-password-auth
        Default is to force SSH key auth with 'PasswordAuthentication=no'. Set
        this to allow ssh password auth. This is strongly recommended against.
        You may have to enter your password hundreds of times.

    --cluster-node-use-ip
        When using '--cluster-node', use the IP address instead of the node name.

    --dry-run
        Flag to enable a dry run mode where no actions are taken.

    --pkg-reinstall PACKAGE
        Package(s) on the hosts to reinstall with 'apt-get reinstall' post
        upgrade. Can be passed multiple times. Defaults to "".

    --force-upgrade
        Flag to force all nodes to upgrade, and not only those with available upgrades.

    --force-reboot
        Flag to force all nodes to be rebooted during upgrade, and not only
        those that aren't booted with the same kernel as the currently installed
        one.

    --skip-reboot
        Flag to skip the reboot step entirely, even when a new kernel is
        staged for boot. Mutually exclusive with --force-reboot. The operator
        is responsible for rebooting later to pick up any new kernel.

    --no-maintenance-mode
        Don't set node to maintenance mode when upgrading. This will disable
        HA migrations.

    --allow-running-guests
        Disable check for running guests on the node prior to upgrade.

    --allow-running-tasks
        Disable check for running tasks on the cluster prior to upgrade.

    --preserve-discovery-order
        When using --cluster-node, do not reorder the upgrade sequence
        ascending by running guest count. Default is to sort so the node
        with the fewest guests upgrades first.

    -v, --verbose
        Log actions and details to stdout. When multiple -v options are given,
        enable verbose logging for de-bugging purposes.

    -h, --help
        Show this message.

EXAMPLE

    Upgrade all nodes in a cluster, retrieving the cluster nodes from 'pve1':

        proxmox-upgrade-cluster.sh -c pve1


    Upgrade only nodes pve2, pve3:

        proxmox-upgrade-cluster.sh -n pve2 -n pve3
```

## Example very-verbose dry run
```shell
> ./proxmox-upgrade-cluster.sh -c pve1 -vv --dry-run
[2026-01-26 17:26:08] Running in dry run mode.
[2026-01-26 17:26:08] Getting all cluster nodes from node 'pve1'...
[2026-01-26 17:26:08] [pve1] Running command 'whoami'
[2026-01-26 17:26:08] [pve1] Running command 'hash pvesh'
[2026-01-26 17:26:08] [pve1] Running command 'pvesh get cluster/status  --output-form=json'
[2026-01-26 17:26:10] Using 'pve2 pve1 pve3' as all nodes to check.
[2026-01-26 17:26:10] Checking if any nodes are not proxmox...
[2026-01-26 17:26:10] [pve2] Running command 'hash pvesh'
[2026-01-26 17:26:10] [pve1] Running command 'hash pvesh'
[2026-01-26 17:26:10] [pve3] Running command 'hash pvesh'
[2026-01-26 17:26:10] All nodes are proxmox.
[2026-01-26 17:26:10] Checking if any nodes are currently down...
[2026-01-26 17:26:10] [pve2] Running command 'whoami'
[2026-01-26 17:26:10] [pve2] Node is up.
[2026-01-26 17:26:10] [pve1] Running command 'whoami'
[2026-01-26 17:26:11] [pve1] Node is up.
[2026-01-26 17:26:11] [pve3] Running command 'whoami'
[2026-01-26 17:26:11] [pve3] Node is up.
[2026-01-26 17:26:11] All nodes are up.
[2026-01-26 17:26:11] Checking if any nodes are currently not online...
[2026-01-26 17:26:11] [pve2] Running command 'pvesh get cluster/ha/status/manager_status  --output-form=json'
[2026-01-26 17:26:12] All nodes are online.
[2026-01-26 17:26:12] Checking if any nodes currently have tasks running...
[2026-01-26 17:26:12] [pve2] Running command 'pvesh get nodes/$(hostname)/tasks --source=active --output-form=json'
[2026-01-26 17:26:14] No tasks are running.
[2026-01-26 17:26:14] Checking for updates on all nodes...
[2026-01-26 17:26:14] [pve2] Running command 'DEBIAN_FRONTEND=noninteractive apt-get update'
[2026-01-26 17:26:15] [pve2]     Hit:1 https://deb.debian.org/debian trixie InRelease
[2026-01-26 17:26:15] [pve2]     Hit:2 https://deb.debian.org/debian trixie-updates InRelease
[2026-01-26 17:26:15] [pve2]     Hit:3 https://deb.debian.org/debian-security trixie-security InRelease
[2026-01-26 17:26:15] [pve2]     Hit:4 http://download.proxmox.com/debian/ceph-squid trixie InRelease
[2026-01-26 17:26:15] [pve2]     Hit:5 http://download.proxmox.com/debian/pve trixie InRelease
[2026-01-26 17:26:15] [pve2]     Reading package lists...
[2026-01-26 17:26:15] [pve1] Running command 'DEBIAN_FRONTEND=noninteractive apt-get update'
[2026-01-26 17:26:16] [pve1]     Hit:1 https://deb.debian.org/debian trixie InRelease
[2026-01-26 17:26:16] [pve1]     Hit:2 https://deb.debian.org/debian trixie-updates InRelease
[2026-01-26 17:26:16] [pve1]     Hit:3 https://deb.debian.org/debian-security trixie-security InRelease
[2026-01-26 17:26:16] [pve1]     Hit:4 http://download.proxmox.com/debian/ceph-squid trixie InRelease
[2026-01-26 17:26:16] [pve1]     Hit:5 http://download.proxmox.com/debian/pve trixie InRelease
[2026-01-26 17:26:16] [pve1]     Reading package lists...
[2026-01-26 17:26:16] [pve3] Running command 'DEBIAN_FRONTEND=noninteractive apt-get update'
[2026-01-26 17:26:17] [pve3]     Hit:1 https://deb.debian.org/debian trixie InRelease
[2026-01-26 17:26:17] [pve3]     Hit:2 https://deb.debian.org/debian trixie-updates InRelease
[2026-01-26 17:26:17] [pve3]     Hit:3 https://deb.debian.org/debian-security trixie-security InRelease
[2026-01-26 17:26:17] [pve3]     Hit:4 http://download.proxmox.com/debian/ceph-squid trixie InRelease
[2026-01-26 17:26:17] [pve3]     Hit:5 http://download.proxmox.com/debian/pve trixie InRelease
[2026-01-26 17:26:17] [pve3]     Reading package lists...
[2026-01-26 17:26:17] [pve2] Running command 'DEBIAN_FRONTEND=noninteractive apt-get -qq -s upgrade'
[2026-01-26 17:26:18] [pve2]
[2026-01-26 17:26:18] [pve2] No updates available.
[2026-01-26 17:26:18] [pve2] Removed from upgrade sequence.
[2026-01-26 17:26:18] [pve1] Running command 'DEBIAN_FRONTEND=noninteractive apt-get -qq -s upgrade'
[2026-01-26 17:26:18] [pve1]
[2026-01-26 17:26:18] [pve1] No updates available.
[2026-01-26 17:26:18] [pve1] Removed from upgrade sequence.
[2026-01-26 17:26:18] [pve3] Running command 'DEBIAN_FRONTEND=noninteractive apt-get -qq -s upgrade'
[2026-01-26 17:26:19] [pve3]
[2026-01-26 17:26:19] [pve3] No updates available.
[2026-01-26 17:26:19] [pve3] Removed from upgrade sequence.
[2026-01-26 17:26:19] No nodes need updates. Exiting.
```

## Testing

Tests are written using [ShellSpec](https://shellspec.info/) and run via Nix development shell:

```shell
nix develop -c shellspec spec/
```

Run a specific test file or tag:

```shell
nix develop -c shellspec spec/logging_spec.sh
nix develop -c shellspec spec/node_functions_spec.sh:@1-1
```

Tests mock all SSH and external commands. No Proxmox cluster is required to run the suite.

## License

This script is provided as-is under the GNU v3 License. Use at your own risk.
