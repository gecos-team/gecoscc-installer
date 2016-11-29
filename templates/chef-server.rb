default_orgname "default"
addons['install'] = false

nginx['url'] = "https://${CHEF_SERVER_IP}"
nginx['enable'] = true
nginx['non_ssl_port'] = false
nginx['enable_non_ssl'] = false
nginx['ssl_port'] = 443

bookshelf['url'] = "https://${CHEF_SERVER_IP}"

