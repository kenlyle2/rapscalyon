#!/usr/bin/env bash
# RapScalYon one-shot deploy: creates (or reuses) a Supabase project, installs core
# and the requested packs. Secrets are read silently and never echoed or written to disk.
#
#   ./deploy.sh --name myapp --org <org-id> --region us-east-1 --packs "subject-business team jobs-tracker"
#   ./deploy.sh --project <existing-ref> --packs "team"        # reuse an existing project
#
# Needs: supabase CLI (logged in, or SUPABASE_ACCESS_TOKEN set), python3.
set -euo pipefail

NAME="" ORG="" REGION="us-east-1" REF="" PACKS="" SIZE="nano"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --org) ORG="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --project) REF="$2"; shift 2;;
    --packs) PACKS="$2"; shift 2;;
    --size) SIZE="$2"; shift 2;;
    -h|--help) sed -n 2,9p "$0"; exit 0;;
    *) echo "unknown option: $1" >&2; exit 2;;
  esac
done

command -v supabase >/dev/null || { echo "supabase CLI not found" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$REF" ]]; then
  [[ -n "$NAME" && -n "$ORG" ]] || { echo "need --name and --org (or --project)" >&2; exit 2; }
  # Database password is generated, shown nowhere, and only needed by the project itself;
  # all our tooling goes through the Management API after `supabase link`.
  DBPASS="$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')"
  OUT="$(supabase projects create "$NAME" --org-id "$ORG" --region "$REGION" --size "$SIZE" \
         --db-password "$DBPASS" -o json)"
  REF="$(printf '%s' "$OUT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
  unset DBPASS
  echo "created project $REF; waiting for it to become healthy..."
  for _ in $(seq 1 60); do
    supabase projects list -o json | python3 -c "
import sys,json
p=[x for x in json.load(sys.stdin) if x['id']=='$REF']
sys.exit(0 if p and p[0].get('status')=='ACTIVE_HEALTHY' else 1)" && break
    sleep 10
  done
fi

python3 "$HERE/tools/rapscalyon.py" --project "$REF" core
for p in $PACKS; do
  python3 "$HERE/tools/rapscalyon.py" --project "$REF" pack add "$HERE/packs/$p"
done
python3 "$HERE/tools/rapscalyon.py" --project "$REF" test
echo "done: https://$REF.supabase.co"
