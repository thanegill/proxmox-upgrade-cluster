# proxmox-upgrade-cluster

proxmox-upgrade-cluster.sh is a Bash script that performs a rolling upgrade of
a Proxmox cluster. It automates the upgrade and optional reboot of one or more
nodes.

## Features

* Can automatically determine cluster members.
* Upgrade all or specific nodes in a Proxmox cluster.
* Reboot nodes only when needed, or can optionally force a reboot.
* Optional force package reinstall after upgrade.
* Testing mode `--testing` that performs no-ops.

## Requirements

* Bash
* SSH access to all Proxmox nodes
* jq installed on your system, can be specified with `--jq-bin`.


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
        Node(s) to upgrade. Can be passed muliple times.

    -u USER, --ssh-user USER
        SSH user to authenticate with. Defaults to "root".

    -o SSH_OPT, --ssh-opt SSH_OPT
        Options to pass to ssh. Can be passed muliple times.

    --ssh-allow-password-auth
        Default is to force SSH key auth with 'PasswordAuthentication=no'. Set
        this to allow ssh passworf auth. This is strongly recommended against.
        You may have to enter your password hundereds of times.

    --cluster-node-use-ip
        When using '--cluster-node', use the IP address instead of the node name.

    --testing
        Flag to enable a testing mode where no actions are taken.

    --pkg-reinstall PACKAGE
        Package(s) on the hosts to reinstall with 'apt-get reinstall' post
        upgrade. Can be passed muliple times. Defaults to "proxmox-truenas"

    --force-upgrade
        Flag to force all nodes to upgrade, and not only those with avaible upgrades.

    --force-reboot
        Flag to force all nodes to be rebooted durring upgrade, and not only
        those that aren't booted with the same kernal as the currenlty installed
        one.

    --jq-bin PATH
        Path to 'jq' binary.

    -v, --verbose
        Log actions and details to stdout. When multiple -v options are given,
        enable verbose logging for de-bugging purposes.

    -h, --help
        Show this message.

EXAMPLE

    Upgrade all nodes in a cluster, retreiving the cluster nodes from 'pve1':

        proxmox-upgrade-cluster.sh -c pve1


    Upgrade only nodes pve2, pve3:

        proxmox-upgrade-cluster.sh -n pve2 -n pve3
```

## License

This script is provided as-is under the GNU v3 License. Use at your own risk.
