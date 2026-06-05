#!/usr/bin/env bash
set -euo pipefail

manifest_file="download-manifest.json"
docker_dir="docker-dir"

if [[ -f "$manifest_file" ]]; then
  file_base="$(sed -n 's/.*"FileBase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_file" | head -n 1)"
  output_tar="$(sed -n 's/.*"OutputTar"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_file" | head -n 1)"
  parsed_docker_dir="$(sed -n 's/.*"DockerDir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_file" | head -n 1)"
  if [[ -n "$parsed_docker_dir" ]]; then
    docker_dir="$parsed_docker_dir"
  fi
else
  if [[ ! -d "$docker_dir" ]]; then
    echo "ERROR: download-manifest.json or docker-dir was not found." >&2
    exit 1
  fi
  file_base="$(basename "$PWD")"
  output_tar="${file_base}.tar"
fi

if [[ -z "${file_base:-}" || -z "${output_tar:-}" ]]; then
  echo "ERROR: Could not determine output tar name." >&2
  exit 1
fi

if [[ -e "$output_tar" ]]; then
  echo "ERROR: Output already exists: $output_tar" >&2
  exit 1
fi

if [[ ! -d "$docker_dir" ]]; then
  echo "ERROR: docker-dir was not found: $docker_dir" >&2
  exit 1
fi

blobs_dir="${docker_dir}/blobs/sha256"
if [[ ! -d "$blobs_dir" ]]; then
  echo "ERROR: OCI blobs directory was not found: $blobs_dir" >&2
  exit 1
fi

while IFS= read -r first_part; do
  blob_path="${first_part%.part0001}"
  if [[ -e "$blob_path" ]]; then
    continue
  fi

  part_count=0
  while IFS= read -r part; do
    cat "$part" >> "$blob_path"
    part_count=$((part_count + 1))
  done < <(find "$(dirname "$first_part")" -maxdepth 1 -type f -name "$(basename "$blob_path").part*" | sort)

  if [[ "$part_count" -eq 0 ]]; then
    echo "ERROR: No split parts found for: $blob_path" >&2
    exit 1
  fi
  echo "Restored: $blob_path"
done < <(find "$blobs_dir" -maxdepth 1 -type f -name '*.part0001' | sort)

if [[ ! -f "${docker_dir}/oci-layout" || ! -f "${docker_dir}/index.json" ]]; then
  echo "ERROR: OCI layout files are missing in: $docker_dir" >&2
  exit 1
fi

missing_blob=""
for part in "$blobs_dir"/*.part0001; do
  [[ -e "$part" ]] || continue
  blob_path="${part%.part0001}"
  if [[ ! -f "$blob_path" ]]; then
    missing_blob="$blob_path"
    break
  fi
done

if [[ -n "$missing_blob" ]]; then
  echo "ERROR: split blob was not restored: $missing_blob" >&2
  exit 1
fi

(
  cd "$docker_dir"
  mapfile -d '' archive_files < <(find . -type f ! -name '*.part*' ! -path './manifest.json' -print0 | sort -z)
  if [[ "${#archive_files[@]}" -eq 0 ]]; then
    echo "ERROR: docker-dir has no files to archive." >&2
    exit 1
  fi
  tar -cf "../$output_tar" "${archive_files[@]}"
)

if [[ ! -f "$output_tar" ]]; then
  echo "ERROR: Failed to create output tar: $output_tar" >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
  :
else
  echo "WARN: docker/podman was not found in PATH; load was not tested." >&2
fi

echo "Created: $output_tar"
echo "Load with: docker load -i $output_tar"
