#!/bin/bash
# Redact creds from uci config dump

file="${1:-uci.txt}"

sed -Ei \
    -e 's/(\.private_key=).*/\1REDACTED/' \
    -e 's/(\.public_key=).*/\1REDACTED/' \
    -e 's/(wireless\.[^.]+\.key=).*/\1REDACTED/' \
    -e 's/(wireless\.[^.]+\.ssid=).*/\1REDACTED/' \
    -e 's/(rpcd\.@login\[0\]\.password=).*/\1REDACTED/' \
"$file"
