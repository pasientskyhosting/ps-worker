#!/bin/bash

# Disable Strict Host checking for non interactive git clones
mkdir -p -m 0700 /root/.ssh
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

if [ ! -z "$SSH_KEY" ]; then
    echo $SSH_KEY > /root/.ssh/id_rsa.base64
    base64 -d /root/.ssh/id_rsa.base64 > /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
fi

# Add new relic if key is present
if [ ! -z "$NEW_RELIC_LICENSE_KEY" ]; then
    newrelic-install install || exit 1
    nrsysmond-config --set license_key=${NEW_RELIC_LICENSE_KEY} || exit 1
    echo -e "\n[program:nrsysmond]\ncommand=nrsysmond -c /etc/newrelic/nrsysmond.cfg -l /dev/stdout -f\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0" >> /etc/supervisord.conf
else
    if [ -f /etc/php/7.1/fpm/conf.d/20-newrelic.ini ]; then
        rm -rf /etc/php/7.1/fpm/conf.d/20-newrelic.ini
    fi
    if [ -f /etc/php/7.1/cli/conf.d/20-newrelic.ini ]; then
        rm -rf /etc/php/7.1/cli/conf.d/20-newrelic.ini
    fi
    /etc/init.d/newrelic-daemon stop
fi

# Setup git variables
if [ ! -z "$GIT_EMAIL" ]; then
    git config --global user.email "$GIT_EMAIL"
fi

if [ ! -z "$GIT_NAME" ]; then
    git config --global user.name "$GIT_NAME"
    git config --global push.default simple
fi

# Dont pull code down if the .git folder exists
if [ ! -d "/data/.git" ]; then
    # Pull down code from git for our site!
    if [ ! -z "$GIT_REPO" ]; then
        # Remove the test index file
        rm -Rf /data/*
        if [ ! -z "$GIT_BRANCH" ]; then
            if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
                git clone -b $GIT_BRANCH $GIT_REPO /data/ || exit 1
            else
                git clone -b ${GIT_BRANCH} https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO} /data || exit 1
            fi
        else
            if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
                git clone $GIT_REPO /data/ || exit 1
            else
                git clone https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO} /data || exit 1
            fi
        fi
    fi
fi

if [ -f /data/app/config/parameters.yml ]; then
    sed -i "s/{{build_id}}/$PS_BUILD_ID/" /data/app/config/parameters.yml
fi

# Composer
if [ -f /data/composer.json ];
then

if [ -f /data/app/config/config_prod.yml ]; then
cat > /data/app/config/config_prod.yml <<EOF
imports:
    - { resource: config.yml }
monolog:
    handlers:
        main:
            type: stream
            path:  "/dev/stderr"
            level: error
EOF
fi
if [ -f /data/app/config/config_worker.yml ]; then
cat > /data/app/config/config_worker.yml <<EOF
imports:
    - { resource: config_prod.yml }
monolog:
    handlers:
        main:
            type: stream
            path:  "/dev/stderr"
            level: error
EOF
fi


    cd /data
    /usr/bin/composer install --no-interaction --no-dev --optimize-autoloader
fi

# Create workers in supervisord
cd /data
workers=""
if [ -f boot ];
then
    workers=$(/bin/bash ./boot)
else
    workers=$(php app/console melin:systemeventlistener:launch -e worker | grep -v "PHP Warning")
    workers="$workers
    $(php app/console melin:eventhandler:launch -e worker | grep -v "PHP Warning")
    $(php app/console melin:systemevents:launch -e worker | grep -v "PHP Warning")"
fi

if [ "$workers" == "" ] && [ ! -f /data/WorkerBoot ];
then
    echo "No workers to launch. Quitting"
    exit 1
fi

i=1
while read job; do
    job=$(echo $job | perl -pe 's/\\/\\\\/g' )

    if [ "x$job" != "x" ]; then
        echo -e "\n[program:worker$i]\ncommand=$job\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0" >> /etc/supervisord.conf
        let i=i+1
    fi
done <<< "$workers"

if [ -f /data/WorkerBoot ]; then
    while read line; do
      job=`echo $line | awk '{ $1=""; print $0}' | sed -e 's/^[[:space:]]*//'`

      if [ "x$job" != "x" ]; then
          echo -e "\n[program:worker$i]\ncommand=$job\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0" >> /etc/supervisord.conf
          let i=i+1
      fi
    done < /data/WorkerBoot
fi

build_id=0
if [ -f /data/build_version ];
then
    build_id=$(cat /data/build_version)
fi

# Notifications
cd /data
php app/console newrelic:notify-deployment --revision="$build_id" -e prod
php app/console melin:clientmessaging:newdeployment -e prod
php app/console melin:cloudinary:upload -e prod

# Start supervisord and services
/usr/bin/supervisord -n -c /etc/supervisord.conf
