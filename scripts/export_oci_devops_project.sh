#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Uso:
  scripts/export_oci_devops_project.sh --project-id <ocid> [opcoes]

Opcoes:
  --project-id <ocid>         OCID do projeto OCI DevOps.
  --compartment-id <ocid>     OCID do compartment. Se omitido, sera lido do projeto.
  --output-dir <dir>          Diretorio raiz da exportacao.
  --profile <nome>            Perfil do OCI CLI.
  --region <regiao>           Regiao do OCI CLI.
  --include-runs              Exporta tambem build runs e deployments recentes.
  --runs-limit <n>            Quantidade maxima de runs/deployments por pipeline. Padrao: 20.
  -h, --help                  Mostra esta ajuda.

Exemplo:
  scripts/export_oci_devops_project.sh \
    --project-id ocid1.devopsproject.oc1..aaaa \
    --profile DEFAULT \
    --region sa-saopaulo-1 \
    --include-runs
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Dependencia obrigatoria nao encontrada: $1" >&2
    exit 1
  }
}

safe_name() {
  local value="${1:-item}"
  value="${value// /_}"
  value="$(printf '%s' "$value" | tr -cd '[:alnum:]_.-')"
  if [[ -z "$value" ]]; then
    value="item"
  fi
  printf '%s' "$value"
}

ocid_suffix() {
  local value="$1"
  value="${value##*.}"
  value="$(printf '%s' "$value" | tr -cd '[:alnum:]')"
  if [[ -z "$value" ]]; then
    value="ocid"
  fi
  printf '%.18s' "$value"
}

write_json() {
  local target="$1"
  shift
  oci_json "$@" | jq '.' >"$target"
}

iter_data_items() {
  local source_json="$1"
  jq -c '
    .data[]?
    | if type == "array" then .[] else . end
    | select(type == "object")
  ' "$source_json"
}

count_data_items() {
  local source_json="$1"
  jq '
    [
      .data[]?
      | if type == "array" then .[] else . end
      | select(type == "object")
    ] | length
  ' "$source_json"
}

oci_json() {
  local args=("$@")
  if [[ -n "${OCI_PROFILE:-}" ]]; then
    args+=(--profile "$OCI_PROFILE")
  fi
  if [[ -n "${OCI_REGION:-}" ]]; then
    args+=(--region "$OCI_REGION")
  fi
  # Silencia apenas o aviso conhecido do urllib3 sobre o parametro strict.
  # Filtros definidos pelo usuario em PYTHONWARNINGS continuam tendo precedencia.
  local warning_filter="ignore:The 'strict' parameter is no longer needed on Python 3+.:FutureWarning:urllib3.poolmanager"
  PYTHONWARNINGS="${warning_filter}${PYTHONWARNINGS:+,${PYTHONWARNINGS}}" \
    oci "${args[@]}" --output json
}

export_collection() {
  local resource_dir="$1"
  local list_file="$2"
  local id_filter="$3"
  local get_cmd="$4"
  local get_flag="$5"
  local name_expr="$6"
  local item
  local id
  local name
  local file_name

  while IFS= read -r item; do
    id="$(jq -r "$id_filter" <<<"$item")"
    name="$(jq -r "$name_expr // empty" <<<"$item")"
    if [[ -z "$name" || "$name" == "null" ]]; then
      name="$id"
    fi
    file_name="$(safe_name "$name")--$(ocid_suffix "$id").json"
    write_json "${resource_dir}/${file_name}" devops ${get_cmd} get "${get_flag}" "$id"
  done < <(iter_data_items "$list_file")
}

PROJECT_ID=""
COMPARTMENT_ID=""
OUTPUT_DIR=""
OCI_PROFILE="${OCI_CLI_PROFILE:-}"
OCI_REGION="${OCI_CLI_REGION:-${OCI_REGION:-}}"
INCLUDE_RUNS="false"
RUNS_LIMIT="20"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      PROJECT_ID="${2:-}"
      shift 2
      ;;
    --compartment-id)
      COMPARTMENT_ID="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
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
    --include-runs)
      INCLUDE_RUNS="true"
      shift
      ;;
    --runs-limit)
      RUNS_LIMIT="${2:-}"
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

if [[ -z "$PROJECT_ID" ]]; then
  echo "--project-id e obrigatorio." >&2
  usage >&2
  exit 1
fi

if ! [[ "$RUNS_LIMIT" =~ ^[0-9]+$ ]]; then
  echo "--runs-limit deve ser numerico." >&2
  exit 1
fi

require_cmd oci
require_cmd jq

TMP_PROJECT_JSON="$(mktemp)"
trap 'rm -f "$TMP_PROJECT_JSON"' EXIT

write_json "$TMP_PROJECT_JSON" devops project get --project-id "$PROJECT_ID"

if [[ -z "$COMPARTMENT_ID" ]]; then
  COMPARTMENT_ID="$(jq -r '.data."compartment-id"' "$TMP_PROJECT_JSON")"
fi

if [[ -z "$COMPARTMENT_ID" || "$COMPARTMENT_ID" == "null" ]]; then
  echo "Nao foi possivel determinar o compartment-id do projeto." >&2
  exit 1
fi

PROJECT_NAME="$(jq -r '.data."name" // .data."display-name" // "devops-project"' "$TMP_PROJECT_JSON")"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="exports/$(safe_name "$PROJECT_NAME")-${TIMESTAMP}"
fi

mkdir -p \
  "$OUTPUT_DIR/project" \
  "$OUTPUT_DIR/build_pipelines" \
  "$OUTPUT_DIR/build_pipeline_stages" \
  "$OUTPUT_DIR/deploy_pipelines" \
  "$OUTPUT_DIR/deploy_stages" \
  "$OUTPUT_DIR/deploy_artifacts" \
  "$OUTPUT_DIR/deploy_environments" \
  "$OUTPUT_DIR/repositories" \
  "$OUTPUT_DIR/triggers" \
  "$OUTPUT_DIR/connections" \
  "$OUTPUT_DIR/meta"

if [[ "$INCLUDE_RUNS" == "true" ]]; then
  mkdir -p "$OUTPUT_DIR/build_runs" "$OUTPUT_DIR/deployments"
fi

cp "$TMP_PROJECT_JSON" "$OUTPUT_DIR/project/project.json"

cat >"$OUTPUT_DIR/meta/export_context.json" <<EOF
{
  "exportedAtUtc": "$TIMESTAMP",
  "projectId": "$PROJECT_ID",
  "projectName": $(jq -Rs . <<<"$PROJECT_NAME"),
  "compartmentId": "$COMPARTMENT_ID",
  "ociProfile": $(jq -Rs . <<<"${OCI_PROFILE:-}"),
  "ociRegion": $(jq -Rs . <<<"${OCI_REGION:-}"),
  "includeRuns": $INCLUDE_RUNS,
  "runsLimit": $RUNS_LIMIT
}
EOF

write_json "$OUTPUT_DIR/build_pipelines/_list.json" devops build-pipeline list --project-id "$PROJECT_ID" --all
write_json "$OUTPUT_DIR/deploy_pipelines/_list.json" devops deploy-pipeline list --project-id "$PROJECT_ID" --all
write_json "$OUTPUT_DIR/deploy_artifacts/_list.json" devops deploy-artifact list --project-id "$PROJECT_ID" --all
write_json "$OUTPUT_DIR/deploy_environments/_list.json" devops deploy-environment list --project-id "$PROJECT_ID" --all
write_json "$OUTPUT_DIR/repositories/_list.json" devops repository list --project-id "$PROJECT_ID" --all
write_json "$OUTPUT_DIR/triggers/_list.json" devops trigger list --project-id "$PROJECT_ID" --all
write_json "$OUTPUT_DIR/connections/_list.json" devops connection list --project-id "$PROJECT_ID" --all

export_collection \
  "$OUTPUT_DIR/build_pipelines" \
  "$OUTPUT_DIR/build_pipelines/_list.json" \
  '."id"' \
  "build-pipeline" \
  "--build-pipeline-id" \
  '."display-name"'

export_collection \
  "$OUTPUT_DIR/deploy_pipelines" \
  "$OUTPUT_DIR/deploy_pipelines/_list.json" \
  '."id"' \
  "deploy-pipeline" \
  "--pipeline-id" \
  '."display-name"'

export_collection \
  "$OUTPUT_DIR/deploy_artifacts" \
  "$OUTPUT_DIR/deploy_artifacts/_list.json" \
  '."id"' \
  "deploy-artifact" \
  "--artifact-id" \
  '."display-name"'

export_collection \
  "$OUTPUT_DIR/deploy_environments" \
  "$OUTPUT_DIR/deploy_environments/_list.json" \
  '."id"' \
  "deploy-environment" \
  "--environment-id" \
  '."display-name"'

export_collection \
  "$OUTPUT_DIR/repositories" \
  "$OUTPUT_DIR/repositories/_list.json" \
  '."id"' \
  "repository" \
  "--repository-id" \
  '."name"'

export_collection \
  "$OUTPUT_DIR/triggers" \
  "$OUTPUT_DIR/triggers/_list.json" \
  '."id"' \
  "trigger" \
  "--trigger-id" \
  '."display-name"'

export_collection \
  "$OUTPUT_DIR/connections" \
  "$OUTPUT_DIR/connections/_list.json" \
  '."id"' \
  "connection" \
  "--connection-id" \
  '."display-name"'

while IFS= read -r item; do
  pipeline_id="$(jq -r '."id"' <<<"$item")"
  pipeline_name="$(jq -r '."display-name" // "build-pipeline"' <<<"$item")"
  stage_dir="$OUTPUT_DIR/build_pipeline_stages/$(safe_name "$pipeline_name")--$(ocid_suffix "$pipeline_id")"
  mkdir -p "$stage_dir"

  write_json "$stage_dir/_list.json" \
    devops build-pipeline-stage list \
    --build-pipeline-id "$pipeline_id" \
    --all

  while IFS= read -r stage_item; do
    stage_id="$(jq -r '."id"' <<<"$stage_item")"
    stage_name="$(jq -r '."display-name" // "build-stage"' <<<"$stage_item")"
    write_json "$stage_dir/$(safe_name "$stage_name")--$(ocid_suffix "$stage_id").json" \
      devops build-pipeline-stage get \
      --stage-id "$stage_id"
  done < <(iter_data_items "$stage_dir/_list.json")

  if [[ "$INCLUDE_RUNS" == "true" ]]; then
    run_dir="$OUTPUT_DIR/build_runs/$(safe_name "$pipeline_name")--$(ocid_suffix "$pipeline_id")"
    mkdir -p "$run_dir"
    write_json "$run_dir/_list.json" \
      devops build-run list \
      --build-pipeline-id "$pipeline_id" \
      --limit "$RUNS_LIMIT"

    while IFS= read -r run_item; do
      run_id="$(jq -r '."id"' <<<"$run_item")"
      run_name="$(jq -r '."display-name" // "build-run"' <<<"$run_item")"
      write_json "$run_dir/$(safe_name "$run_name")--$(ocid_suffix "$run_id").json" \
        devops build-run get \
        --build-run-id "$run_id"
    done < <(iter_data_items "$run_dir/_list.json")
  fi
done < <(iter_data_items "$OUTPUT_DIR/build_pipelines/_list.json")

while IFS= read -r item; do
  pipeline_id="$(jq -r '."id"' <<<"$item")"
  pipeline_name="$(jq -r '."display-name" // "deploy-pipeline"' <<<"$item")"
  stage_dir="$OUTPUT_DIR/deploy_stages/$(safe_name "$pipeline_name")--$(ocid_suffix "$pipeline_id")"
  mkdir -p "$stage_dir"

  write_json "$stage_dir/_list.json" \
    devops deploy-stage list \
    --pipeline-id "$pipeline_id" \
    --all

  while IFS= read -r stage_item; do
    stage_id="$(jq -r '."id"' <<<"$stage_item")"
    stage_name="$(jq -r '."display-name" // "deploy-stage"' <<<"$stage_item")"
    write_json "$stage_dir/$(safe_name "$stage_name")--$(ocid_suffix "$stage_id").json" \
      devops deploy-stage get \
      --stage-id "$stage_id"
  done < <(iter_data_items "$stage_dir/_list.json")

  if [[ "$INCLUDE_RUNS" == "true" ]]; then
    deployment_dir="$OUTPUT_DIR/deployments/$(safe_name "$pipeline_name")--$(ocid_suffix "$pipeline_id")"
    mkdir -p "$deployment_dir"
    write_json "$deployment_dir/_list.json" \
      devops deployment list \
      --pipeline-id "$pipeline_id" \
      --limit "$RUNS_LIMIT"

    while IFS= read -r deployment_item; do
      deployment_id="$(jq -r '."id"' <<<"$deployment_item")"
      deployment_name="$(jq -r '."display-name" // "deployment"' <<<"$deployment_item")"
      write_json "$deployment_dir/$(safe_name "$deployment_name")--$(ocid_suffix "$deployment_id").json" \
        devops deployment get \
        --deployment-id "$deployment_id"
    done < <(iter_data_items "$deployment_dir/_list.json")
  fi
done < <(iter_data_items "$OUTPUT_DIR/deploy_pipelines/_list.json")

jq -n \
  --arg outputDir "$OUTPUT_DIR" \
  --arg projectId "$PROJECT_ID" \
  --arg compartmentId "$COMPARTMENT_ID" \
  --arg exportedAt "$TIMESTAMP" \
  --argjson buildPipelineCount "$(count_data_items "$OUTPUT_DIR/build_pipelines/_list.json")" \
  --argjson buildStageCount "$(find "$OUTPUT_DIR/build_pipeline_stages" -name '*.json' ! -name '_list.json' | wc -l | tr -d ' ')" \
  --argjson deployPipelineCount "$(count_data_items "$OUTPUT_DIR/deploy_pipelines/_list.json")" \
  --argjson deployStageCount "$(find "$OUTPUT_DIR/deploy_stages" -name '*.json' ! -name '_list.json' | wc -l | tr -d ' ')" \
  --argjson deployArtifactCount "$(count_data_items "$OUTPUT_DIR/deploy_artifacts/_list.json")" \
  --argjson deployEnvironmentCount "$(count_data_items "$OUTPUT_DIR/deploy_environments/_list.json")" \
  --argjson repositoryCount "$(count_data_items "$OUTPUT_DIR/repositories/_list.json")" \
  --argjson triggerCount "$(count_data_items "$OUTPUT_DIR/triggers/_list.json")" \
  --argjson connectionCount "$(count_data_items "$OUTPUT_DIR/connections/_list.json")" \
  '{
    exportedAtUtc: $exportedAt,
    outputDir: $outputDir,
    projectId: $projectId,
    compartmentId: $compartmentId,
    counts: {
      buildPipelines: $buildPipelineCount,
      buildStages: $buildStageCount,
      deployPipelines: $deployPipelineCount,
      deployStages: $deployStageCount,
      deployArtifacts: $deployArtifactCount,
      deployEnvironments: $deployEnvironmentCount,
      repositories: $repositoryCount,
      triggers: $triggerCount,
      connections: $connectionCount
    }
  }' >"$OUTPUT_DIR/manifest.json"

echo "Export concluido em: $OUTPUT_DIR"
echo "Resumo:"
jq '.' "$OUTPUT_DIR/manifest.json"
