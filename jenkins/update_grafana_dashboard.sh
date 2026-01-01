#!/bin/bash
###########################################
# Jenkins Job: Grafana Dashboard & Alert Rule Auto-Updater
#
# Purpose:
#   Automatically updates EC2 instance IDs in Grafana dashboards
#   and alert rules when new instances are launched.
#
# Workflow:
#   1. Fetch the latest running EC2 instance ID
#   2. Clone Grafana dashboard repository from CodeCommit
#   3. Delete old provisioned alert rules from Grafana
#   4. Update instance IDs in dashboard JSON
#   5. Update instance IDs in alert rule JSONs
#   6. Upload updated dashboard to Grafana
#   7. Re-create all alert rules in Grafana
#   8. Commit and push changes back to CodeCommit
#
# Author: DevOps Team
# Version: 1.0.0
###########################################

set -e  # Exit on error

# ==================== CONFIGURATION ====================

# AWS Configuration
AWS_REGION="us-west-2"
INSTANCE_NAME="app-server-production"  # EC2 instance tag value

# CodeCommit Repository
CODECOMMIT_REPO="grafana-dashboard-backup"
BRANCH="main"
WORK_DIR="/var/lib/jenkins/workspace"
REPO_DIR="$WORK_DIR/grafana-dashboards"

# Grafana Files
DASHBOARD_JSON="production_server_metrics.json"
ALERT_PATTERN="alert_*.json"

# Grafana API Configuration
GRAFANA_URL="https://grafana.example.com"
GRAFANA_KEY="$GRAFANA_API_KEY"  # Injected from Jenkins credentials

# Logging
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")
LOG_PREFIX="[Grafana Auto-Updater]"

# Alert Rule Titles to Manage
ALERT_TITLES=(
  "Production Alert - High Memory Usage (Critical)"
  "Production Alert - High Memory Usage (Warning)"
  "Production Alert - High CPU Usage (Critical)"
  "Production Alert - High CPU Usage (Warning)"
  "Production Alert - Disk Space Low (Critical)"
  "Production Alert - Application Down"
  "Production Alert - Response Time Degradation"
  "Production Alert - Error Rate Spike"
  "Production Alert - Database Connection Issues"
)

# ==================== FUNCTIONS ====================

log_info() {
    echo "✅ $LOG_PREFIX $1"
}

log_warn() {
    echo "⚠️  $LOG_PREFIX $1"
}

log_error() {
    echo "❌ $LOG_PREFIX $1"
}

log_section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# ==================== MAIN SCRIPT ====================

log_section "Step 1: Fetch Latest EC2 Instance ID"

log_info "Querying AWS for running instance with tag: $INSTANCE_NAME"
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text \
  --region "$AWS_REGION")

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  log_error "No running instance found with tag '$INSTANCE_NAME'"
  exit 1
fi

log_info "Found EC2 instance: $INSTANCE_ID"

# ==================== CLONE REPOSITORY ====================

log_section "Step 2: Clone Grafana Dashboard Repository"

log_info "Cleaning up old repository directory..."
rm -rf "$REPO_DIR"

log_info "Cloning CodeCommit repository: $CODECOMMIT_REPO"
git clone "https://git-codecommit.$AWS_REGION.amazonaws.com/v1/repos/$CODECOMMIT_REPO" "$REPO_DIR" \
  || { log_error "Failed to clone repository"; exit 1; }

cd "$REPO_DIR"
git checkout "$BRANCH" && git pull origin "$BRANCH"
log_info "Repository cloned successfully"

# ==================== DELETE OLD ALERT RULES ====================

log_section "Step 3: Delete Old Alert Rules from Grafana"

log_info "Removing old provisioned alert rules..."

for TITLE in "${ALERT_TITLES[@]}"; do
  # Fetch alert UID from Grafana
  UID=$(curl -sk "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    -H "Authorization: Bearer $GRAFANA_KEY" \
    | jq -r --arg t "$TITLE" '.[] | select(.title==$t) | .uid')
  
  if [[ -n "$UID" && "$UID" != "null" ]]; then
    log_info "Deleting alert: '$TITLE' (UID: $UID)"
    
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
      -X DELETE "${GRAFANA_URL}/api/v1/provisioning/alert-rules/$UID" \
      -H "Authorization: Bearer $GRAFANA_KEY")
    
    if [[ "$HTTP_CODE" == "204" ]]; then
      log_info "  ✓ Deleted successfully"
    else
      log_warn "  ✗ Failed to delete (HTTP $HTTP_CODE)"
    fi
  else
    log_warn "Alert '$TITLE' not found in Grafana, skipping"
  fi
done

# ==================== UPDATE DASHBOARD JSON ====================

log_section "Step 4: Update Dashboard JSON"

if [[ ! -f "$DASHBOARD_JSON" ]]; then
  log_error "Dashboard file not found: $DASHBOARD_JSON"
  exit 1
fi

log_info "Checking dashboard: $DASHBOARD_JSON"

# Extract old instance ID from dashboard
OLD_INSTANCE_ID=$(grep -o '"i-[A-Za-z0-9]*"' "$DASHBOARD_JSON" | tr -d '"' | head -1)

if [[ "$OLD_INSTANCE_ID" != "$INSTANCE_ID" ]]; then
  log_info "Updating dashboard: $OLD_INSTANCE_ID → $INSTANCE_ID"
  
  # Replace all occurrences of old instance ID
  sed -i "s/$OLD_INSTANCE_ID/$INSTANCE_ID/g" "$DASHBOARD_JSON"
  
  # Commit changes
  git add "$DASHBOARD_JSON"
  git commit -m "[$CURRENT_DATE] Dashboard: Updated instance ID from $OLD_INSTANCE_ID to $INSTANCE_ID"
  
  # Upload to Grafana
  log_info "Uploading updated dashboard to Grafana..."
  
  DASHBOARD_UID=$(jq -r '.dashboard.uid' "$DASHBOARD_JSON")
  PAYLOAD=$(jq -n --argjson d "$(jq '.dashboard' "$DASHBOARD_JSON")" \
    '{dashboard: $d, folderId: 0, overwrite: true}')
  
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -H "Authorization: Bearer $GRAFANA_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  
  if [[ "$HTTP_CODE" == "200" ]]; then
    log_info "  ✓ Dashboard uploaded successfully"
  else
    log_error "  ✗ Dashboard upload failed (HTTP $HTTP_CODE)"
  fi
else
  log_info "Dashboard already up to date"
fi

# ==================== UPDATE ALERT RULES ====================

log_section "Step 5: Update Alert Rule JSONs"

log_info "Processing alert rule files..."

for ALERT_FILE in $(ls $ALERT_PATTERN 2>/dev/null); do
  log_info "Updating: $ALERT_FILE"
  
  # Replace instance ID in JSON field
  sed -i -E "s/(\"InstanceId\":\s*\")[^\"]+(\")/\1$INSTANCE_ID\2/g" "$ALERT_FILE"
  
  # Replace instance ID in SQL WHERE clause
  sed -i -E "s/(WHERE InstanceId = ')[^']+(')/\1$INSTANCE_ID\2/g" "$ALERT_FILE"
  
  # Commit changes
  git add "$ALERT_FILE"
  git commit -m "[$CURRENT_DATE] Alert: Updated instance ID to $INSTANCE_ID ($ALERT_FILE)"
done

# ==================== RE-CREATE ALERTS ====================

log_section "Step 6: Re-create Alert Rules in Grafana"

log_info "Uploading updated alert rules to Grafana..."

for ALERT_FILE in $(ls $ALERT_PATTERN 2>/dev/null); do
  ALERT_TITLE=$(jq -r '.title' "$ALERT_FILE")
  
  log_info "Creating alert: $ALERT_TITLE"
  
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -X POST "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    -H "Authorization: Bearer $GRAFANA_KEY" \
    -H "Content-Type: application/json" \
    -d @"$ALERT_FILE")
  
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    log_info "  ✓ Alert created successfully (HTTP $HTTP_CODE)"
  else
    log_error "  ✗ Alert creation failed (HTTP $HTTP_CODE)"
  fi
done

# ==================== PUSH CHANGES ====================

log_section "Step 7: Push Changes to CodeCommit"

log_info "Pushing updates to repository..."
git push origin "$BRANCH"

log_info "Changes pushed successfully"

# ==================== COMPLETION ====================

log_section "✅ AUTOMATION COMPLETE"

echo ""
echo "Summary:"
echo "  • EC2 Instance ID: $INSTANCE_ID"
echo "  • Dashboard Updated: $DASHBOARD_JSON"
echo "  • Alert Rules Updated: $(ls $ALERT_PATTERN 2>/dev/null | wc -l) files"
echo "  • Changes Committed: Yes"
echo "  • Changes Pushed: Yes"
echo "  • Timestamp: $CURRENT_DATE"
echo ""
log_info "Grafana dashboards and alerts are now up to date!"
