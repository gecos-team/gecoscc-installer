FROM guadalinexgecos/gecoscc:3.0.1

ARG SVC_GID
ARG SVC_GROUP

USER root 

# Add a group and assign it to "gecoscc" user
RUN addgroup --gid $SVC_GID $SVC_GROUP \
 && adduser gecoscc $SVC_GROUP 

USER gecoscc

