#!/bin/bash
# Script to export Developer ID certificate for CI/CD

echo "Exporting Developer ID certificate and key..."

# Export to P12 format with password
security export -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -o developer-id.p12 \
  -P "conveyor-ci-temp-password"

# Convert P12 to separate certificate and key files for CI
openssl pkcs12 -in developer-id.p12 -out apple-cert.pem -nokeys -passin pass:conveyor-ci-temp-password
openssl pkcs12 -in developer-id.p12 -out apple-key.pem -nocerts -nodes -passin pass:conveyor-ci-temp-password

# Base64 encode for GitHub secrets
echo "Base64 encoded certificate (for APPLE_CERT secret):"
base64 < apple-cert.pem

echo ""
echo "Base64 encoded key (for APPLE_KEY secret):"
base64 < apple-key.pem

# Clean up temporary files
rm developer-id.p12
echo "Done! Add the base64 outputs as GitHub secrets."