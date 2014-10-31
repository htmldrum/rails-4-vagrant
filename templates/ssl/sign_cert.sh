#!/bin/bash - 
#===============================================================================
#
#          FILE: sign_cert.sh
# 
#         USAGE: ./sign_cert.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: YOUR NAME (), 
#  ORGANIZATION: 
#       CREATED: 10/29/2014 15:38#      REVISION:  ---
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

if [ "$(id -u)" == "0" ]; then
   echo "Please run this script as a regular user with sudo privileges." 1>&2
   exit 1
fi

echo "Creating server key"
openssl genrsa -des3 -out server.key 1024

echo "Creating certificate signing request: Only important field is common name ( should be domain )"
openssl req -new -key server.key -out server.csr

echo "Removing passphrase-less certificate"
cp server.key server.key.org
openssl rsa -in server.key.org -out server.key

echo "signing the SSL certificate"
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

echo "Now done making certificate"
