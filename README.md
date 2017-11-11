# haproxy-and-pgbouncer
PostgreSQL HA created haproxy and bgbouncer 

    client01 ... clientN

            |||||  pguser(6432)
         -----------
        |  haproxy  |
         -----------
            | | |  haproxy(5432)
        -------------
       |  pgbouncer  |
        -------------
            | | | testuser/testuser(5431)
        --------------
       | PostgreSQL DB|
        --------------        
        
               
#######################################  postgresql database #################################

1.pg

# yum install https://download.postgresql.org/pub/repos/yum/10/redhat/rhel-7-x86_64/pgdg-centos10-10-1.noarch.rpm
# yum install postgresql10-server
# /usr/pgsql-10/bin/postgresql-10-setup initdb
# systemctl enable postgresql-10
# systemctl start postgresql-10


postgresql.conf

listen_addresses = '*'
port = 5431


pg_hba.conf

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
host    all             all             192.168.0.0/24           trust
# IPv6 local connections:
host    all             all             ::1/128                 ident
# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            ident
host    replication     all             ::1/128                 ident

create test db and user

-bash-4.2$ psql -p 5431
psql (10.0)
Type "help" for help.

postgres=# 
postgres=# create database testdb;
CREATE DATABASE
postgres=# create user haproxy with superuser createdb;
CREATE ROLE
postgres=# alter user haproxy password 'haproxy';
ALTER ROLE
postgres=# 
postgres=# create user testuser with superuser createdb;
CREATE ROLE
postgres=# alter user testuser password 'testuser';
ALTER ROLE
postgres=# 


#######################################  pgbouncer ##################################################


2.pgbouncer

# yum install -y gcc-c++ openssl-devel

1).libevent
http://libevent.org/
libevent-2.1.8-stable.tar.gz
# tar zxvf libevent-2.1.8-stable.tar.gz
# cd libevent-2.1.8-stable
# ./configure
# make
# make install

2).pgbouncer
https://pgbouncer.github.io/downloads/
# tar zxvf pgbouncer-1.7.2.tar.gz 
# cd pgbouncer-1.7.2
./configure --prefix=/opt/pgbouncer/1.7.2
......
......
......
Results
  c-ares = no
  evdns = yes
  udns = no
  tls = yes
# make
# make install 

create dir and config

# cd /opt/pgbouncer/1.7.2/
# ls
bin  share
# mkdir etc log
# cp share/doc/pgbouncer/pgbouncer.ini etc/
# cp share/doc/pgbouncer/userlist.txt etc/
# 
# cd etc/
# ls
pgbouncer.ini  userlist.txt


# vi pgbouncer.ini 

[databases]
testdb = port=5431 dbname=testdb pool_size=20 user=testuser password=testuser

logfile = /opt/pgbouncer/1.7.2/log/pgbouncer.log
pidfile = /opt/pgbouncer/1.7.2/pgbouncer.pid

listen_addr = 0.0.0.0
listen_port = 5432

auth_file = /opt/pgbouncer/1.7.2/etc/userlist.txt

admin_users = pgbadmin
max_client_conn = 1000
listen_backlog = 8192
  

# vi userlist.txt 
"pgbadmin" "pgbadmin"
"haproxy" "haproxy"
"pguser" "pguser"

# cd /opt
# chown postgres.postgres -R pgbouncer/
#
# vi /etc/profile

#### pgbouncer,pg ####
export LD_LIBRARY_PATH=/usr/local/lib
export PATH=/opt/pgbouncer/1.7.2/bin:/usr/pgsql-10/bin:$PATH



# su - postgres
Last login: Thu Nov  9 15:58:40 CST 2017 on pts/0
-bash-4.2$ 
-bash-4.2$ pgbouncer -d /opt/pgbouncer/1.7.2/etc/pgbouncer.ini 
2017-11-09 16:01:57.613 23929 LOG File descriptor limit: 1024 (H:4096), max_client_conn: 1000, max fds possible: 1030
-bash-4.2$ 

-bash-4.2$ psql -U pgbadmin -h 172.16.3.228 pgbouncer
psql (10.0, server 1.7.2/bouncer)
Type "help" for help.

pgbouncer=# 


#######################################  perl check script ##################################################



3. perl check script

# yum install postgresql10-plperl

# vi /etc/profile

#### pgbouncer,pg ####
export LD_LIBRARY_PATH=/usr/local/lib:/usr/pgsql-10/lib
export PATH=/opt/pgbouncer/1.7.2/bin:/usr/pgsql-10/bin:$PATH

[root@pg01 usr]# su - postgres
Last login: Thu Nov  9 22:34:05 CST 2017 on pts/0
-bash-4.2$ psql -p 5431
psql (10.1)
Type "help" for help.
postgres=# \c testdb 
You are now connected to database "testdb" as user "postgres".
testdb=# create language plperlu;
testdb=# \dL
                      List of languages
  Name   |  Owner   | Trusted |         Description          
---------+----------+---------+------------------------------
 plperlu | postgres | f       | 
 plpgsql | postgres | t       | PL/pgSQL procedural language
(2 rows)

testdb=#
### check_ha ####
testdb=# CREATE OR REPLACE FUNCTION check_ha() 
RETURNS int AS $$
use Sys::Hostname;
my $h = Sys::Hostname::hostname;
if ($h eq 'unknown-host') {
return 0;
} elsif ($h eq 'haproxy') { # standby
return 1;
} elsif ($h eq 'pg01') { # master
return 0;
} elsif ($h eq 'pg02') { # standby
return 1;
} else {
return 0;
}
$$ LANGUAGE plperlu;
testdb=#
testdb=# select check_ha();
 check_ha 
----------
        1
(1 row)

testdb=#  
testdb=# 
testdb=#

######################  script: access http server,check db #####################################

# yum install perl-HTTP-Daemon perl-DBD-Pg perl-Try-Tiny -y

reference doc：

HTTP::Daemon


# curl http://192.168.0.108:8080/pgcheck/username/haproxy/port/5432


testdb=# \df+ check_ha 
List of functions
-[ RECORD 1 ]-------+---------------------------------------
Schema              | public
Name                | check_ha
Result data type    | integer
Argument data types | 
Type                | normal
Volatility          | volatile
Parallel            | unsafe
Owner               | postgres
Security            | invoker
Access privileges   | 
Language            | plperlu
Source code         |                                       +
                    | use Sys::Hostname;                    +
                    | my $h = Sys::Hostname::hostname;      +
                    | if ($h eq 'unknown-host') {           +
                    | return 0;                             +
                    | } elsif ($h eq 'db-sql02') { # standby+
                    | return 1;                             +
                    | } elsif ($h eq 'db-sql03') { # master +
                    | return 0;                             +
                    | } elsif ($h eq 'db-sql05') { # standby+
                    | return 1;                             +
                    | } else {                              +
                    | return 0;                             +
                    | }                                     +
                    | 
Description         | 

testdb=# 


perl backend web server

/opt/pgbouncer/1.7.2/bin/pgcheck.pl


######################  haproxy configure #####################################

4.haproxy

# yum update
# yum install haproxy -y
# yum install gcc pcre-static pcre-devel openssl-devel -y

# tar zxvf haproxy-1.6.13.tar.gz
# cd haproxy-1.6.13
# make TARGET=linux2628 USE_OPENSSL=1 USE_PCRE=1 USE_ZLIB=1
# make install


# cp /usr/local/sbin/haproxy /usr/sbin
cp: overwrite ‘/usr/sbin/haproxy’? y
# 

# systemctl enable haproxy.service

# cd /etc/haproxy/
# mv haproxy.cfg haproxy.cfg.bak

# vi /etc/haproxy/haproxy.cfg

#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    description PostgreSQL Database HAProxy Stats page
    log 127.0.0.1 local0 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     3000
    user        haproxy
    group       haproxy
    daemon
    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    log global
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

#---------------------------------------------------------------------
# stats page
#---------------------------------------------------------------------
listen statspage
    mode http
    bind *:7000
    stats enable
    stats uri /
    stats refresh 30s
    stats auth  admin:admin
    stats show-desc
    stats show-legends
#---------------------------------------------------------------------
# postgresql databases
#---------------------------------------------------------------------
listen postgresql
        mode tcp
        bind 0.0.0.0:6432
        timeout client 20m
        timeout connect 1s
        timeout server 20m
        option tcplog
        balance leastconn
        option log-health-checks
        option tcpka
        option tcplog
        option httpchk GET /pgcheck/username/haproxy/port/5432 # checker pgbouncer connection
        http-check send-state
        server pg01 192.168.0.108:5432 weight 1 check addr 192.168.0.108 port 8080 inter 5000 rise 2 fall 3
        server pg02 192.168.0.109:5432 weight 1 check addr 192.168.0.109 port 8080 inter 5000 rise 2 fall 3
# 
#  
#
# haproxy -f /etc/haproxy/haproxy.cfg -c
Configuration file is valid
#

# systemctl start haproxy.service

log config


# mkdir /var/log/haproxy
# chmod a+w /var/log/haproxy
# 
# vi /etc/rsyslog.conf

# Provides UDP syslog reception
$ModLoad imudp
$UDPServerRun 514

# Save haproxy log
local0.*                       /var/log/haproxy/haproxy.log

# vi /etc/sysconfig/rsyslog
# Options for rsyslogd
# Syslogd options are deprecated since rsyslog v3.
# If you want to use them, switch to compatibility mode 2 by "-c 2"
# See rsyslogd(8) for more details
SYSLOGD_OPTIONS="-r -m 0 -c 2"

# systemctl restart haproxy
# service rsyslog restart
Redirecting to /bin/systemctl restart rsyslog.service
# 

5.check haproxy admin page

# http://haproxy_ip:7000/,input user(admin) and password(admin)

6.use 192.168.0.108:6432 pguser:pguser conn haproxy handle postgres db
