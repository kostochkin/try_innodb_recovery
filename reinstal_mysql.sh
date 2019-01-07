#!/bin/bash

service mysql stop
rm -rf /var/lib/mysql
apt-get remove --purge mysql-server mysql-client mysql-common -y
apt-get autoremove -y
apt-get autoclean -y
echo "mysql-server-5.5 mysql-server/root_password_again password 1234" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password password 1234" | debconf-set-selections
apt-get install mysql-server mysql-client -y

