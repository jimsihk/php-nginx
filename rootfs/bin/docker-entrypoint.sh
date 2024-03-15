#!/bin/sh

shutdown() {
  echo "shutting down container"

  # first shutdown any service started by runit
  for _srv in /etc/service/*; do
    [ -e "$_srv" ] || break
    sv force-stop "$(basename "$_srv")"
  done

  # shutdown runsvdir command
  kill -HUP $RUNSVDIR
  wait $RUNSVDIR

  # give processes time to stop
  sleep 0.5

  # kill any other processes still running in the container
  for _pid  in $(ps -eo pid | grep -v PID  | tr -d ' ' | grep -v '^1$' | head -n -6); do
    timeout 5 /bin/sh -c "kill $_pid && wait $_pid || kill -9 $_pid"
  done
  exit
}

# Replace ENV vars in NGINX configuration files
tmpfile=$(mktemp)
envsubst "$(env | cut -d= -f1 | sed -e 's/^/$/')" < /etc/nginx/nginx.conf > "$tmpfile"
mv "$tmpfile" /etc/nginx/nginx.conf

# Replace ENV vars in PHP configuration files
tmpfile=$(mktemp)
envsubst "$(env | cut -d= -f1 | sed -e 's/^/$/')" < /etc/php/conf.d/custom.ini > "$tmpfile"
mv "$tmpfile" /etc/php/conf.d/custom.ini

tmpfile=$(mktemp)
envsubst "$(env | cut -d= -f1 | sed -e 's/^/$/')" < /etc/php/php-fpm.d/www.conf > "$tmpfile"
mv "$tmpfile" /etc/php/php-fpm.d/www.conf

echo "Starting startup scripts in /docker-entrypoint-init.d ..."

tmpfile=$(mktemp)
find /docker-entrypoint-init.d/ -executable -type f > "$tmpfile"
sort "$tmpfile" | while IFS= read -r script; do
    echo >&2 "*** Running: $script"
    $script
    retval=$?
    if [ $retval != 0 ];
    then
        echo >&2 "*** Failed with return value: $?"
        exit $retval
    fi
done
rm "$tmpfile"
echo "Finished startup scripts in /docker-entrypoint-init.d"

echo "Starting runit..."
exec runsvdir -P /etc/service &

RUNSVDIR=$!
echo "Started runsvdir, PID is $RUNSVDIR"
echo "wait for processes to start...."

sleep 5
for _srv in /etc/service/*; do
  [ -e "$_srv" ] || break
  sv status "$(basename "$_srv")"
done

# catch shutdown signals
trap shutdown SIGTERM SIGHUP SIGQUIT SIGINT
wait $RUNSVDIR

shutdown
