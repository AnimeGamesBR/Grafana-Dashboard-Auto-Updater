# 🔄 Grafana Dashboard Auto-Updater

**Automated solution to keep Grafana dashboards updated when EC2 instances change in AWS**

![AWS](https://img.shields.io/badge/AWS-EventBridge%20%7C%20Lambda%20%7C%20EC2-orange?logo=amazon-aws)
![Jenkins](https://img.shields.io/badge/Jenkins-CI%2FCD-red?logo=jenkins)
![Grafana](https://img.shields.io/badge/Grafana-Monitoring-orange?logo=grafana)
![Python](https://img.shields.io/badge/Python-3.11%2B-blue?logo=python)
![Bash](https://img.shields.io/badge/Bash-Script-green?logo=gnu-bash)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 📋 Table of Contents

- [Problem Statement](#-problem-statement)
- [Solution Overview](#-solution-overview)
- [Architecture](#-architecture)
- [Features](#-features)
- [How It Works](#-how-it-works)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Configuration](#%EF%B8%8F-configuration)
- [Deployment](#-deployment)
- [Monitoring](#-monitoring)
- [Troubleshooting](#-troubleshooting)
- [Cost Estimation](#-cost-estimation)
- [Best Practices](#-best-practices)
- [Contributing](#-contributing)
- [License](#-license)

---

## ❗ Problem Statement

### The Challenge

In dynamic cloud environments, EC2 instances are frequently replaced due to:
- Auto Scaling group updates
- Blue-green deployments
- Disaster recovery procedures
- Infrastructure updates
- Elastic Beanstalk deployments

**The Problem:** Grafana dashboards and alert rules use **hard-coded EC2 instance IDs** for:
- CloudWatch metrics queries
- Log aggregation filters
- Alert rule conditions
- Dashboard panels

When instances are replaced, **instance IDs change**, causing:

❌ **Broken Dashboards** - Panels show "No Data"  
❌ **Failed Alerts** - Monitoring gaps in production  
❌ **Manual Work** - DevOps team must manually update 50+ panels  
❌ **Downtime Risk** - Critical issues go undetected  
❌ **Team Overhead** - Multiple deployments/day = constant updates  

### Real-World Impact

**Before Automation:**
- ⏰ **30 minutes** per deployment to manually update dashboards
- 🔴 **Monitoring blind spots** during updates
- 👥 **3 team members** involved in each update
- 📉 **Missed alerts** due to stale instance IDs

---

## ✅ Solution Overview

**Automated, event-driven system** that:

1. ✅ **Detects** EC2 instance launches in real-time (EventBridge)
2. ✅ **Triggers** automated update workflow (Lambda)
3. ✅ **Updates** Grafana dashboards and alert rules (Jenkins)
4. ✅ **Preserves** version history in Git (CodeCommit)
5. ✅ **Notifies** team via email on completion

### Benefits

- 🚀 **Zero manual intervention** - Fully automated
- ⚡ **Real-time updates** - Dashboards sync within minutes
- 🔒 **Git-backed** - All changes version controlled
- 📊 **Multi-environment** - Dev, Staging, Production
- 🔔 **Email notifications** - Team stays informed
- 💰 **Cost-effective** - ~$0.20/month in AWS costs

---

## 🏗️ Architecture

### Component Diagram

```
┌─────────────────┐
│   EC2 Launch    │  ← New instance started (Auto Scaling, EB, manual)
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  EventBridge    │  ← Detects RunInstances event via CloudTrail
│  Rule           │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  Lambda         │  ← Checks instance tags, selects Jenkins job
│  Function       │  ← Waits 10 min for instance initialization
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  Jenkins Job    │  ← Fetches new instance ID
│  (Triggered)    │  ← Updates JSON files in CodeCommit
└────────┬────────┘  ← Uploads to Grafana API
         │
         ├──────────────────────────────────────┐
         │                                      │
         ↓                                      ↓
┌─────────────────┐                  ┌─────────────────┐
│   Grafana API   │                  │   CodeCommit    │
│   (Dashboard &  │                  │   (Backup Repo) │
│   Alerts)       │                  │                 │
└─────────────────┘                  └─────────────────┘
         │
         ↓
┌─────────────────┐
│  Email Alert    │  ← Notification sent to DevOps team
└─────────────────┘
```

### Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Event Detection** | AWS EventBridge | Monitors EC2 RunInstances events |
| **Orchestration** | AWS Lambda (Python) | Triggers automation workflow |
| **Automation** | Jenkins (Bash) | Updates dashboards and alerts |
| **Version Control** | AWS CodeCommit | Stores Grafana JSON files |
| **Monitoring** | Grafana | Displays metrics and alerts |
| **Metrics Source** | AWS CloudWatch | EC2 instance metrics |
| **Notifications** | Email (Jenkins) | Team notifications |

---

## 🚀 Features

### Core Functionality

- ✅ **Automatic Instance ID Detection** - Fetches latest running EC2 instance
- ✅ **Multi-Environment Support** - Dev, Staging, Production isolated
- ✅ **Dashboard Updates** - Replaces instance IDs in all panel queries
- ✅ **Alert Rule Management** - Deletes old alerts, creates new ones
- ✅ **Git Version Control** - Commits all changes to CodeCommit
- ✅ **Grafana API Integration** - Uploads via REST API
- ✅ **Email Notifications** - Sends success/failure alerts

### Advanced Features

- 🔍 **Tag-Based Routing** - Lambda selects correct Jenkins job by EC2 tag
- ⏰ **Smart Delay** - Waits 10 minutes for instance readiness
- 🔄 **Idempotent** - Safe to run multiple times
- 📊 **Comprehensive Logging** - Detailed execution logs
- 🛡️ **Error Handling** - Graceful failures with rollback capability
- 🔐 **Secure** - API keys in Jenkins credentials store

### Supported Update Types

| Type | Updates |
|------|---------|
| **Dashboard Panels** | CloudWatch queries with `InstanceId` dimension |
| **Alert Rules** | Alert condition queries |
| **SQL Filters** | `WHERE InstanceId = 'i-xxx'` clauses |
| **JSON Fields** | `"InstanceId": "i-xxx"` fields |

---

## ⚙️ How It Works

### Step-by-Step Workflow

#### 1. **EC2 Instance Launch** (0 seconds)
```
Auto Scaling Group scales out
→ New EC2 instance "i-0abc123" launched
→ CloudTrail logs "RunInstances" API call
```

#### 2. **EventBridge Detection** (+5 seconds)
```
EventBridge rule matches event pattern
→ Extracts instance ID from CloudTrail event
→ Triggers Lambda function
```

#### 3. **Lambda Execution** (+10 seconds)
```python
# Lambda checks instance tags
tags = ec2.describe_instances(InstanceIds=['i-0abc123'])
instance_name = tags['Name']  # "app-server-production"

# Selects Jenkins job based on environment
if instance_name == "app-server-production":
    jenkins_job = "Update Grafana - Production"

# Waits for instance readiness
time.sleep(600)  # 10 minutes

# Triggers Jenkins job
trigger_jenkins_job(jenkins_job)
```

#### 4. **Jenkins Job Execution** (+12 minutes)
```bash
# Fetch latest instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=app-server-production" \
  --query "Reservations[0].Instances[0].InstanceId")

# Clone Grafana dashboard repo
git clone codecommit::us-west-2://grafana-dashboard-backup

# Delete old alert rules from Grafana
curl -X DELETE https://grafana.example.com/api/v1/provisioning/alert-rules/{uid}

# Update dashboard JSON
sed -i "s/i-old123/$INSTANCE_ID/g" production_dashboard.json

# Update alert JSONs
sed -i "s/i-old123/$INSTANCE_ID/g" alert_*.json

# Upload to Grafana
curl -X POST https://grafana.example.com/api/dashboards/db \
  -d @production_dashboard.json

# Commit & push to CodeCommit
git commit -m "Updated instance ID to $INSTANCE_ID"
git push origin main
```

#### 5. **Grafana Update** (+15 minutes)
```
✅ Dashboard panels show latest metrics
✅ Alert rules monitor new instance
✅ No monitoring gaps
```

#### 6. **Email Notification** (+16 minutes)
```
To: devops@example.com
Subject: [Grafana] Production Dashboard Updated

Dashboard: production_server_metrics
Old Instance: i-old123
New Instance: i-0abc123
Status: Success ✅
```

### Example Scenario

**Before:**
```json
{
  "targets": [{
    "dimensions": {
      "InstanceId": "i-old123"  ← Old instance (terminated)
    }
  }]
}
```

**After Automation:**
```json
{
  "targets": [{
    "dimensions": {
      "InstanceId": "i-0abc123"  ← New instance (running)
    }
  }]
}
```

---

## 📦 Prerequisites

### AWS Requirements

- ✅ **AWS Account** with admin access
- ✅ **CloudTrail enabled** in target region
- ✅ **EC2 instances** with proper `Name` tags
- ✅ **IAM permissions** for Lambda, EventBridge, EC2

### Infrastructure Requirements

- ✅ **Jenkins server** (version 2.300+)
- ✅ **Grafana server** (version 9.0+)
- ✅ **CodeCommit repository** for dashboard backup
- ✅ **Git configured** on Jenkins server

### Credentials & Access

- ✅ **Grafana API key** with Editor role
- ✅ **Jenkins service account** with build permissions
- ✅ **AWS credentials** for CodeCommit and EC2 API
- ✅ **SMTP configured** for email notifications (optional)

### Software Versions

| Software | Minimum Version |
|----------|----------------|
| Python | 3.10+ |
| Bash | 4.0+ |
| Jenkins | 2.300+ |
| Grafana | 9.0+ |
| Git | 2.30+ |
| AWS CLI | 2.0+ |
| jq | 1.6+ |

---

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/grafana-ec2-auto-updater.git
cd grafana-ec2-auto-updater
```

### 2. Deploy Lambda Function

```bash
cd lambda
pip install -r requirements.txt -t .
zip -r function.zip .
aws lambda create-function \
  --function-name update-grafana-instance-id \
  --runtime python3.11 \
  --handler update_grafana_instance.lambda_handler \
  --zip-file fileb://function.zip \
  --role arn:aws:iam::ACCOUNT_ID:role/lambda-execution-role \
  --timeout 630 \
  --environment Variables="{JENKINS_URL=https://jenkins.example.com,JENKINS_USER=jenkins-service,JENKINS_API_TOKEN=YOUR_TOKEN}"
```

### 3. Create EventBridge Rule

```bash
aws events put-rule \
  --name grafana-instance-id-change-detector \
  --event-pattern file://eventbridge/event_pattern.json \
  --state ENABLED

aws events put-targets \
  --rule grafana-instance-id-change-detector \
  --targets Id=1,Arn=arn:aws:lambda:REGION:ACCOUNT_ID:function:update-grafana-instance-id
```

### 4. Configure Jenkins Job

1. Create new Jenkins job: "Update Grafana Dashboard - Production"
2. Add Git repository: Your CodeCommit repo
3. Add credentials:
   - Grafana API key (as secret text)
   - AWS credentials for CodeCommit
4. Copy script from `jenkins/update_grafana_dashboard.sh`
5. Configure email notifications

### 5. Test the Automation

```bash
# Launch a test EC2 instance
aws ec2 run-instances \
  --image-id ami-0123456789abcdef0 \
  --instance-type t3.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=app-server-production}]'

# Monitor Lambda logs
aws logs tail /aws/lambda/update-grafana-instance-id --follow

# Check Jenkins job execution
# Visit: https://jenkins.example.com/job/Update%20Grafana%20Dashboard%20-%20Production/
```

---

## ⚙️ Configuration

### Lambda Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `JENKINS_URL` | Jenkins server URL | `https://jenkins.example.com` |
| `JENKINS_USER` | Service account username | `jenkins-service` |
| `JENKINS_API_TOKEN` | Jenkins API token | `11a91b...` |

### EC2 Instance Tags

Lambda uses the `Name` tag to route to the correct Jenkins job:

| Tag Value | Jenkins Job | Environment |
|-----------|-------------|-------------|
| `app-server-dev` | Update Grafana - Development | Dev |
| `app-server-staging` | Update Grafana - Staging | Staging |
| `app-server-production` | Update Grafana - Production | Production |

### Jenkins Job Configuration

Update these variables in the bash script:

```bash
AWS_REGION="us-west-2"
INSTANCE_NAME="app-server-production"
CODECOMMIT_REPO="grafana-dashboard-backup"
DASHBOARD_JSON="production_server_metrics.json"
GRAFANA_URL="https://grafana.example.com"
```

### Grafana API Key

Create an API key with **Editor** role:

1. Grafana → Configuration → API Keys
2. Add API key
3. Role: **Editor**
4. Copy key to Jenkins credentials

---

## 🔐 Security Best Practices

### IAM Least Privilege

Lambda IAM role should have **only** these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

### Secrets Management

- ✅ Store Grafana API key in **Jenkins Credentials**
- ✅ Store Jenkins API token in **Lambda Environment Variables** (encrypted)
- ✅ Use **IAM roles** instead of access keys where possible
- ✅ Rotate credentials **every 90 days**

### Network Security

- ✅ Jenkins accessible only via **VPN or private network**
- ✅ Grafana uses **HTTPS** with valid certificate
- ✅ Lambda in **VPC** if accessing private resources

---

## 📊 Monitoring

### CloudWatch Logs

**Lambda logs:**
```bash
aws logs tail /aws/lambda/update-grafana-instance-id --follow
```

**Jenkins job logs:**
- Available in Jenkins UI under job execution history

### Metrics to Monitor

| Metric | Threshold | Action |
|--------|-----------|--------|
| Lambda errors | > 0 | Investigate immediately |
| Jenkins job failures | > 1/day | Check credentials |
| Dashboard update time | > 20 min | Optimize script |

### Alerts to Configure

1. **Lambda function errors** → Page on-call engineer
2. **Jenkins job failures** → Email DevOps team
3. **Grafana API errors** → Check API key validity

---

## 🐛 Troubleshooting

### Lambda Not Triggering

**Symptom:** EC2 launched but Lambda doesn't execute

**Diagnosis:**
```bash
# Check EventBridge rule is enabled
aws events describe-rule --name grafana-instance-id-change-detector

# Check Lambda has EventBridge permission
aws lambda get-policy --function-name update-grafana-instance-id

# Verify CloudTrail is logging in the region
aws cloudtrail describe-trails
```

**Solution:**
```bash
# Add Lambda invoke permission
aws lambda add-permission \
  --function-name update-grafana-instance-id \
  --statement-id AllowEventBridge \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:REGION:ACCOUNT_ID:rule/grafana-instance-id-change-detector
```

### Jenkins Job Fails

**Symptom:** Jenkins job triggered but fails

**Common Causes:**

1. **Grafana API key expired**
   ```bash
   # Test API key
   curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
     https://grafana.example.com/api/org
   ```

2. **CodeCommit credentials invalid**
   ```bash
   # Test git clone
   git clone https://git-codecommit.us-west-2.amazonaws.com/v1/repos/grafana-dashboard-backup
   ```

3. **Instance ID not found**
   ```bash
   # Verify instance exists and has correct tag
   aws ec2 describe-instances \
     --filters "Name=tag:Name,Values=app-server-production"
   ```

### Dashboard Not Updating

**Symptom:** Job succeeds but dashboard still shows old data

**Diagnosis:**
```bash
# Check Grafana dashboard UID
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  https://grafana.example.com/api/dashboards/uid/YOUR_DASHBOARD_UID

# Verify instance ID in JSON
cat production_server_metrics.json | grep -o "i-[A-Za-z0-9]*"
```

**Solution:**
- Ensure dashboard JSON has correct UID
- Check Grafana API response for errors
- Manually reload dashboard in Grafana UI

For more troubleshooting, see [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

## 💰 Cost Estimation

### AWS Services

| Service | Usage | Monthly Cost |
|---------|-------|--------------|
| **Lambda** | 30 invocations @ 10min each | $0.01 |
| **EventBridge** | 30 events (free tier) | $0.00 |
| **CloudWatch Logs** | 1 GB storage | $0.50 |
| **CodeCommit** | 1 repo (free tier) | $0.00 |
| **Data Transfer** | Minimal | $0.01 |

**Total Monthly Cost: ~$0.52**

### Time Savings

**Manual Process:**
- 30 min/deployment × 20 deployments/month = **10 hours/month**
- @ $50/hour = **$500/month in labor**

**ROI:** 99.9% cost reduction 🎉

---

## 🎯 Best Practices

### Deployment

1. ✅ **Test in dev environment first**
2. ✅ **Use separate Jenkins jobs per environment**
3. ✅ **Version control all Grafana JSONs**
4. ✅ **Monitor Lambda execution times**
5. ✅ **Set up alerting for failures**

### Maintenance

1. ✅ **Review logs weekly**
2. ✅ **Rotate credentials quarterly**
3. ✅ **Update dependencies monthly**
4. ✅ **Test disaster recovery procedures**

### Scaling

- For multiple regions: Deploy Lambda in each region
- For multiple AWS accounts: Use cross-account IAM roles
- For high-frequency deployments: Reduce Lambda delay

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- AWS for EventBridge and Lambda services
- Grafana team for comprehensive API
- Jenkins community for automation tools
- DevOps team for testing and feedback

---

## 📧 Support

- **Issues**: [GitHub Issues](https://github.com/sajidkhan8530/Grafana-Dashboard-Auto-Updater/issues)
- **Discussions**: [GitHub Discussions](https://github.com/sajidkhan8530/Grafana-Dashboard-Auto-Updater/discussions)
- **Email**: devops@example.com

---

## ⭐ Star This Repository

If this automation saved you time, please give it a star! ⭐

---

**Built with ❤️ by DevOps Engineers, for DevOps Engineers**
