#!/bin/bash

set -x
set -e
cd $(dirname $0)

myhost=127.0.0.1
myport=3306
myuser=root
mypass=root

# Isuda
isuda_mydb=isuda
mysql -h ${myhost} -P ${myport} -u ${myuser} -p${mypass} -e "DROP DATABASE IF EXISTS ${isuda_mydb}; CREATE DATABASE ${isuda_mydb}"
mysql -h ${myhost} -P ${myport} -u ${myuser} -p${mypass} ${isuda_mydb} < db/isuda.sql
mysql -h ${myhost} -P ${myport} -u ${myuser} -p${mypass} ${isuda_mydb} < db/isuda_user.sql
mysql -h ${myhost} -P ${myport} -u ${myuser} -p${mypass} ${isuda_mydb} < db/isuda_entry.sql

# Isutar
isutar_mydb=isutar
mysql -h ${myhost} -P ${myport} -u ${myuser} -p${mypass} -e "DROP DATABASE IF EXISTS ${isutar_mydb}; CREATE DATABASE ${isutar_mydb}"
mysql -h ${myhost} -P ${myport} -u ${myuser} -p${mypass} ${isutar_mydb} < db/isutar.sql
