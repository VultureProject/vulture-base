# The base package for Vulture 4 Operating System

## Prerequisite

To install vulture-base, you will need a **HardenedBSD 12-STABLE**.

That instance must run on a **ZFS disk configuration** with the default pool **"zroot"**. 
ZFS encryption is supported, but be aware that automatic bootup will no be possible in this case as you will have to type in your passphrase at every reboot. <br>
If you wish to have full disk-encryption AND automatic boot, you may wish to download our [prepackaged versions](https://download.vultureproject.org/v4/12.1/isos/).

It is also advised to create a **admin user** before starting as you won't be anymore allowed to use root over ssh for instance. Do not forget to add that user into **sudoers** file. <br>

## Installation

Firstly, install **root certificates from certificate authorities** : <br>
`pkg update`<br>
`pkg install ca_root_nss`

Then, add **repository signature** to trusted keys : <br>
`vim /usr/share/keys/pkg/trusted/pkg.vultureproject.org`

    function: sha256
    fingerprint: 18072e5d7fbec639a3dfd11da1fe8a0c9e9bd30741780ced28f1665cd7ed9631

And create **repository configuration** file : <br>
`mkdir -p /usr/local/etc/pkg/repos` <br>
`vim /usr/local/etc/pkg/repos/vulture.conf`

    Vulture: {
        url: https://download.vultureproject.org/v4/12.1/release/,
        signature_type: "fingerprints",
        fingerprints: "/usr/share/keys/pkg",
        enabled: yes
    }

Then, **install** required **packages** : <br>
`pkg update` <br>
`pkg install -y open-vm-tools-nox11 wget libucl secadm secadm-kmod` <br>
`pkg install -y vulture-libtensorflow` <br>
`pkg install -y vulture-haproxy` <br>
`pkg install -y vulture-rsyslog` <br>
`pkg install -y vulture-mongodb` <br>
`pkg install -y vulture-redis` <br>
`pkg install -y vulture-gui` <br>
`pkg install -y vulture-base` <br>
`pkg install -y darwin` <br>

> # **At this point you _need to reboot_**

Then, **bootstrap** all the required **system jails** : <br>
`/home/vlt-adm/bootstrap/mkjail-haproxy.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-mongodb.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-redis.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-apache.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-portal.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-rsyslog.sh` <br>

Finally, activate **secadm** in jails: <br>
`jexec haproxy sysrc secadm_enable=YES`<br>
`jexec mongodb sysrc secadm_enable=YES`<br>
`jexec redis sysrc secadm_enable=YES`<br>
`jexec apache sysrc secadm_enable=YES`<br>
`jexec portal sysrc secadm_enable=YES`<br>
`jexec rsyslog sysrc secadm_enable=YES`<br>


System is now installed, you can proceed with the [Initial Configuration](CONFIGURE.md)
