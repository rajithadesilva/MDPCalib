#!/usr/bin/env bash

SESSION_NAME="${SESSION_NAME:-mdpcalib_blt}"
HELPER_SCRIPT="/tmp/attach_mdpcalib.sh"
DATA_MOUNT_SOURCE="${DATA_MOUNT_SOURCE:-$HOME/aoc/MDPCalib/data/kitti}"
DATA_MOUNT_TARGET="${DATA_MOUNT_TARGET:-/data}"
CMRNEXT_LAUNCH="${CMRNEXT_LAUNCH:-cmrnext_blt.launch}"
SYNC_LAUNCH="${SYNC_LAUNCH:-pose_synchronizer_fastlo_blt.launch}"
PLAY_BAG_LAUNCH="${PLAY_BAG_LAUNCH:-play_bag_blt.launch}"
ROSBAG_NAME="${ROSBAG_NAME:-april_smaller_bag_0.bag}"
ROSBAG_PATH="${ROSBAG_PATH:-/data/blt/}"
ORB_VOCAB_DELAY_SEC="${ORB_VOCAB_DELAY_SEC:-10}"
ATTACH_TMUX="${ATTACH_TMUX:-true}"
LOG_ROOT="${LOG_ROOT:-$PWD/logs/mdpcalib_blt}"
RUN_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RUN_LOG_DIR="$LOG_ROOT/$RUN_TIMESTAMP"
PUBLISH_GT_FROM_TF="${PUBLISH_GT_FROM_TF:-false}"
GT_SOURCE_FRAME="${GT_SOURCE_FRAME:-os_sensor}"
GT_TARGET_FRAME="${GT_TARGET_FRAME:-front_left_camera_optical_frame}"
GT_TIMEOUT_SEC="${GT_TIMEOUT_SEC:-30}"
# The optimizer expects the camera optical pose expressed in the LiDAR frame.
# These defaults are the front_left_camera_optical_frame pose in os_sensor.
# They are the optical-frame equivalent of the measured near-identity camera
# body pose in the LiDAR frame.
GT_TX="${GT_TX:-0.443}"
GT_TY="${GT_TY:-0.0}"
GT_TZ="${GT_TZ:--0.237}"
GT_QX="${GT_QX:--0.5084265376725761}"
GT_QY="${GT_QY:-0.508426537672576}"
GT_QZ="${GT_QZ:--0.4914289936402579}"
GT_QW="${GT_QW:-0.491428993640258}"
REBUILD_ON_STARTUP="${REBUILD_ON_STARTUP:-false}"

# --- Create helper script that waits for the container & runs role-specific commands ---
cat > "$HELPER_SCRIPT" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

PREFIX="mdpcalib-mdpcalib-run"
ROLE="${1:-shell}"
CMRNEXT_LAUNCH="${CMRNEXT_LAUNCH:-cmrnext_blt.launch}"
SYNC_LAUNCH="${SYNC_LAUNCH:-pose_synchronizer_fastlo_blt.launch}"
PLAY_BAG_LAUNCH="${PLAY_BAG_LAUNCH:-play_bag_blt.launch}"
ROSBAG_NAME="${ROSBAG_NAME:-april_smaller_bag_0.bag}"
ROSBAG_PATH="${ROSBAG_PATH:-/data/blt/}"
ORB_VOCAB_DELAY_SEC="${ORB_VOCAB_DELAY_SEC:-10}"
PUBLISH_GT_FROM_TF="${PUBLISH_GT_FROM_TF:-true}"
GT_SOURCE_FRAME="${GT_SOURCE_FRAME:-os_sensor}"
GT_TARGET_FRAME="${GT_TARGET_FRAME:-front_left_camera_optical_frame}"
GT_TIMEOUT_SEC="${GT_TIMEOUT_SEC:-30}"
GT_TX="${GT_TX:-}"
GT_TY="${GT_TY:-}"
GT_TZ="${GT_TZ:-}"
GT_QX="${GT_QX:-}"
GT_QY="${GT_QY:-}"
GT_QZ="${GT_QZ:-}"
GT_QW="${GT_QW:-}"

echo "[attach_mdpcalib] Role: $ROLE"
echo "[attach_mdpcalib] Looking for container starting with: $PREFIX"

# Wait for container to exist
while true; do
    CONTAINER_NAME=$(docker ps --format '{{.Names}}' | grep "^${PREFIX}" | head -n1 || true)
    if [[ -n "${CONTAINER_NAME:-}" ]]; then
        echo "[attach_mdpcalib] Attaching to: $CONTAINER_NAME"
        break
    fi
    echo "[attach_mdpcalib] Waiting for container..."
    sleep 2
done

# Wait for roscore (process-based, robust)
WAIT_ROSCORE='echo "[attach_mdpcalib] Waiting for roscore (process)..."; \
while ! pgrep -f "[r]oscore" >/dev/null 2>&1; do sleep 2; done; \
echo "[attach_mdpcalib] roscore process found.";'

ROLE_CMD='exec bash'

case "$ROLE" in
    rviz)
        ROLE_CMD="$WAIT_ROSCORE roscd pose_synchronizer 2>/dev/null || cd /root || true; rviz -d rviz/combined.rviz; exec bash"
        ;;
    cmrnext)
        ROLE_CMD="$WAIT_ROSCORE roslaunch cmrnext $CMRNEXT_LAUNCH; exec bash"
        ;;
    optimizer)
        ROLE_CMD="$WAIT_ROSCORE \
echo \"[attach_mdpcalib] Cleaning data/experiments/*\"; \
rm -rf data/experiments/*; \
roslaunch optimization_utils optimizer.launch; \
exec bash"
        ;;
    sync)
        ROLE_CMD="$WAIT_ROSCORE \
echo \"[attach_mdpcalib] Cleaning /data/cache/*\"; \
rm -rf /data/cache/*; \
roslaunch pose_synchronizer $SYNC_LAUNCH; \
exec bash"
        ;;
    play)
        PLAY_ARGS="rosbag:=$ROSBAG_NAME path:=$ROSBAG_PATH publish_gt_from_tf:=$PUBLISH_GT_FROM_TF tf_source_frame:=$GT_SOURCE_FRAME tf_target_frame:=$GT_TARGET_FRAME tf_timeout_sec:=$GT_TIMEOUT_SEC"
        if [[ "$PUBLISH_GT_FROM_TF" != "true" ]]; then
            : "${GT_TX:?Set GT_TX to the BLT camera pose-in-LiDAR translation x value when PUBLISH_GT_FROM_TF=false.}"
            : "${GT_TY:?Set GT_TY to the BLT camera pose-in-LiDAR translation y value when PUBLISH_GT_FROM_TF=false.}"
            : "${GT_TZ:?Set GT_TZ to the BLT camera pose-in-LiDAR translation z value when PUBLISH_GT_FROM_TF=false.}"
            : "${GT_QX:?Set GT_QX to the BLT camera pose-in-LiDAR quaternion x value when PUBLISH_GT_FROM_TF=false.}"
            : "${GT_QY:?Set GT_QY to the BLT camera pose-in-LiDAR quaternion y value when PUBLISH_GT_FROM_TF=false.}"
            : "${GT_QZ:?Set GT_QZ to the BLT camera pose-in-LiDAR quaternion z value when PUBLISH_GT_FROM_TF=false.}"
            : "${GT_QW:?Set GT_QW to the BLT camera pose-in-LiDAR quaternion w value when PUBLISH_GT_FROM_TF=false.}"
            PLAY_ARGS="$PLAY_ARGS gt_tx:=$GT_TX gt_ty:=$GT_TY gt_tz:=$GT_TZ gt_qx:=$GT_QX gt_qy:=$GT_QY gt_qz:=$GT_QZ gt_qw:=$GT_QW"
        fi
        ROLE_CMD="$WAIT_ROSCORE \
echo \"[attach_mdpcalib] Waiting ${ORB_VOCAB_DELAY_SEC}s for ORB vocabulary to load...\"; \
sleep ${ORB_VOCAB_DELAY_SEC}; \
roslaunch pose_synchronizer $PLAY_BAG_LAUNCH $PLAY_ARGS; \
exec bash"
        ;;
esac

# Exec into container with interactive shell (loads ~/.bashrc → ROS env OK)
exec docker exec -it "$CONTAINER_NAME" bash -ic "$ROLE_CMD"
EOF

chmod +x "$HELPER_SCRIPT"
mkdir -p "$RUN_LOG_DIR"

if [[ "$REBUILD_ON_STARTUP" == "true" ]]; then
  ROSCORE_CONTAINER_CMD="cd /root/catkin_ws && echo '[run_mdpcalib_blt] Rebuilding optimization_utils and pose_synchronizer before roscore.' && catkin build optimization_utils pose_synchronizer && roscore; exec bash"
else
  ROSCORE_CONTAINER_CMD="cd /root/catkin_ws && echo '[run_mdpcalib_blt] Skipping startup rebuild.' && roscore; exec bash"
fi

# --- Kill any existing tmux session ---
tmux has-session -t "$SESSION_NAME" 2>/dev/null && tmux kill-session -t "$SESSION_NAME"

# --- Start tmux session ---
tmux new-session -d -s "$SESSION_NAME" -n main

# ---- Build strict 3x2 layout ----

tmux split-window -h -t "$SESSION_NAME":0.0

tmux select-pane -t "$SESSION_NAME":0.0
tmux split-window -v -t "$SESSION_NAME":0.0
tmux select-pane -t "$SESSION_NAME":0.2
tmux split-window -v -t "$SESSION_NAME":0.2

tmux select-pane -t "$SESSION_NAME":0.1
tmux split-window -v -t "$SESSION_NAME":0.1
tmux select-pane -t "$SESSION_NAME":0.4
tmux split-window -v -t "$SESSION_NAME":0.4

# Pane mapping:
# 0: top-left        → roscore
# 1: top-right       → rviz
# 2: middle-left     → cmrnext
# 3: bottom-left     → optimizer (cleans data/experiments)
# 4: middle-right    → synchroniser (cleans /data/cache)
# 5: bottom-right    → play bag (ORB gate)

# ---- Send commands ----

tmux send-keys -t "$SESSION_NAME":0.0 \
  "xhost +local:docker >/dev/null 2>&1 || true; cd /home/rajitha/aoc/MDPCalib && docker compose run -v $DATA_MOUNT_SOURCE:$DATA_MOUNT_TARGET -it mdpcalib bash -ic \"$ROSCORE_CONTAINER_CMD\"" C-m

tmux send-keys -t "$SESSION_NAME":0.1 "CMRNEXT_LAUNCH='$CMRNEXT_LAUNCH' SYNC_LAUNCH='$SYNC_LAUNCH' PLAY_BAG_LAUNCH='$PLAY_BAG_LAUNCH' ROSBAG_NAME='$ROSBAG_NAME' ROSBAG_PATH='$ROSBAG_PATH' PUBLISH_GT_FROM_TF='$PUBLISH_GT_FROM_TF' GT_SOURCE_FRAME='$GT_SOURCE_FRAME' GT_TARGET_FRAME='$GT_TARGET_FRAME' GT_TIMEOUT_SEC='$GT_TIMEOUT_SEC' GT_TX='$GT_TX' GT_TY='$GT_TY' GT_TZ='$GT_TZ' GT_QX='$GT_QX' GT_QY='$GT_QY' GT_QZ='$GT_QZ' GT_QW='$GT_QW' bash '$HELPER_SCRIPT' rviz" C-m
tmux send-keys -t "$SESSION_NAME":0.2 "CMRNEXT_LAUNCH='$CMRNEXT_LAUNCH' SYNC_LAUNCH='$SYNC_LAUNCH' PLAY_BAG_LAUNCH='$PLAY_BAG_LAUNCH' ROSBAG_NAME='$ROSBAG_NAME' ROSBAG_PATH='$ROSBAG_PATH' PUBLISH_GT_FROM_TF='$PUBLISH_GT_FROM_TF' GT_SOURCE_FRAME='$GT_SOURCE_FRAME' GT_TARGET_FRAME='$GT_TARGET_FRAME' GT_TIMEOUT_SEC='$GT_TIMEOUT_SEC' GT_TX='$GT_TX' GT_TY='$GT_TY' GT_TZ='$GT_TZ' GT_QX='$GT_QX' GT_QY='$GT_QY' GT_QZ='$GT_QZ' GT_QW='$GT_QW' bash '$HELPER_SCRIPT' cmrnext" C-m
tmux send-keys -t "$SESSION_NAME":0.3 "CMRNEXT_LAUNCH='$CMRNEXT_LAUNCH' SYNC_LAUNCH='$SYNC_LAUNCH' PLAY_BAG_LAUNCH='$PLAY_BAG_LAUNCH' ROSBAG_NAME='$ROSBAG_NAME' ROSBAG_PATH='$ROSBAG_PATH' PUBLISH_GT_FROM_TF='$PUBLISH_GT_FROM_TF' GT_SOURCE_FRAME='$GT_SOURCE_FRAME' GT_TARGET_FRAME='$GT_TARGET_FRAME' GT_TIMEOUT_SEC='$GT_TIMEOUT_SEC' GT_TX='$GT_TX' GT_TY='$GT_TY' GT_TZ='$GT_TZ' GT_QX='$GT_QX' GT_QY='$GT_QY' GT_QZ='$GT_QZ' GT_QW='$GT_QW' bash '$HELPER_SCRIPT' optimizer" C-m
tmux send-keys -t "$SESSION_NAME":0.4 "CMRNEXT_LAUNCH='$CMRNEXT_LAUNCH' SYNC_LAUNCH='$SYNC_LAUNCH' PLAY_BAG_LAUNCH='$PLAY_BAG_LAUNCH' ROSBAG_NAME='$ROSBAG_NAME' ROSBAG_PATH='$ROSBAG_PATH' PUBLISH_GT_FROM_TF='$PUBLISH_GT_FROM_TF' GT_SOURCE_FRAME='$GT_SOURCE_FRAME' GT_TARGET_FRAME='$GT_TARGET_FRAME' GT_TIMEOUT_SEC='$GT_TIMEOUT_SEC' GT_TX='$GT_TX' GT_TY='$GT_TY' GT_TZ='$GT_TZ' GT_QX='$GT_QX' GT_QY='$GT_QY' GT_QZ='$GT_QZ' GT_QW='$GT_QW' bash '$HELPER_SCRIPT' sync" C-m
tmux send-keys -t "$SESSION_NAME":0.5 "CMRNEXT_LAUNCH='$CMRNEXT_LAUNCH' SYNC_LAUNCH='$SYNC_LAUNCH' PLAY_BAG_LAUNCH='$PLAY_BAG_LAUNCH' ROSBAG_NAME='$ROSBAG_NAME' ROSBAG_PATH='$ROSBAG_PATH' ORB_VOCAB_DELAY_SEC='$ORB_VOCAB_DELAY_SEC' PUBLISH_GT_FROM_TF='$PUBLISH_GT_FROM_TF' GT_SOURCE_FRAME='$GT_SOURCE_FRAME' GT_TARGET_FRAME='$GT_TARGET_FRAME' GT_TIMEOUT_SEC='$GT_TIMEOUT_SEC' GT_TX='$GT_TX' GT_TY='$GT_TY' GT_TZ='$GT_TZ' GT_QX='$GT_QX' GT_QY='$GT_QY' GT_QZ='$GT_QZ' GT_QW='$GT_QW' bash '$HELPER_SCRIPT' play" C-m

tmux pipe-pane -o -t "$SESSION_NAME":0.0 "cat >> '$RUN_LOG_DIR/roscore.log'"
tmux pipe-pane -o -t "$SESSION_NAME":0.1 "cat >> '$RUN_LOG_DIR/rviz.log'"
tmux pipe-pane -o -t "$SESSION_NAME":0.2 "cat >> '$RUN_LOG_DIR/cmrnext.log'"
tmux pipe-pane -o -t "$SESSION_NAME":0.3 "cat >> '$RUN_LOG_DIR/optimizer.log'"
tmux pipe-pane -o -t "$SESSION_NAME":0.4 "cat >> '$RUN_LOG_DIR/sync.log'"
tmux pipe-pane -o -t "$SESSION_NAME":0.5 "cat >> '$RUN_LOG_DIR/play.log'"

echo "[run_mdpcalib_blt] Logs: $RUN_LOG_DIR"

if [[ "$ATTACH_TMUX" == "true" ]]; then
  tmux attach -t "$SESSION_NAME"
else
  echo "[run_mdpcalib_blt] Session '$SESSION_NAME' started without attaching."
fi
