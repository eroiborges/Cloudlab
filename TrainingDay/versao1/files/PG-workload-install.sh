#!/bin/bash

# Install PG
sudo dnf module install postgresql:16/server -y

# bring down necessary utilities
sudo yum install git php php-pgsql httpd -y

# setup firewall rules
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload

# Initialize PG
sudo postgresql-setup --initdb

# Start PG Service
sudo systemctl start postgresql.service
sudo systemctl enable postgresql.service

# Configre PG
sudo sed -i "s/ident/trust/g" /var/lib/pgsql/data/pg_hba.conf
sudo sed -i "s/peer/trust/g" /var/lib/pgsql/data/pg_hba.conf
sudo sed -i "s/32/0/g"  /var/lib/pgsql/data/pg_hba.conf
sudo sed -i "s/127/0/g"  /var/lib/pgsql/data/pg_hba.conf
sudo sed -i '115s/\.1/\.0/;121s/\.1/\.0/' /var/lib/pgsql/data/pg_hba.conf
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /var/lib/pgsql/data/postgresql.conf
sudo sed -i "s/#port = 5432/port = 5432/g" /var/lib/pgsql/data/postgresql.conf

# Restart PG
sudo systemctl restart postgresql.service

#  Adjust SELinux to allow to allow HTTPD to make network connections  
sudo setsebool -P httpd_can_network_connect_db 1

# bring down Northwind database
curl https://23qt08bkeft5g.z20.web.core.windows.net/northwind.sql -o ~/northwind.sql

# Create User and database
sudo -u postgres psql -c "CREATE USER demouser WITH PASSWORD 'demopass123';"
sudo -u postgres psql -c "CREATE TABLESPACE northwindspace;"
sudo -u postgres psql -c "CREATE DATABASE northwind OWNER demouser TABLESPACE northwindspace;"

# create root user for migration
sudo -u postgres psql -c "CREATE USER rootuser WITH PASSWORD '123rootpass456' SUPERUSER;"

# Populate database
# bring down file to home and then sudo cp to /var/lib/pgsql
sudo cp ~/northwind.sql /var/lib/pgsql
sudo -u postgres psql -d northwind -a -f /var/lib/pgsql/northwind.sql
sudo -u postgres psql -d northwind -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO demouser;"
sudo -u postgres psql -d northwind -c "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO demouser;"