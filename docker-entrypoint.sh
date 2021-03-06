#!/usr/bin/env bash
set -Ee
# TODO swap to -Eeuo pipefail above (after handling all potentially-unset variables)

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

if [ "${1:0:1}" = '-' ]; then
	set -- postgres "$@"
fi

# allow the container to be started with `--user`
if  [ "$(id -u)" = '0' ]; then
	mkdir -p "$PGDATA"
	chown -R postgres "$PGDATA"
	chmod 700 "$PGDATA"

	mkdir -p /var/run/postgresql
	chown -R postgres /var/run/postgresql
	chmod 775 /var/run/postgresql

	# Create the transaction log directory before initdb is run (below) so the directory is owned by the correct user
	if [ "$POSTGRES_INITDB_WALDIR" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		chown -R postgres "$POSTGRES_INITDB_WALDIR"
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	exec gosu postgres "$BASH_SOURCE" "$@"
fi

	mkdir -p "$PGDATA"
	chown -R "$(id -u)" "$PGDATA" 2>/dev/null || :
	chmod 700 "$PGDATA" 2>/dev/null || :

	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
		# "initdb" is particular about the current user existing in "/etc/passwd", so we use "nss_wrapper" to fake that if necessary
		# see https://github.com/docker-library/postgres/pull/253, https://github.com/docker-library/postgres/issues/359, https://cwrap.org/nss_wrapper.html
		if ! getent passwd "$(id -u)" &> /dev/null && [ -e /usr/lib/libnss_wrapper.so ]; then
			export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
			export NSS_WRAPPER_PASSWD="$(mktemp)"
			export NSS_WRAPPER_GROUP="$(mktemp)"
			echo "postgres:x:$(id -u):$(id -g):PostgreSQL:$PGDATA:/bin/false" > "$NSS_WRAPPER_PASSWD"
			echo "postgres:x:$(id -g):" > "$NSS_WRAPPER_GROUP"
		fi

		file_env 'POSTGRES_USER' 'postgres'
		file_env 'POSTGRES_PASSWORD'

		file_env 'POSTGRES_INITDB_ARGS'
		if [ "$POSTGRES_INITDB_WALDIR" ]; then
			export POSTGRES_INITDB_ARGS="$POSTGRES_INITDB_ARGS --waldir $POSTGRES_INITDB_WALDIR"
		fi
		eval 'initdb --username="$POSTGRES_USER" --pwfile=<(echo "$POSTGRES_PASSWORD") '"$POSTGRES_INITDB_ARGS"

		# unset/cleanup "nss_wrapper" bits
		if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ]; then
			rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
			unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
		fi

		# check password first so we can output the warning before postgres
		# messes it up
		if [ -n "$POSTGRES_PASSWORD" ]; then
			authMethod=md5
		else
			# The - option suppresses leading tabs but *not* spaces. :)
			cat >&2 <<-'EOWARN'
				****************************************************
				WARNING: No password has been set for the database.
				         This will allow anyone with access to the
				         Postgres port to access your database. In
				         Docker's default configuration, this is
				         effectively any other container on the same
				         system.
				         Use "-e POSTGRES_PASSWORD=password" to set
				         it in "docker run".
				****************************************************
			EOWARN

			authMethod=trust
		fi

		{
			echo
			echo "host all all all $authMethod"
		} >> "$PGDATA/pg_hba.conf"

#                {       echo 
#                        echo "REPMGRD_ENABLED=yes"
#                        echo "REPMGRD_CONF=\"/etc/repmgr.conf\""
#                } >> /etc/default/repmgrd

		# internal start of server in order to allow set-up using psql-client
		# does not listen on external TCP/IP and waits until start finishes
		PGUSER="${PGUSER:-$POSTGRES_USER}" \
		pg_ctl -D "$PGDATA" \
			-o "-c listen_addresses=''" \
			-w start

		file_env 'POSTGRES_DB' "$POSTGRES_USER"

		export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
		psql=( psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --no-password )

		if [ "$POSTGRES_DB" != 'postgres' ]; then
			"${psql[@]}" --dbname postgres --set db="$POSTGRES_DB" <<-'EOSQL'
				CREATE DATABASE :"db" ;
			EOSQL
			echo
		fi
		psql+=( --dbname "$POSTGRES_DB" )

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)
					# https://github.com/docker-library/postgres/issues/450#issuecomment-393167936
					# https://github.com/docker-library/postgres/pull/452
					if [ -x "$f" ]; then
						echo "$0: running $f"
						"$f"
					else
						echo "$0: sourcing $f"
						. "$f"
					fi
					;;
				*.sql)    echo "$0: running $f"; "${psql[@]}" -f "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

		PGUSER="${PGUSER:-$POSTGRES_USER}" \
		pg_ctl -D "$PGDATA" -m fast -w stop

		unset PGPASSWORD

		echo
		echo 'PostgreSQL init process complete; ready for start up.'
		echo
	fi

#exec "$@"

if [ ! -f "$PGDATA/exists" ];then
if [ "$NODE_TYPE" = 'standby' ]; then

  echo "standby"

    echo "rm data"
    rm -rf "$PGDATA"/*

    /usr/bin/repmgr -F -h $MASTER_IP -U repmgr -d repmgr -f /etc/repmgr.conf standby clone

  echo "repmgr register"
  PGUSER="${PGUSER:-$POSTGRES_USER}" \
	    pg_ctl -D "$PGDATA" -w start
  /usr/bin/repmgr -F -f /etc/repmgr.conf standby register
  touch $PGDATA/exists  

else
 
  echo "primary"

#  exec gosu postgres "$BASH_SOURCE" "repmgr -f /etc/repmgr.conf primary register"
  echo "repmgr register"
  PGUSER="${PGUSER:-$POSTGRES_USER}" \
	    pg_ctl -D "$PGDATA" -w start
  /usr/bin/repmgr -F -f /etc/repmgr.conf primary register
#  exec gosu postgres "$BASH_SOURCE" "repmgrd --daemonize"
  touch $PGDATA/exists

fi
else
PGUSER="${PGUSER:-$POSTGRES_USER}" \
	    pg_ctl -D "$PGDATA" -w start
new_node=`repmgr -q -f /etc/repmgr.conf cluster show|grep  'is registered as standby but running as primary' |cut -d '"' -f 2`
conn=`grep 'conninfo' /etc/repmgr.conf|cut -d ' ' -f 2- |sed "s/'//g"`
conninfo="repmgr node rejoin -f /etc/repmgr.conf -d 'host=$new_node $conn' --force-rewind=/usr/lib/postgresql/11/bin/pg_rewind --verbose"
echo $conninfo

if [ $new_node ];then
        echo "rejoin"
PGUSER="${PGUSER:-$POSTGRES_USER}" \
 	pg_ctl -D "$PGDATA" -w stop
eval $conninfo
else
PGUSER="${PGUSER:-$POSTGRES_USER}" \
            pg_ctl -D "$PGDATA" -w start
fi

fi

/usr/bin/repmgrd  --daemonize &

while sleep 60;do
#  echo "grep postgres"
#  ps aux|grep postgres|grep -q -v grep
#  POSTGRES_STATUS=$?
  
  echo "grep repmgrd"
  ps aux|grep repmgrd|grep -q -v grep
  REPMGRD_STATUS=$?
  
#  if [ $POSTGRES_STATUS -ne 0 -o $REPMGRD_STATUS -ne 0 ];then
  if [ $REPMGRD_STATUS -ne 0 ];then
    echo "processes repmgrd has already exited."
    exit 1
  fi
done

#if [ "$NODE_TYPE" = 'standby' ]; then
#  gosu postgres repmgr -f /etc/repmgr.conf standby register
#  gosu postgres repmgrd --daemonize
#else
#  gosu postgres repmgr -f /etc/repmgr.conf primary register
#  gosu postgres repmgrd --daemonize
#fi
