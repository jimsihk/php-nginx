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

# Replace ENV vars in configuration files
for _configini in $envsubst_config_list; do
  if [ -f "$_configini" ]
  then
    echo "Setting up $_configini..."
    tmpfile=$(mktemp)
    envsubst "$(env | cut -d= -f1 | sed -e 's/^/$/')" < "$_configini" > "$tmpfile"
    mv "$tmpfile" "$_configini"
  fi
done

echo "Starting startup scripts in /docker-entrypoint-init.d ..."

tmpfile=$(mktemp)
find /docker-entrypoint-init.d/ -executable -type f > "$tmpfile"
while IFS= read -r script; do
    echo >&2 "*** Running: $script"
    $script
    retval=$?
    if [ $rc != 0 ];
    then
        echo >&2 "*** Failed with return value: $retval"
        exit $retval
    fi
done < <(sort "$tmpfile")
echo $?
echo "retval=$retval"
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

# If there are additional arguments, execute them
if [ $# -gt 0 ]; then
    exec "$@"
fi

# catch shutdown signals
trap shutdown SIGTERM SIGHUP SIGQUIT SIGINT
wait $RUNSVDIR

shutdown
