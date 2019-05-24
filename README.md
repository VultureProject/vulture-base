# The base FreeBSD Operating System for Vulture 4

## Purpose

This FreeBSD package turns an existing FreeBSD 12.0 system into a Vulture 4 operating system

What it basically does is:
 - Hardening the FreeBSD operating system
 - Installing FreeBSD packages needed by Vulture
 - Installing system scripts to bootstrap Vulture services and Jails
 
You do not want to bother to follow all these annoying steps ? <br>
Just download the production-ready OVF Image: https://download.vultureproject.org/v4/12.0/isos/vulture4-latest.zip

## Prerequisite

To install vulture-base, you will need a **FreeBSD 12.0**.

That instance must run on a **ZFS disk configuration**.
ZFS encryption is supported, but be aware that automatic bootup will no be possible in this case as you will have to type in your passphrase at every reboot.

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
        url: https://download.vultureproject.org/v4/12.0/release/,
        signature_type: "fingerprints",
        fingerprints: "/usr/share/keys/pkg",
        enabled: yes
    }

Then, **install** required **packages** : <br>
`pkg update` <br>
`pkg install -y vulture-libtensorflow` <br>
`pkg install -y vulture-haproxy` <br>
`pkg install -y vulture-rsyslog` <br>
`pkg install -y vulture-mongodb` <br>
`pkg install -y vulture-redis` <br>
`pkg install -y vulture-gui` <br>
`pkg install -y netdata` <br>
`pkg install -y vulture-base` <br>
`pkg install -y darwin` <br>

> # **At this point you _need to reboot_**

Lastly, **bootstrap** all the required **system jails** : <br>
`/home/vlt-adm/bootstrap/mkjail-haproxy.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-mongodb.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-redis.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-apache.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-portal.sh` <br>
`/home/vlt-adm/bootstrap/mkjail-rsyslog.sh` <br>


## Configuration of OS

To configure VultureOS, use the `vlt-adm` account, and the `admin` command : <br>
![Admin MENU](/admin_menu.png)

Using this menu, you have the following choices :
 - **Keymap** : Configure keymap, like during installation of FreeBSD,
 - **Time** : Configure timezone and ntp server,
 - **Password** : Change vlt-adm password,
 - **Geli Change** : Change the ZFS disk encryption password,
 - **Email** : Define the administration SMTP Email address,
 - **Management** : Modify current management IP used to bind services,**\***
 - **Proxy** : Configure proxy,
 - **Netconfig** : Manage network configuration, like during installation of FreeBSD,
 - **Hostname** : Configure hostname,**\*** **\*\***
 - **Shell** : Launch a CSH shell as vlt-adm,
 - **RootShell** : Launch a CSH shell as root,
 - **Update OS** : Update system and jails, with pkg and freebsd-update,**\***
 - **Exit** : Exit admin menu.

> **(\*): This command will run installation & configuration of jails.** <br>
> **(\*\*) : Mandatory option to bootstrap *VultureOS*.**


## Bootstraping Vulture 4

Depending on what you want do to, you have 2 scripts available : 
 - `/home/vlt-adm/gui/cluster_create.sh` : To create a new **Master** node
 - `/home/vlt-adm/gui/cluster_join.sh` : To create a **slave** and join a Cluster

The first script, to create a new Master, has the following usage : 

    sudo /home/vlt-adm/gui/cluster_create.sh <admin_user> <admin_password>

The second, to add the node to an existing cluster, has the following usage :

   sudo  /home/vlt-adm/gui/cluster_join.sh <master_hostname> <master_ip> <secret_key>
   
After that, start **vultured** if it is down : <br>
`service vultured start`
