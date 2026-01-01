# Jenkins Job Configuration

This directory contains the Jenkins job script that updates Grafana dashboards and alert rules.

## File

- **update_grafana_dashboard.sh** - Main automation script

## Jenkins Job Setup

### 1. Create New Jenkins Job

1. Jenkins → New Item
2. Name: `Update Grafana Dashboard - Production`
3. Type: **Freestyle project**
4. Click OK

### 2. Configure Source Code Management

**Git Repository:**
- Repository URL: `https://git-codecommit.us-west-2.amazonaws.com/v1/repos/grafana-dashboard-backup`
- Credentials: Add AWS CodeCommit credentials
- Branch: `*/main`

### 3. Configure Build Environment

**Inject Environment Variables:**

Add these bindings:

1. **Git Username and Password**
   - Variable: (default)
   - Credentials: Select CodeCommit credentials

2. **Secret Text**
   - Variable: `GRAFANA_API_KEY`
   - Credentials: Add Grafana API key as secret text

**Add Timestamps:**
- ☑ Add timestamps to the Console Output

### 4. Build Steps

**Execute Shell:**

Copy the entire content from `update_grafana_dashboard.sh` into the command box.

**OR** reference it from repository:

```bash
#!/bin/bash
chmod +x jenkins/update_grafana_dashboard.sh
./jenkins/update_grafana_dashboard.sh
```

### 5. Post-Build Actions

**Git Publisher:**
- ☑ Push Only If Build Succeeds
- ☑ Merge Results

**Editable Email Notification:**
- Recipients: `devops@example.com`
- Subject: `[Grafana] $PROJECT_NAME - Build # $BUILD_NUMBER - $BUILD_STATUS!`
- Content: 
  ```
  Dashboard Update Status: $BUILD_STATUS
  
  Build URL: $BUILD_URL
  Console Output: $BUILD_URL/console
  
  Changes:
  $CHANGES
  ```

### 6. Configure Triggers

This job is triggered by Lambda (not scheduled).

**Optional**: Add "Build Trigger" → "Trigger builds remotely"
- Authentication Token: Use secure token in Lambda

---

## Creating Grafana API Key

### Step 1: Login to Grafana

Go to your Grafana instance: `https://grafana.example.com`

### Step 2: Create API Key

1. Click **Configuration** (gear icon) → **API Keys**
2. Click **New API Key**
3. Settings:
   - Key name: `jenkins-dashboard-updater`
   - Role: **Editor** (required for dashboard updates)
   - Time to live: `Never` or `1 year`
4. Click **Add**
5. **Copy the key immediately** (you can't see it again!)

### Step 3: Add to Jenkins

1. Jenkins → Credentials → System → Global credentials
2. Add Credentials
3. Kind: **Secret text**
4. Secret: (paste Grafana API key)
5. ID: `grafana-api-key`
6. Description: `Grafana API key for dashboard updates`
7. Click OK

---

## Script Configuration Variables

Edit these in the script to match your environment:

```bash
# AWS Configuration
AWS_REGION="us-west-2"                          # Your AWS region
INSTANCE_NAME="app-server-production"           # EC2 instance Name tag

# CodeCommit Repository
CODECOMMIT_REPO="grafana-dashboard-backup"      # Your repo name
BRANCH="main"                                    # Git branch

# Grafana Files
DASHBOARD_JSON="production_server_metrics.json" # Dashboard filename
ALERT_PATTERN="alert_*.json"                    # Alert file pattern

# Grafana Configuration
GRAFANA_URL="https://grafana.example.com"       # Your Grafana URL

# Alert Titles (update to match your alerts)
ALERT_TITLES=(
  "Production Alert - High CPU Usage (Critical)"
  "Production Alert - High Memory Usage (Critical)"
  # Add your alert titles here
)
```

---

## Testing the Job

### Manual Test Run

1. Go to Jenkins job page
2. Click **Build Now**
3. Monitor **Console Output**
4. Expected output:
   ```
   ✅ [Grafana Auto-Updater] Found EC2 instance: i-0abc123
   ✅ [Grafana Auto-Updater] Repository cloned successfully
   ✅ [Grafana Auto-Updater] Dashboard uploaded successfully
   ✅ [Grafana Auto-Updater] Alert created successfully
   ```

### Verify Results

1. **Check Grafana Dashboard**
   - Open dashboard in Grafana
   - Verify panels show latest data
   - Check instance ID in panel queries

2. **Check Alert Rules**
   - Go to Grafana → Alerting → Alert rules
   - Verify alerts are active
   - Check instance ID in alert queries

3. **Check CodeCommit**
   - Go to AWS CodeCommit console
   - Open repository
   - Verify commit with timestamp

---

## Required Jenkins Plugins

Install these plugins:

- **Git Plugin** - For CodeCommit integration
- **Credentials Plugin** - For secrets management
- **Email Extension Plugin** - For email notifications
- **Timestamper Plugin** - For build log timestamps
- **AnsiColor Plugin** (optional) - For colored output

Install via: Jenkins → Manage Jenkins → Manage Plugins

---

## Troubleshooting

### Job Fails: "AWS CLI not found"

**Solution**: Install AWS CLI on Jenkins server

```bash
# On Jenkins server
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Job Fails: "jq: command not found"

**Solution**: Install jq

```bash
# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq

# macOS
brew install jq
```

### Job Fails: "Permission denied" on git push

**Solution**: Check CodeCommit credentials

1. Verify AWS credentials have CodeCommit permissions
2. Test git clone manually:
   ```bash
   git clone https://git-codecommit.us-west-2.amazonaws.com/v1/repos/grafana-dashboard-backup
   ```

### Job Fails: Grafana API returns 401

**Solution**: Check API key

```bash
# Test API key
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  https://grafana.example.com/api/org
```

If returns 401, regenerate API key in Grafana.

---

## Job Execution Time

Expected duration:
- Fetch instance ID: 5 seconds
- Clone repository: 10 seconds
- Delete old alerts: 30 seconds
- Update JSONs: 5 seconds
- Upload to Grafana: 20 seconds
- Push to CodeCommit: 10 seconds

**Total: ~90 seconds**

---

## Multiple Environments

For multiple environments (Dev, Staging, Prod), create separate jobs:

1. **Update Grafana Dashboard - Development**
   - INSTANCE_NAME="app-server-dev"
   - DASHBOARD_JSON="dev_server_metrics.json"

2. **Update Grafana Dashboard - Staging**
   - INSTANCE_NAME="app-server-staging"
   - DASHBOARD_JSON="staging_server_metrics.json"

3. **Update Grafana Dashboard - Production**
   - INSTANCE_NAME="app-server-production"
   - DASHBOARD_JSON="production_server_metrics.json"

Lambda will trigger the appropriate job based on EC2 instance Name tag.

---

## Security Considerations

✅ **Never commit Grafana API keys to Git**  
✅ **Use Jenkins Credentials for all secrets**  
✅ **Rotate API keys every 90 days**  
✅ **Restrict Jenkins job permissions**  
✅ **Use HTTPS for all API calls**  

---

## Monitoring Job Health

### CloudWatch Dashboard

Create a dashboard to monitor:
- Lambda invocations
- Jenkins job success/failure rate
- Grafana API response times
- CodeCommit commit frequency

### Alerts to Configure

1. **Jenkins job failure** → Email to DevOps
2. **Grafana API errors** → Page on-call
3. **CodeCommit push failures** → Slack notification

---

## Additional Resources

- [Jenkins Pipeline Documentation](https://www.jenkins.io/doc/book/pipeline/)
- [Grafana API Documentation](https://grafana.com/docs/grafana/latest/developers/http_api/)
- [AWS CodeCommit User Guide](https://docs.aws.amazon.com/codecommit/latest/userguide/)
