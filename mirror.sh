#!/usr/bin/env bash
# Копирует текущие версии файлов ВМ с yx.ru.net в релизы этого репозитория.
#
# Для каждого канала спрашивает у бэкенда текущую версию
# (/api/artifacts/<канал>/latest/). Если релиза <канал>-<версия> с файлом ещё
# нет, скачивает файл с /dl/<канал>/<версия>, сверяет sha256 и выкладывает.
# Бэкенд сам находит файл по ссылке
#   https://github.com/<репо>/releases/download/<канал>-<версия>/<файл>
# и делает её основным источником для ВМ (artifacts.tasks.adopt_github_mirrors).
#
# Исходник — v2-alt-backend/artifacts/github-mirror/ в репозитории yx.
set -euo pipefail

API="${YX_API:-https://yx.ru.net}"
CHANNELS="${YX_CHANNELS:-yxman2 moonvanila}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for ch in $CHANNELS; do
  if ! meta="$(curl -fsS --max-time 30 "$API/api/artifacts/$ch/latest/")"; then
    echo "$ch: у канала нет текущей версии или API недоступен — пропускаю"
    continue
  fi
  version="$(jq -r .version <<<"$meta")"
  sha="$(jq -r .sha256 <<<"$meta")"
  file="$(jq -r .filename <<<"$meta")"
  size="$(jq -r .size <<<"$meta")"
  tag="$ch-$version"

  if gh release view "$tag" --json assets --jq '.assets[].name' 2>/dev/null | grep -qxF "$file"; then
    echo "$tag: уже есть"
    continue
  fi

  echo "$tag: качаю $file ($size байт)"
  curl -fsSL --retry 3 --max-time 1800 -o "$work/$file" "$API/dl/$ch/$version"
  (cd "$work" && echo "$sha  $file" | sha256sum -c -)

  {
    echo "Канал \`$ch\`, версия \`$version\`."
    echo
    echo "sha256 \`$sha\`, $size байт. Копия $API/dl/$ch/$version."
    notes="$(jq -r '.notes // ""' <<<"$meta")"
    [ -n "$notes" ] && { echo; echo "$notes"; }
  } >"$work/notes.md"

  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$work/$file" --clobber
  else
    gh release create "$tag" "$work/$file" --title "$ch $version" \
      --notes-file "$work/notes.md" --latest=false
  fi
  rm -f "$work/$file"
  echo "$tag: выложен"
done
