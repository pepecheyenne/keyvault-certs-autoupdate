#!/bin/bash
##location: /usr/local/bin/pihole-cert-renew.sh
set -euo pipefail

VAULT_NAME="kv-acme-synv"
CERT_NAME="maunaloa-redlocal-pro"
WORKDIR="/tmp/unifi-cert"
FQDN="rpi.maunaloa.redlocal.pro"
EMAIL="pepe@asistenciatecnicaonline.com"

# ==== Separador con fecha/hora ====
echo "===================================================================="
echo "[INFO] Inicio de ejecución: $(date '+%Y-%m-%d %H:%M:%S')"
echo "===================================================================="

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[INFO] Descargando certificado desde Key Vault..."
az login --identity
az keyvault secret download \
  --file test.pfx \
  --encoding base64 \
  --name "$CERT_NAME" \
  --vault-name kv-acme-synv\
  --overwrite

az keyvault secret download \
  --encoding base64 \
  --vault-name "$VAULT_NAME" \
  --name "$CERT_NAME" \
  --file "$WORKDIR/unifi-cert.pfx" \
  --overwrite

echo "[INFO] Extrayendo clave privada y certificados..."
# Convertir PFX a PEM
openssl pkcs12 -in "$WORKDIR/unifi-cert.pfx" -nodes -out "$WORKDIR/unifi-cert.pem" -password pass:

# Extraer clave privada
openssl pkey -in "$WORKDIR/unifi-cert.pem" -out "$WORKDIR/PRIVATE.key"

# Extraer certificado principal
openssl pkcs12 -in "$WORKDIR/unifi-cert.pfx" -clcerts -nokeys -out "$WORKDIR/SSL_CERTIFICATE.cer" -password pass:

# Extraer cadena/intermedio si existe
openssl pkcs12 -in "$WORKDIR/unifi-cert.pfx" -nodes -nokeys -cacerts -out "$WORKDIR/CHAIN.cer" -password pass: || true

echo "[INFO] Validando si el certificado cambió..."
NEW_FP=$(openssl x509 -in "$WORKDIR/SSL_CERTIFICATE.cer" -noout -fingerprint -sha256 | cut -d= -f2)

CURRENT_FP=$(echo | \
  openssl s_client -connect uc.redlocal.pro:8443 -servername uc.redlocal.pro 2>/dev/null | \
  openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)

if [ "$NEW_FP" = "$CURRENT_FP" ]; then
    echo "[INFO] El certificado en UniFi ya es el mismo que el descargado, no se reemplaza."
    exit 0
fi

echo "[INFO] Actualizando certificado en UniFi..."
sudo bash "$UNIFI_SCRIPT" \
  --skip \
  --own-certificate \
  --private-key "$WORKDIR/PRIVATE.key" \
  --signed-certificate "$WORKDIR/SSL_CERTIFICATE.cer" \
  --fqdn "$FQDN" \
  --email "$EMAIL"

echo "[INFO] Certificado actualizado correctamente"