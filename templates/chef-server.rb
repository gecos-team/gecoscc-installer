nginx['url'] = "https://${CHEF_SERVER_IP}"
nginx['enable'] = true
nginx['non_ssl_port'] = false
nginx['enable_non_ssl'] = false
nginx['ssl_port'] = 443

