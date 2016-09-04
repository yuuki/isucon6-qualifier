#!/bin/bash
set -ex

HOSTS=("$@")
USERNAME=$USER

for HOST in ${HOSTS[@]}; do
    ssh isucon@$HOST "cd /home/isucon/deploy && git pull && ~/deploy/env.sh carton install && sudo systemctl restart mysql && sudo service memcached restart && sudo systemctl restart isuda && sudo systemctl restart isutar && sudo systemctl restart nginx && sudo sysctl -p"
done
