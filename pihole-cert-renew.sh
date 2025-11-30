#!/bin/bash
##location: /usr/local/bin/pihole-cert-renew.sh
set -euo pipefail

VAULT_NAME="kv-acme-synv"
CERT_NAME="maunaloa-redlocal-pro"
WORKDIR="/tmp/rpi-cert"
FQDN="rpi.maunaloa.redlocal.pro"
EMAIL="pepe@asistenciatecnicaonline.com"
DESTDIR="/etc/pihole"

# ==== Separador con fecha/hora ====
echo "===================================================================="
echo "[INFO] Inicio de ejecución: $(date '+%Y-%m-%d %H:%M:%S')"
echo "===================================================================="

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[INFO] Descargando certificado desde Key Vault..."
az login --identity

az keyvault secret download \
  --encoding base64 \
  --vault-name "$VAULT_NAME" \
  --name "$CERT_NAME" \
  --file "$WORKDIR/cert.pfx" \
  --overwrite

echo "[INFO] Extrayendo clave privada y certificados..."
# Convertir PFX a PEM
openssl pkcs12 -in "$WORKDIR/cert.pfx" -nodes -out "$WORKDIR/CERT.pem" -password pass:

# Extraer clave privada
openssl pkey -in "$WORKDIR/CERT.pem" -out "$WORKDIR/PRIVATE.key"

# Extraer certificado principal
openssl pkcs12 -in "$WORKDIR/cert.pfx" -clcerts -nokeys -out "$WORKDIR/SSL_CERTIFICATE.cer" -password pass:

# Extraer cadena/intermedio si existe
openssl pkcs12 -in "$WORKDIR/cert.pfx" -nodes -nokeys -cacerts -out "$WORKDIR/CHAIN.cer" -password pass: || true

echo "[INFO] Validando si el certificado cambió..."
NEW_FP=$(openssl x509 -in "$WORKDIR/SSL_CERTIFICATE.cer" -noout -fingerprint -sha256 | cut -d= -f2)

CURRENT_FP=$(echo | \
  openssl s_client -connect "$FQDN:443" -servername "$FQDN" 2>/dev/null | \
  openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)

if [ "$NEW_FP" = "$CURRENT_FP" ]; then
    echo "[INFO] El certificado en Rpi ya es el mismo que el descargado, no se reemplaza."
    exit 0
fi

echo "[INFO] Actualizando certificado en pihole..."
cp  "$WORKDIR/SSL_CERTIFICATE.cer" "$DESTDIR/tls.pem"
cat "$WORKDIR/PRIVATE.key" >> "$DESTDIR/tls.pem"

echo "[INFO] Reiniciando el servicio pihole-FTL..."
service pihole-FTL restart

echo "[INFO] Certificado actualizado correctamente"