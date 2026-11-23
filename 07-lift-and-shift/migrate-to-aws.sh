#!/usr/bin/env bash
# LIFT-AND-SHIFT (REHOST): on-premises server (= your PC) -> Amazon EC2, in 5 phases (~10 min).
#   KEY=~/.ssh/labsuser.pem ./migrate-to-aws.sh
# Requires infra/1-bootstrap (S3 bucket). The JAR is NOT modified: its SHA-256 is compared on both sides.
source "$(dirname "$0")/../scripts/aws/common.sh"
start_log 07-lift-and-shift
KEY="${KEY:-$HOME/.ssh/labsuser.pem}"; chmod 400 "$KEY" 2>/dev/null
D=07-lift-and-shift/terraform
W="$ROOT/07-lift-and-shift/work"; rm -rf "$W"; mkdir -p "$W/onprem/data" "$W/bundle"
JAR="$ROOT/backend/legacy-registry/target/legacy-registry.jar"
ONPREM=http://localhost:8080
BUCKET=$(tf_out infra/1-bootstrap artifact_bucket)
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -o ConnectTimeout=10"

step "0. Current state: the legacy registry runs ON-PREMISES (java -jar on this machine)"
(cd "$ROOT/backend" && mvn -B -q -pl legacy-registry package -DskipTests) || exit 1
cat > "$W/onprem/app.conf" <<CONF
site=onprem-quito-dc
port=8080
data_file=$W/onprem/data/donors.csv
CONF
java -Dyawar.conf="$W/onprem/app.conf" -jar "$JAR" > "$W/onprem/server.log" 2>&1 &
ONPREM_PID=$!; trap 'kill $ONPREM_PID 2>/dev/null' EXIT
until curl -sf $ONPREM/health >/dev/null; do sleep 1; done
for d in '{"id":"D-001","name":"Ana Quishpe","bloodType":"O+"}' '{"id":"D-002","name":"Luis Andrade","bloodType":"A-"}' '{"id":"D-003","name":"Carla Yepez","bloodType":"B+"}'; do
  curl -s -o /dev/null -w "POST /donors -> %{http_code}\n" -X POST -d "$d" $ONPREM/donors
done
curl -s $ONPREM/about; echo

step "1. ASSESS: inventory of the source server"
SRC_SHA=$(sha256sum "$JAR" | cut -d' ' -f1)
echo "application : yawar-legacy-registry (JAR, Java 21, port 8080, data in a local CSV file)"
echo "jar sha256  : $SRC_SHA"
echo "records     : $(wc -l < "$W/onprem/data/donors.csv")"
echo "strategy    : REHOST (no code change) -> Amazon EC2 + Amazon Corretto 21 + same systemd unit"

step "2. REPLICATE: bundle (binary + config + data + service unit) with checksums, uploaded to S3"
cp "$JAR" "$W/bundle/"; cp "$W/onprem/data/donors.csv" "$W/bundle/"
cp "$ROOT/backend/legacy-registry/conf/yawar-legacy.service" "$W/bundle/"
sed 's/^site=.*/site=aws-us-east-1/' "$ROOT/backend/legacy-registry/conf/app.conf" > "$W/bundle/app.aws.conf"  # only infra values change
(cd "$W/bundle" && sha256sum * | tee SHA256SUMS)
aws s3 cp "$W/bundle" s3://$BUCKET/legacy/ --recursive --only-show-errors && aws s3 ls s3://$BUCKET/legacy/

step "3. LAUNCH the target EC2 instance"
tf $D init -input=false -upgrade >/dev/null
tf $D apply -auto-approve -input=false -var admin_cidr=$(my_ip_cidr) | tail -3
EC2=$(tf_out $D url); EIP=$(tf_out $D public_ip)
echo "waiting for the service on $EC2 (Corretto install + boot)..."
until curl -sf -m 5 $EC2/health >/dev/null; do sleep 10; done

step "4. TEST the migrated instance before cutover"
TGT_SHA=$(curl -s $EC2/about | python3 -c 'import json,sys;print(json.load(sys.stdin)["jarSha256"])')
echo "jar sha256 on-prem : $SRC_SHA"
echo "jar sha256 on EC2  : $TGT_SHA"
[ "$SRC_SHA" = "$TGT_SHA" ] && echo "RESULT: identical binary -> application rehosted WITHOUT code changes"
curl -s $ONPREM/donors > "$W/src.json"; curl -s $EC2/donors > "$W/tgt.json"
diff -q "$W/src.json" "$W/tgt.json" && echo "RESULT: GET /donors identical on source and target"
curl -s $EC2/about; echo

step "5. CUTOVER: freeze writes, final delta sync, switch users to EC2"
curl -s -o /dev/null -w "late write on-prem during the test window -> %{http_code}\n" -X POST \
  -d '{"id":"D-004","name":"Pedro Tituana","bloodType":"O-"}' $ONPREM/donors
kill $ONPREM_PID; trap - EXIT; echo "on-prem service stopped (writes frozen)"
aws s3 cp "$W/onprem/data/donors.csv" s3://$BUCKET/legacy/donors.csv --only-show-errors
$SSH ec2-user@$EIP "sudo aws s3 cp s3://$BUCKET/legacy/donors.csv /var/lib/yawar/donors.csv --only-show-errors && sudo systemctl restart yawar-legacy && systemctl is-active yawar-legacy"
until curl -sf -m 5 $EC2/health >/dev/null; do sleep 2; done
echo "records on EC2 after delta sync: $(curl -s $EC2/donors | grep -o '"id"' | wc -l)  (expected 4)"
curl -s -o /dev/null -w "new write on AWS -> %{http_code}\n" -X POST -d '{"id":"D-005","name":"Maria Chimbo","bloodType":"AB+"}' $EC2/donors
echo "DNS switch: registry.yawar.local -> $EIP  (in production: change the A record / Route 53, low TTL)"
step "systemd status on EC2"
$SSH ec2-user@$EIP "systemctl status yawar-legacy --no-pager | head -5; sudo journalctl -u yawar-legacy --no-pager | tail -3"
