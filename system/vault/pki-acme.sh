#!/bin/bash

set -euxo pipefail

vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki
vault write -field=certificate pki/root/generate/internal \
   common_name="edgecdnx.com" \
   issuer_name="issuer-edgecdnx.com" \
   ttl=87600h > issuer-edgecdnx_ca.crt
vault write pki/config/cluster \
   path=http://vault.vault.svc.cluster.local:8200/v1/pki \
   aia_path=http://vault.vault.svc.cluster.local:8200/v1/pki
vault write pki/roles/edgecdnx \
   allow_any_name=true \
   no_store=false

vault write pki/config/urls \
   issuing_certificates={{cluster_aia_path}}/issuer/{{issuer_id}}/der \
   crl_distribution_points={{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der \
   ocsp_servers={{cluster_path}}/ocsp \
   enable_templating=true

vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int
vault write -format=json pki_int/intermediate/generate/internal \
   common_name="edgecdnx.com Intermediate Authority" \
   issuer_name="edgecdnx-intermediary" \
   | jq -r '.data.csr' > pki_intermediate.csr

vault write -format=json pki/root/sign-intermediate \
   issuer_ref="issuer-edgecdnx.com" \
   csr=@pki_intermediate.csr \
   format=pem_bundle ttl="43800h" \
   | jq -r '.data.certificate' > intermediate.cert.pem


vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem
vault write pki_int/config/cluster \
   path=http://vault.vault.svc.cluster.local:8200/v1/pki_int \
   aia_path=http://vault.vault.svc.cluster.local:8200/v1/pki_int


vault write pki_int/roles/issuers \
   issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
   allow_any_name=true \
   max_ttl="720h" \
   no_store=false
vault write pki_int/config/urls \
   issuing_certificates={{cluster_aia_path}}/issuer/{{issuer_id}}/der \
   crl_distribution_points={{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der \
   ocsp_servers={{cluster_path}}/ocsp \
   enable_templating=true
