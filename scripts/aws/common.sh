# Shared helpers for the AWS scripts. Source it:  source "$(dirname "$0")/../scripts/aws/common.sh"
set -uo pipefail
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVID="$ROOT/evidence/aws"
mkdir -p "$EVID"

# start_log <name>: everything printed afterwards also goes to evidence/aws/<name>.log
start_log() {
  exec > >(tee "$EVID/$1.log") 2>&1
  echo "=== $(date -u +%FT%TZ)  $1  account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) region=$AWS_REGION ==="
}

step() { echo; echo "### $*"; }

tf() { # tf <dir> <terraform args...>
  local d="$1"; shift
  (cd "$ROOT/$d" && terraform "$@")
}

tf_out() { tf "$1" output -raw "$2"; }

my_ip_cidr() { echo "$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')/32"; }

# prints only the "log" lines of a demo JSON response
demo_lines() { python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(d["log"])); print("SUMMARY", json.dumps({k:v for k,v in d["summary"].items() if not k.startswith("latency")}))'; }

need() { command -v "$1" >/dev/null || { echo "missing tool: $1"; exit 1; }; }
