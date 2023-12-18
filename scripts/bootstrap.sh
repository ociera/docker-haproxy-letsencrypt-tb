#!/usr/bin/env bash

# guardar las variables de entorno del contenedor para usarlas
# en scripts cron

declare -p | grep -Ev '^declare -[[:alpha:]]*r' > /container.env

# go!
/certs.sh && supervisord -c /etc/supervisord.conf -n
