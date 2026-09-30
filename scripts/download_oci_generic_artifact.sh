#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Uso:
  scripts/download_oci_generic_artifact.sh \
    --repository-id <ocid> \
    --artifact-path <path> \
    --artifact-version <versao> \
    --output-file <arquivo>

Opcoes:
  --repository-id <ocid>       OCID do Artifact Registry repository.
  --artifact-path <path>       Caminho logico do artifact.
  --artifact-version <versao>  Versao do artifact.
  --output-file <arquivo>      Arquivo de saida.
  --profile <nome>             Perfil do OCI CLI.
  --region <regiao>            Regiao do OCI CLI.
  -h, --help                   Mostra esta ajuda.

Exemplo:
  scripts/download_oci_generic_artifact.sh \
    --repository-id ocid1.artifactrepository.oc1..aaaa \
    --artifact-path oic/deploy.car \
    --artifact-version 20260703.1 \
    --output-file out/deploy.car
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Dependencia obrigatoria nao encontrada: $1" >&2
    exit 1
  }
}

REPOSITORY_ID=""
ARTIFACT_PATH=""
ARTIFACT_VERSION=""
OUTPUT_FILE=""
OCI_PROFILE="${OCI_CLI_PROFILE:-}"
OCI_REGION="${OCI_CLI_REGION:-${OCI_REGION:-}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository-id)
      REPOSITORY_ID="${2:-}"
      shift 2
      ;;
    --artifact-path)
      ARTIFACT_PATH="${2:-}"
      shift 2
      ;;
    --artifact-version)
      ARTIFACT_VERSION="${2:-}"
      shift 2
      ;;
    --output-file)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --profile)
      OCI_PROFILE="${2:-}"
      shift 2
      ;;
    --region)
      OCI_REGION="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opcao invalida: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$REPOSITORY_ID" || -z "$ARTIFACT_PATH" || -z "$ARTIFACT_VERSION" || -z "$OUTPUT_FILE" ]]; then
  echo "repository-id, artifact-path, artifact-version e output-file sao obrigatorios." >&2
  usage >&2
  exit 1
fi

require_cmd oci

mkdir -p "$(dirname "$OUTPUT_FILE")"

cmd=(
  oci artifacts generic artifact download-by-path
  --repository-id "$REPOSITORY_ID"
  --artifact-path "$ARTIFACT_PATH"
  --artifact-version "$ARTIFACT_VERSION"
  --file "$OUTPUT_FILE"
)

if [[ -n "$OCI_PROFILE" ]]; then
  cmd+=(--profile "$OCI_PROFILE")
fi

if [[ -n "$OCI_REGION" ]]; then
  cmd+=(--region "$OCI_REGION")
fi

# Silencia apenas o aviso conhecido do urllib3 sobre o parametro strict.
# Filtros definidos pelo usuario em PYTHONWARNINGS continuam tendo precedencia.
warning_filter="ignore:The 'strict' parameter is no longer needed on Python 3+.:FutureWarning:urllib3.poolmanager"
PYTHONWARNINGS="${warning_filter}${PYTHONWARNINGS:+,${PYTHONWARNINGS}}" \
  "${cmd[@]}"

echo "Artifact baixado em: $OUTPUT_FILE"
