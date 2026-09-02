#!/usr/bin/env bash
#
# vscode-node.sh - reserve a CARC compute node and point VS Code at it.
#
#   vscode-node.sh setup              once: install your SSH key on the cluster
#   vscode-node.sh                    start the default session -> VS Code host "discovery1"
#   vscode-node.sh discovery1-2       start a second session    -> VS Code host "discovery1-2"
#   vscode-node.sh status             list sessions, their nodes and time left
#   vscode-node.sh stop [NAME|all]    cancel a session
#
# Every session has a name, which is also the host name you pick in VS Code.
# Anything starting with "-" is passed to sbatch after SBATCH_OPTS, so it
# overrides the defaults:  vscode-node.sh discovery1-gpu --partition=gpu --gres=gpu:1
#
set -euo pipefail

# ---- settings ---------------------------------------------------------------
USC_NetID="ttrojan"
LOGIN_HOST="discovery1.usc.edu"    # discovery2.usc.edu, endeavour.usc.edu, ...
NODE_SUFFIX=".hpc.usc.edu"         # compute nodes resolve as <node>.hpc.usc.edu
SBATCH_OPTS="--partition=main --cpus-per-task=4 --mem=12G --time=24:00:00"
                                   # add --account=<project> if you have several
KEY=""                             # SSH key; blank = id_ed25519, id_rsa or id_ecdsa, whichever exists
# -----------------------------------------------------------------------------

HOST="${LOGIN_HOST%.usc.edu}"      # "discovery1": the default session name
CONF="$HOME/.ssh/$HOST.conf"       # ssh config written by this script
SSH_CONFIG="$HOME/.ssh/config"
PREFIX="vscode-"                   # Slurm job name is $PREFIX plus the session name

for k in id_ed25519 id_rsa id_ecdsa; do
  [[ -z "$KEY" && -f "$HOME/.ssh/$k" && -f "$HOME/.ssh/$k.pub" ]] && KEY="$HOME/.ssh/$k"
done
KEY="${KEY:-$HOME/.ssh/id_ed25519}"   # none found: 'setup' creates this one

usage() { sed -n '3,13p' "$0" | cut -c3-; }

# ---- arguments --------------------------------------------------------------
CMD="start"; NAME=""; EXTRA=""
for arg in "$@"; do
  case "$arg" in
    setup|status|stop) CMD="$arg" ;;
    -h|--help)         usage; exit 0 ;;
    -*)                EXTRA="$EXTRA $arg" ;;
    *)                 NAME="$arg" ;;
  esac
done

login() { ssh -n -o LogLevel=ERROR "$USC_NetID@$LOGIN_HOST" "$@"; }   # -n: never reads stdin

# Progress messages, so you can see which step is slow and where it stopped.
step() { printf '\n[%s/3] %s\n' "$1" "$2"; }
info() { printf '      %s\n' "$1"; }

# Our jobs, one per line: "<session> <jobid> <timeleft> <node>". Node is empty while queued.
sessions() { login "squeue --me -h -o '%j %i %L %N'" | sed -n "s/^$PREFIX//p"; }

# The whole config is rewritten from the jobs that exist right now, so a session
# you stopped does not leave an entry behind.
write_config() {
  {
    echo "# Written by vscode-node.sh - overwritten on every run"
    echo "Host $HOST-login"
    echo "    HostName $LOGIN_HOST"
    echo "    User $USC_NetID"
    echo "    IdentityFile $KEY"
    echo "    ServerAliveInterval 300"
    echo "    ServerAliveCountMax 2"
    sessions | while read -r name id left node; do
      [[ -n "$node" ]] || continue     # still queued, nothing to connect to yet
      echo
      echo "# job $id"
      echo "Host $name"
      echo "    HostName $node$NODE_SUFFIX"
      echo "    User $USC_NetID"
      echo "    ProxyJump $HOST-login"
      echo "    IdentityFile $KEY"
      echo "    ServerAliveInterval 300"
      echo "    ServerAliveCountMax 2"
      echo "    StrictHostKeyChecking no"          # a different node every session
      echo "    UserKnownHostsFile /dev/null"
    done
  } > "$CONF"
  chmod 600 "$CONF"
  info "$CONF"

  if ! grep -qs "^Include $HOST.conf" "$SSH_CONFIG"; then
    { echo "Include $HOST.conf"; echo; cat "$SSH_CONFIG" 2>/dev/null || true; } > "$SSH_CONFIG.tmp"
    mv "$SSH_CONFIG.tmp" "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    info "added 'Include $HOST.conf' to $SSH_CONFIG"
  fi
}

case "$CMD" in
setup)
  if [[ -f "$KEY" ]]; then
    echo "Using the key you already have: $KEY"
  else
    echo "No SSH key found. Creating one:"
    ssh-keygen -t ed25519 -N "" -f "$KEY"
  fi
  echo "Adding $KEY.pub to ~/.ssh/authorized_keys on $LOGIN_HOST..."
  PUB=$(cat "$KEY.pub")
  # Appended to authorized_keys, leaving existing keys alone. Home is shared, so one key covers all nodes.
  login "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
         grep -qxF '$PUB' ~/.ssh/authorized_keys || echo '$PUB' >> ~/.ssh/authorized_keys"
  echo "Done. Now run: $0"
  exit ;;

status)
  LIST=$(sessions)
  if [[ -z "$LIST" ]]; then echo "No sessions running."; exit; fi
  printf '%-18s %-9s %-11s %s\n' SESSION JOB "TIME LEFT" NODE
  while read -r name id left node; do
    printf '%-18s %-9s %-11s %s\n' "$name" "$id" "$left" "${node:-(queued)}"
  done <<<"$LIST"
  exit ;;

stop)
  echo "Checking your sessions on $LOGIN_HOST..."
  LIST=$(sessions)
  if [[ -z "$LIST" ]]; then echo "No sessions running."; exit; fi

  # With one session the name is obvious, so it may be left out. With several,
  # say which one, because stopping the wrong reservation is not undoable.
  if [[ -z "$NAME" ]]; then
    if [[ $(grep -c . <<<"$LIST") -gt 1 ]]; then
      echo "You have more than one session. Name the one to stop, or use 'all':" >&2
      awk '{ print "  '"$0"' stop " $1 }' <<<"$LIST" >&2
      exit 1
    fi
    NAME=$(awk 'NR==1 { print $1 }' <<<"$LIST")
  fi

  FOUND="no"
  while read -r name id left node; do
    [[ "$NAME" == "all" || "$name" == "$NAME" ]] || continue
    FOUND="yes"
    login "scancel $id"
    echo "Cancelled job $id ($name)."
  done <<<"$LIST"
  if [[ "$FOUND" == "no" ]]; then echo "No session named $NAME. Try: $0 status" >&2; exit 1; fi
  write_config
  exit ;;
esac

# ---- start ------------------------------------------------------------------
NAME="${NAME:-$HOST}"
[[ -f "$KEY" ]] || { echo "No SSH key at $KEY. Run '$0 setup' first." >&2; exit 1; }

echo "Checking your sessions on $LOGIN_HOST..."
if sessions | grep -q "^$NAME "; then
  echo "Session $NAME already exists. To start another one, give it a name:" >&2
  echo "  $0 $HOST-2" >&2
  echo "To stop this one:  $0 stop $NAME" >&2
  exit 1
fi

step 1 "Submitting a job to hold a compute node"
ID=$(login "sbatch --parsable --job-name=$PREFIX$NAME --nodes=1 --ntasks=1 \
  --wrap='sleep infinity' $SBATCH_OPTS $EXTRA")
info "job $ID queued with $SBATCH_OPTS$EXTRA"

step 2 "Waiting for Slurm to start the job"
NODE=""
printf '      '
for _ in {1..60}; do               # up to 5 minutes
  printf '.'
  NODE=$(login "squeue -h -j $ID -o %N")
  [[ -n "$NODE" ]] && break
  sleep 5
done
printf '\n'
[[ -n "$NODE" ]] || { echo "      still queued. Check 'squeue --me' on the cluster, then run $0 again."; exit 1; }
info "running on $NODE$NODE_SUFFIX"

step 3 "Writing the SSH configuration"
write_config

echo
echo "Ready. In VS Code: Remote-SSH: Connect to Host... -> $NAME"
echo "Stop when you are done:  $0 stop $NAME"
