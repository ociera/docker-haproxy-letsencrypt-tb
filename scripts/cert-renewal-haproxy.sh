#!/usr/bin/env bash

set -euo pipefail

# automatización de la renovación de certificados para Let's Encrypt y HAProxy
# - verifica todos los certificados bajo /etc/letsencrypt/live y renueva
#   aquellos que están a punto de expirar en menos de 4 semanas
# - crea archivos haproxy.pem en /etc/letsencrypt/live/dominio.tld/
# - soft-restarts HAProxy para aplicar los nuevos certificados
# uso:
# sudo ./cert-renewal-haproxy.sh

################################################################################
### global settings
################################################################################

LE_CLIENT="certbot"

HAPROXY_RELOAD_CMD="supervisorctl signal HUP haproxy"
HAPROXY_SOFTSTOP_CMD="supervisorctl signal USR1 haproxy"

WEBROOT="/jail"
# Habilitar para redirigir la salida a un archivo de registro (para silent cron jobs)
# Dejarlo vacío para registrar en STDOUT/ERR (registro de Docker)
#LOGFILE="/var/log/certrenewal.log"
LOGFILE=""

################################################################################
### FUNCIONES
################################################################################

function issueCert {
  $LE_CLIENT certonly --text --webroot --webroot-path ${WEBROOT} --renew-by-default --agree-tos --email ${EMAIL} ${1} &>/dev/null
  return $?
}

function logger_error {
  if [ -n "${LOGFILE}" ]
  then
    echo "[error] ${1}\n" >> ${LOGFILE}
  fi
  >&2 echo "[error] ${1}"
}

function logger_info {
  if [ -n "${LOGFILE}" ]
  then
    echo "[info] ${1}\n" >> ${LOGFILE}
  else
    echo "[info] ${1}"
  fi
}

################################################################################
### MAIN
################################################################################

le_cert_root="/etc/letsencrypt/live"

if [ ! -d ${le_cert_root} ]; then
  logger_error "${le_cert_root} does not exist!"
  exit 1
fi

# verificar la expiración del certificado y ejecutar solicitudes de emisión de certificado
# para aquellos que expiran en menos de 4 semanas
renewed_certs=()
exitcode=0
while IFS= read -r -d '' cert; do
  if ! openssl x509 -noout -checkend $((4*7*86400)) -in "${cert}"; then
    subject="$(openssl x509 -noout -subject -in "${cert}" | grep -o -E 'CN = [^ ,]+' | tr -d 'CN = ')"
    subjectaltnames="$(openssl x509 -noout -text -in "${cert}" | sed -n '/X509v3 Subject Alternative Name/{n;p}' | sed 's/\s//g' | tr -d 'DNS:' | sed 's/,/ /g')"
    domains="-d ${subject}"
    for name in ${subjectaltnames}; do
      if [ "${name}" != "${subject}" ]; then
        domains="${domains} -d ${name}"
      fi
    done
    issueCert "${domains}"
    if [ $? -ne 0 ]
    then
      logger_error "failed to renew certificate! check /var/log/letsencrypt/letsencrypt.log!"
      exitcode=1
    else
      renewed_certs+=("$subject")
      logger_info "renewed certificate for ${subject}"
    fi
  else
    logger_info "none of the certificates requires renewal"
  fi
done < <(find ${le_cert_root} -name cert.pem -print0)

# crear archivos haproxy.pem
for domain in ${renewed_certs[@]}; do
  cat ${le_cert_root}/${domain}/privkey.pem ${le_cert_root}/${domain}/fullchain.pem | tee /etc/haproxy/certs/haproxy-${domain}.pem >/dev/null
  if [ $? -ne 0 ]; then
    logger_error "failed to create haproxy.pem file!"
    exit 1
  fi
done

# soft-stop (y reinicio implícito) de HAProxy
# (el comando RELOAD no recarga los certificados)
if [ "${#renewed_certs[@]}" -gt 0 ]; then
  $HAPROXY_SOFTSTOP_CMD
  if [ $? -ne 0 ]; then
    logger_error "failed to stop haproxy!"
    exit 1
  fi
fi

exit ${exitcode}
