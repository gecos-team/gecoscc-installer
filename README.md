# gecoscc-installer

This script installs and configure [__GECOS Control Center__](https://gecos-team.github.io). At the end of this process you will have a complete and modern solution for corporate workstation management.

## Minimum host machine requirements

In order to get __GECOS Control Center__ installed, your server must have:

__Minimal host__
* 64-bits architecture
* 1 CPU
* 1 GB of RAM memory 
* Red Hat 7 / CentOS 7
* 15 GB of free disk space in `/home` partition
* An FQDN
* Internet access


This installer has been tested in [CentOS](https://centos.org) 7 minimal (64bits) and [Red Hat Enterprise Linux](https://redhat.com) 7 64bits (base install). In case your operating system is Red Hat, you should have your suscription updated.

## Other services required
In order to have __GECOS Control Center__ installed, you must provide the following services:

* A Redis 3.2+ server: https://redis.io/
* A MongoDB 4.4+ database: https://www.mongodb.com/
* An Opscode Chef 12 server: https://www.chef.io/
* A NginX server (or similar) to balance the load between the different processes of the GECOS Control Center. (The installer will setup a NginX with a base configuration.)


## Installation instructions

![Installer Screenshot](./gecoscc-installer-docker-01.png)

1. From your `root` account (or some other user with privileges), download the installer from [`http://bit.ly/gecoscc-installer`](http://bit.ly/gecoscc-installer).
~~~
curl -L http://bit.ly/gecoscc-installer > gecoscc-installer.sh
~~~

After downloadint the installer you must edit the script and provide the URL or IP address of the different services required.

2. Run the installer.
~~~
bash gecoscc-installer.sh
~~~

The first time you run the installer several packages will be installed in your system (docker, docker-compose, firewalld, unzip, ...), so it might take a while before displaying the main menu.

3. Select the `CC` option in the menu in order to install the GECOS Control Center.


## Configuration

1. Run the installer again, create an administrator user (`CCUSER` option in the menu).
~~~
bash gecoscc-installer.sh
~~~

2. This command will show some messages with important data like your superadmin password. Do not forget to write them down!
~~~
NOTICE: Please remember to grant server admin permissions to this user by executing the following command in Chef 12 server:
/opt/opscode/bin/chef-server-ctl grant-server-admin-permissions <username>
User  <username> set as administrator in the default organization chef server
The generated password to GCC is: xxxxx
~~~

3. Log into your Opscode Chef server and execute the aforementioned command:
~~~
/opt/opscode/bin/chef-server-ctl grant-server-admin-permissions <username>
~~~

4. Now you should be able to log in into your brand new __GECOS Control Center__, using your favorite web browser. Just point it to your server's name or IP address.

## Catalogues

Once you reach into your Control Center you may populate your system installing policies, printers and packages. This catalogues are optional but it is strongly recommended to install at least a policies catalogue for a better user experience.

Run the installer, once more.
~~~
bash gecoscc-installer.sh
~~~

Execute the options that feed the system with:
1. `POLICIES`. It will download and install last version of workstation policies.
2. `PRINTERS`. It will download and install a catalogue with +4000 printer models.
3. `PACKAGES`. It will download and install a huge catalogue of software to install in your workstations.

You can repeat these steps as many times as you need in order to keep your __GECOS Control Center__ updated.


## Logging in

![Installer Screenshot](./gecoscc-installer-02.png)

Just point your web browser to your server's IP address and log in with your superuser information.

## Troubleshooting
* **What services must I check to ensure that everything is up and running?**
You must check the "gecoscc" service and the "firewalld" service. 

* **How can I check that all the docker containers are running?**
The docker containers are created with the "gecos" user account. So you can check then by executing:
~~~
su - gecos
docker ps
~~~

* **Where are the important data, configuration files and logs stored?**
The configuration files and logs are stored in the /data directory.
All the important data is stored in MongoDB and Opscode chef.

* **How can I see the logs that are not stored in the /data directory?**
You can see them by using the "docker logs" command.

* **What ports are opened in the host machine?**
The opened ports are: TCP 80 (NginX) and TCP 8010, 8011 and 9001 (GECOS Control Center).
If you use NginX as a load balancer (by default), you won't need ports 8010 and 8011 to be accesible.
If you only use one GECOS CC server (instead of several of them balanced to keep high availability) you won't need to expose the 9001 TCP port.





