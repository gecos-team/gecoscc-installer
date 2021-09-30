FROM chefserverofficial/chef-server-ctl:12.18.14

ARG SVC_GID
ARG SVC_GROUP

# Add a group and assign it to "hab" user
RUN addgroup -g $SVC_GID $SVC_GROUP \
 && adduser hab $SVC_GROUP \
 && echo $SVC_GROUP > /hab/pkgs/jeremymv2/chef-server-ctl/12.18.14/20181017194418/SVC_GROUP

# Create chef-server-ctl-gecos script
RUN cp /bin/chef-server-ctl /bin/chef-server-ctl-gecos \
 && sed -i 's/export CHEF_SECRETS_DATA/#export CHEF_SECRETS_DATA/g' /bin/chef-server-ctl-gecos

