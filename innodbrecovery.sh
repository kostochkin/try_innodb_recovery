#!/bin/bash

mysql_user=root
mysql_password=1234

mysql_dir=/var/lib/mysql

# What does this script do? It restores InnoDB tables from ibd and frm files.
# Read there: https://twindb.com/how-to-recover-table-structure-from-frm-files-online/
# And there: http://www.hexblot.com/blog/recovering-innodb-tables-ibd-and-frm-files
# And there: https://medium.com/magebit/recover-innodb-database-from-frm-and-ibd-files-99fdb0deccad
# It doesn't work now:
# "ALTER TABLE xxx IMPORT TABLESPACE;" returns error
# MYSQL 5.1 (Ubuntu 10.04) , 5.5 (Ubuntu 12.04)


# CHECK RUN AS ROOT
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" >&2
   exit 1
fi

dir=$1
if [ ! $dir ]
then
	echo usage $0 %dir with ibd and frm files%
	exit 1
fi
echo Working with $dir
cd $dir


# Some useful functions
function tagged_log {
	tag=$1
	shift
	echo "[ $tag ] $@" >&2
}

function log {
	tagged_log LOG "$@"
}

function log_mysql {
	tagged_log MYSQL "$@"
	echo $@ | mysql -u$mysql_user -p$mysql_password
}

function log_execute {
	tagged_log EXECUTE "$@"
	if $@
	then
		tagged_log "EXECUTE OK"
	else
		error=$?
		tagged_log "EXECUTE ERROR" $error
		exit $error
	fi
}

function start_mysql {
	tagged_log "START MYSQL" "mysqld $@"
	mysqld --innodb-file-per-table=1 $@ &
	sleep 10
}

function stop_mysql {
	tagged_log "STOP MYSQL" "mysqld"
	killall mysqld
}

function restart_mysql {
	stop_mysql
	start_mysql $@
}


# Actions start here
service mysql stop

log "Find ibd files"
db=$dir
temp_db=temp_$dir
files=`ls *.ibd`
if [ ! "$files" ]
then
	log "There are no *ibd files"
	exit 1
fi

log "Collect ibd table names"
tables=
for f in $files
do
	tn=`echo $f | sed s/\.ibd$//g`
	log "Found table $tn"
	tables="$tables$tn "
done

log "Create a temporary database"
restart_mysql --innodb-force-recovery=6
log_mysql DROP DATABASE IF EXISTS $temp_db
log_execute rm -rf $mysql_dir/$temp_db
log_mysql CREATE DATABASE IF NOT EXISTS $temp_db

log "Create dummy tables ..."
for t in $tables
do
	log_mysql "USE $temp_db; CREATE TABLE IF NOT EXISTS $t (id INT) ENGINE=InnoDB"
done

log "... and replace their frms with ours"
stop_mysql
for t in $tables
do
	frm=$t.frm
	log_execute cp $frm $mysql_dir/$temp_db/
	log_execute chown mysql:mysql $mysql_dir/$temp_db/$frm
	log_execute chmod 660 $mysql_dir/$temp_db/$frm
done

start_mysql --innodb-force-recovery=6

log "Make a MYSQL script for the empty database"
creates=
for t in $tables
do
	c=`log_mysql "USE $temp_db; SHOW CREATE TABLE $t" | tail -n -1 | sed "s/^$t//" | sed 's/\n//g'`
	creates="$creates $c;"
done

echo $creates

log "Create a real database"
log_mysql DROP DATABASE IF EXISTS $temp_db
log_execute rm -rf $mysql_dir/$temp_db

restart_mysql --innodb-force-recovery=1

log_mysql DROP DATABASE IF EXISTS $db
log_execute rm -rf $mysql_dir/$db
log_mysql CREATE DATABASE IF NOT EXISTS $db
log_mysql "USE $db;" $creates

log "Unlink frms from the empty ibds ..."

for t in $tables
do
	log_mysql "USE $db; ALTER TABLE $t DISCARD TABLESPACE"
done

log "... and replace ibds with ours"
stop_mysql
for t in $tables
do
	ibd=$t.ibd
	log_execute cp $ibd $mysql_dir/$db/
	log_execute chown mysql:mysql $mysql_dir/$db/$ibd
	log_execute chmod 660 $mysql_dir/$db/$ibd
done

start_mysql --innodb-force-recovery=1

log "Link frms to our ibds"
for t in $tables
do
	log_mysql "USE $db; ALTER TABLE $t IMPORT TABLESPACE"
#	md=$mysql_dir
#	./../drt/ibdconnect -o $md/ibdata1 -f $md/$db/$t.ibd -d $db -t $t
done



