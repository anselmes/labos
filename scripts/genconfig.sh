#!/bin/bash
# SPDX-License-Identifier: GPL-3.0

[[ -z "${LABOS_DIR}" ]] && echo "LABOS_DIR is not set" && exit 1

mkdir -p "${SITE_DIR}"

if [[ ! -f "${SITE_CONFIG}" ]]; then
  cp -f "${LABOS_DIR}/config/site.yaml" "${SITE_DIR}/site.yaml"
  yq --inplace '
    (.. | select(tag == "!!str")) |= envsubst
  ' "${SITE_DIR}/site.yaml"
fi

eval $(yq --output-format shell "${SITE_CONFIG}")

export domain

export spec_config_pki_ca_cert_file
export spec_config_pki_ca_key_file
export spec_config_ssh_key_file

export spec_provider_vyos_as
export spec_provider_vyos_hostname
export spec_provider_vyos_interfaces_0_address_ipv4_cidr
export spec_provider_vyos_interfaces_0_address_ipv6_cidr
export spec_provider_vyos_interfaces_1_address_ipv4_cidr
export spec_provider_vyos_interfaces_1_address_ipv6_cidr
export spec_provider_vyos_interfaces_2_address_ipv4_cidr
export spec_provider_vyos_interfaces_2_address_ipv6_cidr
export spec_provider_vyos_interfaces_3_address_ipv4_cidr
export spec_provider_vyos_interfaces_3_address_ipv6_cidr
export spec_provider_vyos_user_name

export spec_service_bgp_cilium_password
export spec_service_dns_nameservers_0
export spec_service_dns_nameservers_1
export spec_service_ntp_servers_0
export spec_service_ntp_servers_1
export spec_service_ntp_timezone

export spec_cluster_bootstrap_cni_file
export spec_cluster_bootstrap_csi_file
export spec_cluster_bootstrap_capi_file

export status_vyos_config

# ssh config
ssh_config() {
  stat "${spec_config_ssh_key_file}" > /dev/null 2>&1 ||
  ssh-keygen -N "" -C "${SITE_NAME}" -t ed25519 -f "${spec_config_ssh_key_file}"

  if [[ -z "${status_pubkey}" ]]; then
    export status_gpg="${spec_config_ssh_key_file}.pub"
    yq --inplace '
      .status.pubkey = load(env(status_gpg))
    ' "${SITE_CONFIG}"
  fi
}

# gpg config
gpg_config() {
  if ! gpg --homedir "${spec_config_gpg_dir}" -k "${SITE_NAME}" > /dev/null 2>&1; then
    cat <<eof > "${spec_config_gpg_dir}/${SITE_NAME}.batch"
%no-protection
# %no-ask-passphrase
Key-Type: RSA
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Real: "${SITE_NAME}"
eof
    gpg --no-tty --batch --homedir "${spec_config_gpg_dir}" --gen-key "${spec_config_gpg_dir}/${SITE_NAME}.batch"
  fi

  if [[ -z "${status_gpg}" ]]; then
    export status_gpg="$(gpg --homedir "${spec_config_gpg_dir}" --list-keys "${SITE_NAME}" | head -n +2 | tail -n 1 | tr -d ' ')"
    yq --inplace '
      .status.pgp = env(status_gpg)
    ' "${SITE_CONFIG}"
  fi
}

# todo: sops config

# root ca config
root_ca() {
  mkdir -p "${spec_config_pki_dir}"

  stat "${spec_config_pki_dir}/index.txt" > /dev/null 2>&1 ||
  touch "${spec_config_pki_dir}/index.txt"

  stat "${spec_config_pki_ca_key_file}" > /dev/null 2>&1 ||
  openssl genrsa -out "${spec_config_pki_ca_key_file}" 4096

  if ! stat "${spec_config_pki_ca_cert_file}" > /dev/null 2>&1; then
    "${LABOS_DIR}/scripts/gencert.sh" --root-ca \
      "${config_pki_ca_subj}" \
      "${spec_config_pki_ca_key_file}" \
      "${spec_config_pki_ca_cert_file}" \
      "${SITE_DIR}/ca.pfx"
  fi

  if [[ -z "${status_ca}" ]]; then
    export status_ca="$(cat ${spec_config_pki_ca_cert_file} | base64)"
    yq --inplace '
      .status.ca = strenv(status_ca)
    ' "${SITE_CONFIG}"
  fi
}

# vm config
vm_config() {
  export spec_service_libvirt_type
  export spec_service_libvirt_arch
  export spec_service_libvirt_emulator
  export spec_service_libvirt_firmware

  export vm_cpu_model="${1}"

  [[ -z "${vm_cpu_model}" ]] && export vm_cpu_model="host-passthrough"
  [[ -z "${vm_config_file}" ]] && export vm_config_file="${SITE_DIR}/vm.xml"

  yq '
    (.. | select(tag == "!!str")) |= envsubst |
    .domain.cpu.+@mode = env(vm_cpu_model)
  ' "${LABOS_DIR}/config/vm.xml" > "${vm_config_file}"

  # note: watchdog is automatically set for x86_64
  if [[ "${spec_service_libvirt_arch}" != "x86_64" ]]; then
    export vm_watchdog_model="i6300esb"
    export vm_watchdog_action="reset"
    yq --inplace '
      .domain.devices.watchdog.+@model=env(vm_watchdog_model) |
      .domain.devices.watchdog.+@action=env(vm_watchdog_action)
    ' "${vm_config_file}"
  fi
}

# vyos config
vyos_config() {
  mkdir -p "${SITE_DIR}/vyos"

  # vyos intermediate ca
  stat "${spec_provider_vyos_ca_key_file}" > /dev/null 2>&1 ||
  openssl genrsa -out "${spec_provider_vyos_ca_key_file}" 4096

  if ! stat "${spec_provider_vyos_ca_cert_file}" > /dev/null 2>&1; then
    "${LABOS_DIR}/scripts/gencert.sh" --intermediate-ca \
      "${spec_provider_vyos_ca_subj}" \
      "${spec_provider_vyos_ca_days}" \
      "${spec_provider_vyos_ca_key_file}" \
      "${spec_provider_vyos_ca_cert_file}" \
      "${spec_provider_vyos_ca_bundle}"
  fi

  # vyos cloud init
  export status_ca
  [[ -z "${status_ca}" ]] && echo "missing ca cert" && exit 1

  export spec_provider_vyos_interfaces_0_address_ipv4_addr="$(echo ${spec_provider_vyos_interfaces_0_address_ipv4_cidr} | cut -d '/' -f 1)"
  export spec_provider_vyos_interfaces_0_address_ipv6_addr="$(echo ${spec_provider_vyos_interfaces_0_address_ipv6_cidr} | cut -d '/' -f 1)"
  export spec_provider_vyos_interfaces_1_address_ipv4_addr="$(echo ${spec_provider_vyos_interfaces_1_address_ipv4_cidr} | cut -d '/' -f 1)"
  export spec_provider_vyos_interfaces_1_address_ipv6_addr="$(echo ${spec_provider_vyos_interfaces_1_address_ipv6_cidr} | cut -d '/' -f 1)"

  if [[ -z "${status_vyos_ca}" ]]; then
    export status_vyos_ca="$(cat ${spec_provider_vyos_ca_cert_file} | base64 -w0)"
    yq --inplace '
      .status.vyos.ca = strenv(status_vyos_ca)
    ' "${SITE_CONFIG}"
  fi
  if [[ -z "${status_vyos_config}" ]]; then
    export vyos_ca="$(tail -n +2 ${spec_provider_vyos_ca_cert_file} | sed '$ d' | tr -d '\n')"
    export vyos_ca_key="$(tail -n +2 ${spec_provider_vyos_ca_key_file} | sed '$ d' | tr -d '\n')"
    export vyos_config="${SITE_DIR}/vyos/config.boot.default"
    yq --input-format uri --output-format yaml '
      (.. | select(tag == "!!str")) |= envsubst
    ' ${LABOS_DIR}/config/vyos/config.boot.default > "${vyos_config}"
    export status_vyos_config="$(cat ${vyos_config} | base64 -w0)"
    yq --inplace '
      .status.vyos.config = strenv(status_vyos_config)
    ' "${SITE_CONFIG}"
  fi

  touch "${SITE_DIR}/vyos/meta-data"
  cp -f "${LABOS_DIR}/config/vyos/network.yaml" "${SITE_DIR}/vyos/network-config"
  yq '
    .write_files[0].content = strenv(status_vyos_config) |
    .write_files[1].content = strenv(status_ca)
  ' "${LABOS_DIR}/config/vyos/config.yaml" > "${SITE_DIR}/vyos/user-data"

  # fixme: vyos vm
  export vm_config_file="${SITE_DIR}/vyos/vm.xml"
  vm_config "host-passthrough"
}

# generate cloud init
cloudinit() {
  export macaddress="${1}"

  [[ -z "${macaddress}" ]] && echo "missing mac address" && exit 1

  # network-config
  export NETPLAN="$(sed '/#/d' ${LABOS_DIR}/config/netplan/default.yaml)"
  yq '
    . *+ env(NETPLAN) |
    .network.ethernets.oam.match.macaddress = env(macaddress)
  ' "${LABOS_DIR}/config/netplan/default.yaml" > "${SITE_DIR}/network-config"

  # # user-data
  export PACKAGES="$(sed '/#/d' ${LABOS_DIR}/config/cloudinit/packages.yaml)"

  if ! stat "${config_ssh_pubkey_file}" > /dev/null 2>&1; then
    echo "missing ssh pubkey"
    exit 1
  elif ! stat "${spec_config_pki_ca_cert_file}" > /dev/null 2>&1; then
    echo "missing ca cert"
    exit 1
  fi

  export config_ssh_pubkey_content="$(cat ${config_ssh_pubkey_file})"
  export status_ca="$(cat ${spec_config_pki_ca_cert_file})"

  yq '
    . *+ env(PACKAGES) |
    .ssh_authorized_keys = [env(config_ssh_pubkey_content)] |
    .ca_certs.trusted = [strenv(status_ca)]
  ' "${LABOS_DIR}/config/cloudinit/default.yaml" > "${SITE_DIR}/user-data"
}

# bootstrap
bootstrap() {
  # generate k0s config
  export K0S_CONFIG="$(yq '
    . *+ load(env(spec_cluster_bootstrap_cni_file)) |
    . *+ load(env(spec_cluster_bootstrap_csi_file)) |
    . *+ load(env(spec_cluster_bootstrap_capi_file))
  ' ${LABOS_DIR}/config/bootstrap/config.yaml)"

  # generate k0sctl config
  yq '
    .spec.hosts[].ssh.keyPath = env(spec_config_ssh_key_file) |
    .spec.k0s.config = env(K0S_CONFIG)
  ' "${LABOS_DIR}/config/bootstrap/cluster.yaml" > "${SITE_DIR}/bootstrap.yaml"
}

# todo: generate secrets

case "${1}" in
  bootstrap)
    bootstrap
    ;;
  ssh)
    ssh_config
    ;;
  gpg)
    gpg_config
    ;;
  rootca)
    root_ca
    ;;
  cloudinit)
    echo "${1}" "${2}"
    cloudinit "${2}"
    ;;
  vm)
    vm_config "${2}" "${3}" "${4}"
    ;;
  vyos)
    vyos_config
    ;;
  *)
    echo """
usage: ${0} [OPTIONS]

OPTIONS:
  bootstrap
  ssh
  gpg
  rootca
  cloudinit [mac-address]
  vm [cpu-model]
  vyos

EXAMPLES:
  ${0} cloudinit ba:be:fa:ce:00:00
  ${0} vm host-passthrough
"""
    ;;
esac
