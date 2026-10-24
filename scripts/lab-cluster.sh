#!/bin/bash
#
# lab-cluster.sh — launch a lab cluster the way the app's launcher should, then
# check the properties the UI depends on.
#
# This is the verifier, not the product. The app grows a launcher; this script
# starts the same cluster from outside it, so the UI can be pointed at real
# clusters before it is trusted to launch them itself.
#
# What it does, and why:
#
#   * state     every member gets an absolute state dir, lock file and baseline
#               under one private work directory, so members never collide on
#               disk.
#   * ports     nothing is remapped. The alarm self-negotiates: `health` scans
#               upward when its port is taken, and `federation` claims the
#               first free slot in its range. The first member to bind is the
#               leader; followers announce at the root (base_port).
#   * isotopes  `service.name` is rotated per member. That name is what mDNS
#               prints, and the key the app and adhd use to find the port the
#               member actually bound.
#   * agreement `federation.cluster_id` is shared by every member (the sample's
#               own value, or one minted here). Peers do not trust each other
#               by default; the agreement is what mirrors them into each
#               other's isotope list at the peer-certified rung.
#
# Nothing is written to /tmp directly. Work happens in a mktemp directory under
# the per-user $TMPDIR, so a lab run is not world-readable and does not leave a
# predictable path behind.
#
# usage:
#   scripts/lab-cluster.sh [options] [<sample>.yaml]
#
#   --count N        number of member processes (default: 3 for
#                    federation-mesh.yaml, else 1)
#   --checkout DIR   smoke-alarm checkout to read samples from (default:
#                    $SMOKE_ALARM, else ~/projects/personal/smoke-alarm)
#   --root DIR       use DIR as the work directory instead of a fresh mktemp
#   --no-register    do not write cluster.json into the app's Clusters folder
#   --pair-adhd      also launch one headless adhd watching every member, and
#                    print the endpoint to connect the UI to
#   --gherkin DIR    features.binaries[].gherkin_files for the paired adhd
#   --stop SLUG      stop the registered cluster for SLUG and exit
#   --keep           leave the work directory behind (it is not deleted either
#                    way; this only stops the summary from calling it private)
#   --help
#
# Requires: lezz (with ocd-smoke-alarm), curl, python3, dns-sd.
#
set -euo pipefail

PROG=$(basename "$0")
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
APP_SUPPORT="${HOME}/Library/Application Support/LezzSea/Clusters"
LEZZ="${LEZZ:-$HOME/.lezz/bin/lezz}"
[ -x "$LEZZ" ] || LEZZ=$(command -v lezz || true)

SAMPLE="federation-mesh.yaml"
CHECKOUT="${SMOKE_ALARM:-$HOME/projects/personal/smoke-alarm}"
COUNT=""
WORK=""
REGISTER=1
PAIR_ADHD=0
GHERKIN_DIR=""
STOP_SLUG=""

say()  { printf '%s\n' "$*"; }
fail() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --count) COUNT="${2:-}"; shift 2 ;;
    --checkout) CHECKOUT="${2:-}"; shift 2 ;;
    --root) WORK="${2:-}"; shift 2 ;;
    --no-register) REGISTER=0; shift ;;
    --pair-adhd) PAIR_ADHD=1; shift ;;
    --gherkin) GHERKIN_DIR="${2:-}"; shift 2 ;;
    --stop) STOP_SLUG="${2:-}"; shift 2 ;;
    --keep) shift ;;
    --help|-h) sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) fail "unknown option $1" ;;
    *) SAMPLE="$1"; shift ;;
  esac
done

[ -n "$LEZZ" ] || fail "lezz is not installed (looked in ~/.lezz/bin and PATH)"
[ -x "$LEZZ" ] || fail "lezz at $LEZZ is not executable"

sample_path() {
  case "$1" in
    /*) printf '%s' "$1"; return ;;
    *) ;;
  esac
  if [ -f "$1" ]; then
    printf '%s' "$1"
    return
  fi
  case "$1" in
    configs/*) printf '%s' "$CHECKOUT/$1"; return ;;
    *) printf '%s' "$CHECKOUT/configs/samples/$1" ;;
  esac
}

slug_of() {
  local base
  base=$(basename "$1")
  printf '%s' "${base%.yaml}"
}

# ---------------------------------------------------------------- stop

stop_cluster() {
  local slug="$1" pointer="$2"
  [ -f "$pointer" ] || fail "no cluster.json for $slug at $pointer"

  local stopped=0
  while IFS=$'\t' read -r pid_path isotope; do
    [ -n "$pid_path" ] || continue
    if "$LEZZ" run ocd-smoke-alarm ops stop -pid-file "$pid_path" >/dev/null 2>&1; then
      say "stopped $isotope"
      stopped=$((stopped + 1))
    else
      say "not running: $isotope"
    fi
  done < <(python3 - "$pointer" <<'PY'
import json, sys
cluster = json.load(open(sys.argv[1]))
for member in cluster.get("members", []):
    print(f"{member.get('pidPath','')}\t{member.get('isotope','')}")
PY
)

  local adhd_pid
  adhd_pid=$(python3 - "$pointer" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("adhd", {}).get("pidPath", ""))
except Exception:
    print("")
PY
)
  if [ -n "$adhd_pid" ] && [ -f "$adhd_pid" ]; then
    kill "$(cat "$adhd_pid")" 2>/dev/null || true
    say "stopped adhd"
  fi

  rm -f "$pointer"
  say "cluster $slug stopped ($stopped member(s))"
}

if [ -n "$STOP_SLUG" ]; then
  stop_cluster "$STOP_SLUG" "$APP_SUPPORT/$STOP_SLUG/cluster.json"
  exit 0
fi

# ---------------------------------------------------------------- derive
#
# Kept in step with LezzSea/Models/ScenarioConfig.swift. The rules are the
# point, so they are stated once here and pinned by the Swift unit tests: state
# moves, isotope rotates, discovery turns on, agreement is supplied; ports stay
# where the sample put them.

derive() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import os, re, sys

source_path, out_path, instance_dir, slug, index = sys.argv[1:6]
lines = open(source_path, encoding="utf-8").read().splitlines()

section = None
base_name = None
health = None
base_port = None
declared_cluster = None
has_tuner = False
has_federation = False
has_cluster_line = False

def key_of(line):
    m = re.match(r"^\s+([A-Za-z_]+):", line)
    return m.group(1) if m else None

def scalar(line):
    m = re.match(r"^\s+[A-Za-z_]+:\s*(.*)$", line)
    if not m:
        return None
    value = m.group(1).split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    return value or None

for line in lines:
    m = re.match(r"^([A-Za-z_]+):", line)
    if m:
        section = m.group(1)
        has_tuner = has_tuner or section == "tuner"
        has_federation = has_federation or section == "federation"
        continue
    if section == "service" and key_of(line) == "name":
        base_name = scalar(line)
    elif section == "health" and key_of(line) == "listen_addr":
        host, _, port = scalar(line).rpartition(":")
        if port.isdigit() and int(port) != 0 and host in ("", "localhost", "127.0.0.1", "0.0.0.0"):
            health = int(port)
    elif section == "federation":
        if key_of(line) == "base_port":
            value = scalar(line)
            base_port = int(value) if value and value.isdigit() else None
        elif key_of(line) == "cluster_id":
            has_cluster_line = True
            declared_cluster = scalar(line)

if health is None:
    sys.exit("the sample does not declare a health listener")
if base_name is None:
    sys.exit("the sample does not declare service.name")

isotope = f"{base_name}-{slug}-{index}"
agreement = declared_cluster or f"lezzsea-{slug}"

out = []
section = None
seen_runtime = set()
tuner_advertise = False
tuner_type = False
inserted_cluster = False

def tuner_defaults():
    global tuner_advertise, tuner_type
    if not tuner_advertise:
        out.append("  advertise: true")
        tuner_advertise = True
    if not tuner_type:
        out.append('  service_type: "_smoke-alarm._tcp"')
        tuner_type = True

def replace_scalar(line, value):
    indent = line[: len(line) - len(line.lstrip())]
    body = line[len(indent):]
    key, _, rest = body.partition(":")
    comment = ""
    if "#" in rest:
        comment = " " + rest[rest.index("#"):]
    return f"{indent}{key}: {value}{comment}"

for line in lines:
    m = re.match(r"^([A-Za-z_]+):", line)
    if m:
        if section == "tuner" and m.group(1) != "tuner":
            tuner_defaults()
        section = m.group(1)
        out.append(line)
        if section == "federation" and not has_cluster_line:
            out.append("  # Added by lab-cluster.sh: the agreement that makes peers trust each other.")
            out.append(f'  cluster_id: "{agreement}"')
            inserted_cluster = True
        continue

    key = key_of(line)
    if section == "service" and key == "name":
        out.append(replace_scalar(line, f'"{isotope}"'))
        continue
    if section == "runtime" and key in ("state_dir", "lock_file", "baseline_file"):
        seen_runtime.add(key)
        if key == "state_dir":
            value = os.path.join(instance_dir, "state")
        elif key == "lock_file":
            value = os.path.join(instance_dir, "ocd-smoke-alarm.pid")
        else:
            value = os.path.join(instance_dir, "state", "known-good.json")
        out.append(replace_scalar(line, f'"{value}"'))
        continue
    if section == "tuner" and key == "advertise":
        tuner_advertise = True
        out.append(replace_scalar(line, "true"))
        continue
    if section == "tuner" and key == "service_type":
        tuner_type = True
        out.append(replace_scalar(line, '"_smoke-alarm._tcp"'))
        continue
    if section == "federation" and key == "cluster_id":
        if scalar(line) is None:
            out.append(replace_scalar(line, f'"{agreement}"'))
            continue
    out.append(line)

if section == "tuner":
    tuner_defaults()
if section == "federation" and not has_cluster_line and not inserted_cluster:
    out.append(f'  cluster_id: "{agreement}"')

for key in ("state_dir", "lock_file", "baseline_file"):
    if key not in seen_runtime:
        sys.exit(f"the sample does not declare runtime.{key}")

if not has_tuner:
    out += [
        "",
        "# Added by lab-cluster.sh: every member advertises its own isotope name",
        "# so mDNS can tell the members of a lab cluster apart.",
        "tuner:",
        "  enabled: true",
        "  advertise: true",
        '  service_type: "_smoke-alarm._tcp"',
    ]

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(out) + "\n")

root = str(base_port) if has_federation and base_port is not None else ""
cluster = agreement if has_federation else ""
print("\t".join([isotope, str(health), root, cluster]))
PY
}

# ---------------------------------------------------------------- discover

# The advertised port is authoritative: it is the port the member bound, which
# is not the port its config asked for once another member holds it.
mdns_port() {
  local name="$1" port
  # dns-sd does not exit after resolving, so run it in the background and read
  # its first resolution line.
  local tmp
  tmp=$(mktemp "${WORK}/dns-sd.XXXXXX")
  dns-sd -L "$name" _smoke-alarm._tcp local. > "$tmp" 2>/dev/null &
  local pid=$!
  for _ in $(seq 1 20); do
    if grep -q "can be reached at" "$tmp" 2>/dev/null; then break; fi
    sleep 0.1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  port=$(sed -n 's/.*can be reached at .*:\([0-9][0-9]*\).*/\1/p' "$tmp" | head -1)
  rm -f "$tmp"
  [ -n "$port" ] && printf '%s' "$port"
}

SCANNED=0

port_names() {
  local isotope="$1" expected_service="$2" port status
  port=$(mdns_port "$isotope" || true)
  if [ -n "$port" ]; then
    if curl -fsS --max-time 2 "http://127.0.0.1:$port/status" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("service",""))' 2>/dev/null \
        | grep -qx "$expected_service"; then
      printf '%s' "$port"
      return 0
    fi
  fi
  # mDNS can be slow to answer on a busy machine. Scan the neighbourhood of the
  # preferred port, but accept a hit only when /status names the isotope: a
  # port held by somebody else is not this member.
  SCANNED=1
  local preferred="$3" candidate
  for candidate in $(seq "$preferred" $((preferred + 20))); do
    if curl -fsS --max-time 1 "http://127.0.0.1:$candidate/status" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("service",""))' 2>/dev/null \
        | grep -qx "$expected_service"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# The advertisement is the designed channel; the scan is the fallback. Report
# which one answered instead of claiming discovery works.
mdns_names() {
  local tmp
  tmp=$(mktemp "${WORK}/dns-sd-browse.XXXXXX")
  dns-sd -B _smoke-alarm._tcp local. > "$tmp" 2>/dev/null &
  local pid=$!
  sleep 3
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  cat "$tmp"
  rm -f "$tmp"
}

verify() {
  python3 - "$@" <<'PY'
import json, sys, time, urllib.request

root_port, count, *pairs = sys.argv[1:]
count = int(count)
expected = set()
ports = {}
for index in range(0, len(pairs), 2):
    isotope, port = pairs[index], pairs[index + 1]
    expected.add(isotope)
    ports[isotope] = int(port)

def get(url):
    with urllib.request.urlopen(url, timeout=3) as response:
        return json.load(response)

def check():
    failures = []
    membership = get(f"http://127.0.0.1:{root_port}/membership")
    records = [membership["self"]] + membership.get("peers", [])
    names = {record.get("service_name") for record in records}
    if len(records) != count:
        failures.append(f"root sees {len(records)} member(s), expected {count}")
    if names != expected:
        failures.append(f"root sees {sorted(names)}, expected {sorted(expected)}")
    agreements = {record.get("cluster_id") for record in records}
    if len(agreements) != 1 or None in agreements:
        failures.append(f"members do not share one agreement: {sorted(map(str, agreements))}")
    if membership["self"].get("role") != "introducer":
        failures.append("the root is not the introducer")

    for isotope, port in sorted(ports.items()):
        listed = get(f"http://127.0.0.1:{port}/isotope/list")
        rungs = {record.get("trust_rung") for record in listed}
        if len(listed) != count:
            failures.append(f"{isotope}: {len(listed)} isotope(s), expected {count}")
        if rungs != {4}:
            failures.append(f"{isotope}: rungs {sorted(rungs)}, expected the peer-certified rung 4")
    return failures, agreements

# Membership is announced on a timer, so a freshly started cluster is briefly
# incomplete. Poll until it agrees, then report the last disagreement.
deadline = time.time() + 25
failures = []
agreements = set()
while time.time() < deadline:
    try:
        failures, agreements = check()
    except Exception as error:
        failures = [f"cluster not answering yet: {error}"]
    if not failures:
        break
    time.sleep(2)

if failures:
    print("FAIL")
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)

print(f"root :{root_port} introducer, {count}/{count} members, one agreement")
print("agreement: " + agreements.pop())
print("isotopes: every member mirrors every other at rung 4")
PY
}

# ---------------------------------------------------------------- contract
#
# cluster.json is the same file the app's launcher writes. Anything that can
# write it can hand the UI a cluster; that is deliberate.

write_cluster_json() {
  local out="$1"
  python3 - "$out" "$SLUG" "$CLUSTER_ID" "$ROOT_PORT" "$COUNT" "$SAMPLE_RESOLVED" "$WORK" "$ADHD_JSON" \
    "${ISOTOPES[@]}" -- "${PREFERRED[@]}" <<'PY'
import datetime, json, os, sys

out, slug, cluster_id, root_port, count, sample, work, adhd_json = sys.argv[1:9]
rest = sys.argv[9:]
split = rest.index("--")
isotopes = rest[:split]
ports = rest[split + 1:]
count = int(count)

cluster = {
    "scenarioID": os.path.basename(sample),
    "name": slug.replace("-", " ").title(),
    "slug": slug,
    "clusterID": cluster_id or None,
    "rootPort": int(root_port) if root_port else None,
    "startedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "members": [],
}
for index in range(count):
    member = os.path.join(work, slug, f"member-{index + 1}")
    cluster["members"].append({
        "index": index + 1,
        "isotope": isotopes[index],
        "preferredHealthPort": int(ports[index]),
        "configPath": os.path.join(member, "config.yaml"),
        "pidPath": os.path.join(member, "ocd-smoke-alarm.pid"),
        "logPath": os.path.join(member, "alarm.log"),
        "stateDir": os.path.join(member, "state"),
    })
cluster["adhd"] = json.loads(adhd_json)

os.makedirs(os.path.dirname(out), exist_ok=True)
tmp = out + ".tmp"
with open(tmp, "w", encoding="utf-8") as handle:
    json.dump(cluster, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp, out)
PY
}

# ---------------------------------------------------------------- launch

[ -n "$COUNT" ] || {
  case "$(basename "$SAMPLE")" in
    federation-mesh.yaml) COUNT=3 ;;
    *) COUNT=1 ;;
  esac
}

if [ -z "$WORK" ]; then
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/lezzsea-lab.XXXXXX")
else
  mkdir -p "$WORK"
fi
chmod 700 "$WORK"

SLUG=$(slug_of "$SAMPLE")
SAMPLE_RESOLVED=$(sample_path "$SAMPLE")
[ -r "$SAMPLE_RESOLVED" ] || fail "cannot read $SAMPLE_RESOLVED"

mkdir -p "$WORK/$SLUG"
say "work: $WORK"
say "sample: $SAMPLE_RESOLVED"
say "cluster: $SLUG ($COUNT member(s))"

ISOTOPES=()
HEALTH_PORTS=()
ROOT_PORT=""
CLUSTER_ID=""
ADHD_JSON="null"
PREFERRED=()

for index in $(seq 1 "$COUNT"); do
  member="$WORK/$SLUG/member-$index"
  mkdir -p "$member/state"

  meta=$(derive "$SAMPLE_RESOLVED" "$member/config.yaml" "$member" "$SLUG" "$index")
  isotope=$(printf '%s' "$meta" | cut -f1)
  health=$(printf '%s' "$meta" | cut -f2)
  root=$(printf '%s' "$meta" | cut -f3)
  agreement=$(printf '%s' "$meta" | cut -f4)

  ISOTOPES+=("$isotope")
  PREFERRED+=("$health")
  [ -n "$root" ] && ROOT_PORT="$root"
  [ -n "$agreement" ] && CLUSTER_ID="$agreement"

  "$LEZZ" run ocd-smoke-alarm serve --config="$member/config.yaml" --mode=headless \
    > "$member/alarm.log" 2>&1 &
  say "  member-$index $isotope (preferred health :$health) pid $!"
  sleep 1
done

mkdir -p "$WORK/$SLUG"
say "waiting for self-negotiation…"

deadline=$(( $(date +%s) + 45 ))
while :; do
  ready=1
  HEALTH_PORTS=()
  for index in $(seq 1 "$COUNT"); do
    isotope="${ISOTOPES[$((index - 1))]}"
    preferred="${PREFERRED[$((index - 1))]}"
    port=$(port_names "$isotope" "$isotope" "$preferred" || true)
    if [ -z "$port" ]; then
      ready=0
      HEALTH_PORTS+=("$preferred")
    else
      HEALTH_PORTS+=("$port")
    fi
  done
  [ "$ready" -eq 1 ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    for index in $(seq 1 "$COUNT"); do
      say "--- member-$index log ---" >&2
      tail -5 "$WORK/$SLUG/member-$index/alarm.log" >&2 || true
    done
    fail "members did not advertise a health port in time"
  fi
  sleep 1
done

for index in $(seq 1 "$COUNT"); do
  say "  ${ISOTOPES[$((index - 1))]} health :${HEALTH_PORTS[$((index - 1))]}"
done

write_cluster_json "$WORK/$SLUG/cluster.json"
if [ "$REGISTER" -eq 1 ]; then
  write_cluster_json "$APP_SUPPORT/$SLUG/cluster.json"
fi

if [ -n "$ROOT_PORT" ]; then
  verify "$ROOT_PORT" "$COUNT" \
    $(for index in $(seq 1 "$COUNT"); do
        printf '%s %s ' "${ISOTOPES[$((index - 1))]}" "${HEALTH_PORTS[$((index - 1))]}"
      done)
  say "federation root: http://127.0.0.1:$ROOT_PORT/membership"
fi

# ---------------------------------------------------------------- adhd

if [ "$PAIR_ADHD" -eq 1 ]; then
  ADHD_PORT=$(
    python3 - <<'PY'
import socket
for port in range(9190, 9290):
    with socket.socket() as probe:
        try:
            probe.bind(("127.0.0.1", port))
        except OSError:
            continue
        print(port)
        break
PY
  )
  [ -n "$ADHD_PORT" ] || fail "no free adhd port in 9190-9289"

  {
    say "mcp_server:"
    say "  enabled: true"
    say "  addr: \"127.0.0.1:$ADHD_PORT\""
    say "smoke_alarm:"
    for index in $(seq 1 "$COUNT"); do
      say "  - name: \"${ISOTOPES[$((index - 1))]}\""
      say "    endpoint: \"http://127.0.0.1:${HEALTH_PORTS[$((index - 1))]}\""
      say "    interval: 5s"
    done
    if [ -n "$GHERKIN_DIR" ]; then
      say "features:"
      say "  binaries:"
      say "    - name: ocd-smoke-alarm"
      say "      endpoint: \"http://127.0.0.1:${HEALTH_PORTS[0]}/status\""
      say "      gherkin_files:"
      say "        - \"$GHERKIN_DIR/*.feature\""
    fi
  } > "$WORK/$SLUG/adhd.yaml"

  ADHD_BIN=$(command -v adhd || true)
  [ -n "$ADHD_BIN" ] || ADHD_BIN="$HOME/.lezz/bin/adhd"
  [ -x "$ADHD_BIN" ] || fail "adhd is not installed"

  "$ADHD_BIN" --headless --config "$WORK/$SLUG/adhd.yaml" \
    > "$WORK/$SLUG/adhd.log" 2>&1 &
  ADHD_PID=$!
  say "$ADHD_PID" > "$WORK/$SLUG/adhd.pid"

  deadline=$(( $(date +%s) + 20 ))
  while :; do
    if curl -fsS --max-time 2 -X POST "http://127.0.0.1:$ADHD_PORT/mcp" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"adhd.status"}' >/dev/null 2>&1; then
      break
    fi
    [ "$(date +%s)" -ge "$deadline" ] && fail "adhd did not answer on :$ADHD_PORT"
    sleep 1
  done

  LIGHT_COUNT=$(
    curl -fsS --max-time 3 -X POST "http://127.0.0.1:$ADHD_PORT/mcp" \
      -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":2,"method":"adhd.lights.list"}' \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("result") or {}; print(len(r.get("lights") or []))' 2>/dev/null || echo 0
  )

  say "adhd: http://127.0.0.1:$ADHD_PORT/mcp ($LIGHT_COUNT light(s))"
  ADHD_JSON=$(python3 - "$WORK/$SLUG/adhd.yaml" "$ADHD_PORT" "$WORK/$SLUG/adhd.pid" <<'PY'
import json, sys
print(json.dumps({
    "endpoint": f"http://127.0.0.1:{sys.argv[2]}/mcp",
    "port": int(sys.argv[2]),
    "configPath": sys.argv[1],
    "pidPath": sys.argv[3],
}))
PY
)
fi

write_cluster_json "$WORK/$SLUG/cluster.json"
if [ "$REGISTER" -eq 1 ]; then
  write_cluster_json "$APP_SUPPORT/$SLUG/cluster.json"
  say "registered: $APP_SUPPORT/$SLUG/cluster.json"
fi

# ---------------------------------------------------------------- summary

say ""
say "cluster ready."
if [ -n "$ROOT_PORT" ]; then
  say "  root      http://127.0.0.1:$ROOT_PORT/membership"
else
  say "  root      none (single member)"
fi
say "  agreement ${CLUSTER_ID:-none}"
for index in $(seq 1 "$COUNT"); do
  say "  member-$index  ${ISOTOPES[$((index - 1))]}  http://127.0.0.1:${HEALTH_PORTS[$((index - 1))]}/status"
done
if [ "$PAIR_ADHD" -eq 1 ]; then
  say "  adhd      http://127.0.0.1:$ADHD_PORT/mcp"
fi
BROWSED=$(mdns_names || true)
FOUND=0
for isotope in "${ISOTOPES[@]}"; do
  case "$BROWSED" in
    *"$isotope"*) FOUND=$((FOUND + 1)) ;;
  esac
done
if [ "$FOUND" -eq "$COUNT" ]; then
  say "  mDNS      $FOUND/$COUNT isotope names advertised"
else
  say "  mDNS      $FOUND/$COUNT isotope names seen (local-network permission?)"
fi
if [ "$SCANNED" -eq 1 ]; then
  say "  ports     resolved by the name-checked loopback scan"
else
  say "  ports     resolved from the mDNS advertisement"
fi

say ""
say "stop with: $PROG --stop $SLUG"
[ "$REGISTER" -eq 1 ] && say "the Scenarios panel shows this cluster while cluster.json exists"
