# gecoscc-installer

This script installs and configure [__GECOS Control Center__](https://gecos-team.github.io). At the end of this process you will have a complete and modern solution for corporate workstation management.

## Minimum requirements

In order to get __GECOS Control Center__ installed, your server must have:

__Minimal host__
* 64-bits architecture
* 1 CPU
* * 6 GB of RAM memory 
* Red Hat 7 / CentOS 6
* 15 GB of free disk space in `/home`
* An FQDN
* Internet access

__Recommended host__
* 64-bits architecture
* 4 CPU
* 16 GB of RAM memory 
* Red Hat 7 / CentOS 6
* 15 GB of free disk space in `/home`
* An FQDN
* Internet access

This installer has been tested in [CentOS](https://centos.org) 7 minimal (64bits) and [Red Hat Enterprise Linux](https://redhat.com) 7 64bits (base install). In case your operating system is Red Hat, you should have your suscription updated.

## Installation instructions

![Installer Screenshot](./gecoscc-installer-docker-01.png)

1. From your `root` account (or some other user with privileges), download the installer from [`http://bit.ly/gecoscc-installer`](http://bit.ly/gecoscc-installer).
~~~
curl -L http://bit.ly/gecoscc-installer > gecoscc-installer.sh
~~~

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
The generated password to GCC is: xxxxx
~~~

3. Now you should be able to log in into your brand new __GECOS Control Center__, using your favorite web browser. Just point it to your server's name or IP address.

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
