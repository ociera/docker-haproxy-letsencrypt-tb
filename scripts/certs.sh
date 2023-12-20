  GNU nano 5.4                                                                                                                 certs.sh
#!/usr/bin/env bash

if [ -n "$CERT1" ] || [ -n "$CERT" ]; then
    error_count=0
    if [ "$STAGING" = true ]; then
        for certname in ${!CERT*}; do
            if ! certbot certonly --no-self-upgrade -n --text --standalone \
                --preferred-challenges http-01 \
                --staging \
                -d "${!certname}" --keep --expand --agree-tos --email "$EMAIL"; then
                ((error_count++))
                echo "Error en la renovacion del certificado para $certname. Intento $error_count de 1."
                [ $error_count -ge 1 ] && { echo "Maximo numero de intentos alcanzados."; exit 2; }
            else
                error_count=0
            fi
        done
    else
        for certname in ${!CERT*}; do
            if ! certbot certonly --no-self-upgrade -n --text --standalone \
                --preferred-challenges http-01 \
                -d "${!certname}" --keep --expand --agree-tos --email "$EMAIL"; then
                ((error_count++))
                echo "Error en la renovacion del certificado para $certname. Intento $error_count de 1."
                [ $error_count -ge 1 ] && { echo "Maximo numero de intentos alcanzados."; exit 1; }
            else
                error_count=0
            fi
        done
    fi

    [ $error_count -eq 0 ] && {
        mkdir -p /etc/haproxy/certs
        for site in $(ls -1 /etc/letsencrypt/live | grep -v ^README$); do
            cat /etc/letsencrypt/live/$site/privkey.pem \
                /etc/letsencrypt/live/$site/fullchain.pem \
                | tee /etc/haproxy/certs/haproxy-"$site".pem >/dev/null
        done
    }
fi

exit 0
