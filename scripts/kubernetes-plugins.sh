#!/bin/bash
# SPDX-License-Identifier: GPL-3.0

PLUGINS=(
  "access-matrix"
  "ca-cert"
  "cert-manager"
  "cilium"
  "config-import"
  "ctx"
  "debug-shell"
  "deprecations"
  "df-pv"
  "hns"
  "images"
  "minio"
  "node-shell"
  "ns"
  "nsenter"
  "oidc-login"
  "open-svc"
  "openebs"
  "pod-shell"
  "rabbitmq"
  "rook-ceph"
  "view-cert"
  "view-secret"
  "view-serviceaccount-kubeconfig"
  "view-utilization"
  "view-webhook"
  "virt"
)

for PLUGIN in "${PLUGINS[@]}"; do
  kubectl krew install "${PLUGIN}"
done
