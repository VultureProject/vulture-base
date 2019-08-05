# The base FreeBSD Operating System for Vulture 4

## Configuration of Operating System

To configure VultureOS, use the `vlt-adm` account, and the `admin` command : <br>

Using this menu, you have the following choices :
 - **Keymap** : Configure keymap, like during installation of FreeBSD,
 - **Time** : Configure timezone and ntp server,
 - **Password** : Change vlt-adm password,
 - **Geli Change** : Change the ZFS disk encryption password,
 - **Email** : Define the administration SMTP Email address,
 - **Management** : Modify current management IP used to bind services,
 - **Proxy** : Configure proxy,
 - **Netconfig** : Manage network configuration, like during installation of FreeBSD,
 - **Hostname** : Configure hostname,
 - **Shell** : Launch a CSH shell as vlt-adm,
 - **RootShell** : Launch a CSH shell as root,
 - **Update OS** : Update system and jails, with pkg and freebsd-update,
 - **Exit** : Exit admin menu.

**It is mandatory to, at least, configure the hostname before bootstraping Vulture**


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
