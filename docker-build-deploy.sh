#!/usr/bin/env bash
#
# docker-build-deploy.sh
#
# Faz o build (e opcionalmente o push) das imagens Docker do AVideo Platform
# diretamente do notebook, sem depender do GitHub Actions.
#
# Uso:
#   ./docker-build-deploy.sh [avideo|mariadb|all] [opcoes]
#
# Opcoes:
#   --push                   Faz login no DockerHub e envia a imagem apos o build
#   --tag <tag>               Define a tag da imagem (padrao: avideo:1 / avideo-mariadb:1)
#   --platform <lista>         Plataformas para build multi-arch via buildx (ex: linux/amd64,linux/arm64)
#   -h, --help                 Mostra esta ajuda
#
# Variaveis de ambiente (necessarias apenas com --push):
#   DOCKERHUB_USERNAME         Usuario do DockerHub
#   DOCKERHUB_TOKEN            Token/senha de acesso do DockerHub
#
# Exemplos:
#   ./docker-build-deploy.sh avideo
#   ./docker-build-deploy.sh mariadb --tag meuuser/avideo-mariadb:latest --push
#   DOCKERHUB_USERNAME=meuuser DOCKERHUB_TOKEN=xxxx ./docker-build-deploy.sh all --push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET="${1:-}"
if [[ "$TARGET" == --* || "$TARGET" == "-h" ]]; then
  TARGET=""
elif [[ -n "$TARGET" ]]; then
  shift
fi

PUSH="false"
TAG=""
PLATFORM=""

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH="true"
      shift
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opcao desconhecida: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Erro: informe qual imagem construir (avideo, mariadb ou all)." >&2
  usage
  exit 1
fi

build_image() {
  local dockerfile="$1"
  local default_tag="$2"
  local image_tag="${TAG:-$default_tag}"

  if [[ ! -f "$dockerfile" ]]; then
    echo "Erro: $dockerfile nao encontrado em $SCRIPT_DIR" >&2
    exit 1
  fi

  echo "==> Build: $dockerfile -> $image_tag"

  if [[ -n "$PLATFORM" ]]; then
    docker buildx build \
      --platform "$PLATFORM" \
      -f "$dockerfile" \
      -t "$image_tag" \
      $( [[ "$PUSH" == "true" ]] && echo "--push" || echo "--load" ) \
      .
  else
    docker build -f "$dockerfile" -t "$image_tag" .
    if [[ "$PUSH" == "true" ]]; then
      echo "==> Push: $image_tag"
      docker push "$image_tag"
    fi
  fi
}

if [[ "$PUSH" == "true" ]]; then
  if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
    echo "Erro: defina DOCKERHUB_USERNAME e DOCKERHUB_TOKEN para usar --push." >&2
    exit 1
  fi
  echo "==> Login no DockerHub como $DOCKERHUB_USERNAME"
  echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin

  if [[ -n "$PLATFORM" ]]; then
    if ! docker buildx inspect avideo-builder >/dev/null 2>&1; then
      echo "==> Criando builder buildx (avideo-builder)"
      docker buildx create --name avideo-builder --use
    else
      docker buildx use avideo-builder
    fi
  fi
fi

case "$TARGET" in
  avideo)
    build_image "Dockerfile.avideo" "avideo:1"
    ;;
  mariadb)
    build_image "Dockerfile.mariadb" "avideo-mariadb:1"
    ;;
  all)
    build_image "Dockerfile.avideo" "avideo:1"
    build_image "Dockerfile.mariadb" "avideo-mariadb:1"
    ;;
  *)
    echo "Erro: alvo invalido '$TARGET'. Use avideo, mariadb ou all." >&2
    usage
    exit 1
    ;;
esac

echo "==> Concluido."
