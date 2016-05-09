# gecoscc-installer

Script and configuration templates to install a GECOS Control Center


## Instructions

* Install a CENTOS 6.x minimal (64bits) in a real or virtual server.

* Log into your server.

* Download the installer from http://bit.ly/gecoscc-installer:         

`curl -L http://bit.ly/gecoscc-installer > gecoscc-installer `

* Edit the installer and change the ORGANIZATION_NAME, ADMIN_USER_NAME and ADMIN_EMAIL

* Run the installer:
  
`bash gecoscc-installer`

* Select proper menu items in order to install every component: CHEF, MONGODB, NGINX and CONTROL CENTER 

* Select USER to create your first superuser (You can create more users from the web interface). Do not forget to write down your password!

* Reboot the server. 

Now you can log into your brand new Control Center using your web browser.

If you can see the web interface, follow these steps to finish the configuration:

* Select POLICIES to download and install last version of workstation policies.

* Select PRINTERS to download and install a catalogue of printer models.

* Select PACKAGES to download and install a catalogue of software for your workstations.

Ÿou can repeat these steps as many times as you need.

