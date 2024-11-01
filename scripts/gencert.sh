#!/bin/bash
# SPDX-License-Identifier: GPL-3.0

generate_root_ca() {
  CA_CERT_SUBJ="${1}"
  CA_KEY_FILE="${2:-/tmp/ca.key}"
  CA_CERT_FILE="${3:-/tmp/ca.crt}"
  CA_CERT_PKCS12_FILE="${4:-/tmp/ca.pfx}"
  CA_VALID_FOR="${5:-3065}"

  [[ -z "${CA_CERT_SUBJ}" ]] && echo "ca certificate subject is required" && exit 1

  openssl req \
    -new \
    -x509 \
    -days ${CA_VALID_FOR} \
    -extensions v3_ca \
    -keyout "${CA_KEY_FILE}" \
    -out "${CA_CERT_FILE}" \
    -passout pass: \
    -subj "${CA_CERT_SUBJ}" \

  openssl pkcs12 \
    -export \
    -in "${CA_CERT_FILE}" \
    -inkey "${CA_KEY_FILE}" \
    -out "${CA_CERT_PKCS12_FILE}" \
    -passin pass: \
    -passout pass:
}

generate_intermediate_ca() {
  CA_CERT_FILE="${1}"
  CA_KEY_FILE="${2}"
  INTERMEDIATE_CERT_SUBJ="${3}"
  INTERMEDIATE_CA_KEY_FILE="${4:-/tmp/ca.key}"
  INTERMEDIATE_CA_FILE="${5:-/tmp/ca.crt}"
  INTERMEDIATE_CERT_PKCS12_FILE="${6:-/tmp/ca.pfx}"
  INTERMEDIATE_CA_VALID_FOR="${7:-365}"

  [[ -z "${CA_CERT_FILE}" ]] && echo "ca certificate file is required" && exit 1
  [[ -z "${CA_KEY_FILE}" ]] && echo "ca key file is required" && exit 1
  [[ -z "${INTERMEDIATE_CERT_SUBJ}" ]] && echo "intermediate certificate subject is required" && exit 1

  OUT_DIR="$(dirname ${INTERMEDIATE_CA_FILE})"

  openssl genrsa -out "${INTERMEDIATE_CA_KEY_FILE}"

  openssl req \
    -new \
    -key "${INTERMEDIATE_CA_KEY_FILE}" \
    -out /tmp/intermediate-ca.csr \
    -subj "${INTERMEDIATE_CERT_SUBJ}"

  cd "${OUT_DIR}"
  openssl ca \
    -batch \
    -notext \
    -create_serial \
    -cert "${CA_CERT_FILE}" \
    -days ${INTERMEDIATE_CA_VALID_FOR} \
    -extensions v3_ca \
    -in /tmp/intermediate-ca.csr \
    -keyfile "${CA_KEY_FILE}" \
    -out "${INTERMEDIATE_CA_FILE}" \
    -outdir "${OUT_DIR}" \
    -passin pass: \
    -policy policy_anything \
    -subj "${INTERMEDIATE_CERT_SUBJ}"
  cd -

  openssl pkcs12 \
    -export \
    -in "${INTERMEDIATE_CA_FILE}" \
    -inkey "${INTERMEDIATE_CA_KEY_FILE}" \
    -out "${INTERMEDIATE_CERT_PKCS12_FILE}" \
    -passout pass:

  rm -f /tmp/intermediate-ca.csr
}

case "${1}" in
  --root-ca)
    generate_root_ca "${@:2}"
    ;;
  --intermediate-ca)
    generate_intermediate_ca "${@:2}"
    ;;
  *)
    echo """
Usage: ${0} [OPTIONS]

OPTIONS:
  --root-ca <ca-subject> [ca-key-file] [ca-cert-file] [ca-pkcs12-file] [valid-for]
  --intermediate-ca <ca-cert-file> <ca-key-file> <intermediate-subject> [intermediate-ca-key-file] [intermediate-ca-file] [intermediate-ca-pkcs12-file] [valid-for]

EXAMPLES:
  ${0} --root-ca '/C=US/ST=CA/O=Example/CN=Root CA' /tmp/ca.key /tmp/ca.crt /tmp/ca.pfx 3650
  ${0} --intermediate-ca /tmp/ca.crt /tmp/ca.key '/C=US/ST=CA/O=Example/CN=Intermediate CA' /tmp/ca.key /tmp/ca.crt /tmp/ca.pfx 365
"""
    exit 1
    ;;
esac
