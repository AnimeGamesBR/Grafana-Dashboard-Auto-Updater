# Lambda Function Deployment Guide

This directory contains the AWS Lambda function that orchestrates the Grafana update workflow.

## Files

- **update_grafana_instance.py** - Main Lambda function code
- **requirements.txt** - Python dependencies

---

## Deployment Steps

### Option 1: AWS Console (Easy)

#### 1. Create Deployment Package

```powershell
# Navigate to lambda directory
cd C:\Users\Admin\Desktop\grafana-ec2-auto-updater\lambda

# Install dependencies
pip install -r requirements.txt -t .

# Create ZIP file
Compress-Archive -Path * -DestinationPath function.zip
```

#### 2. Create Lambda Function

1. Go to **AWS Lambda Console**
2. Click **Create function**
3. Settings:
   - Function name: `update-grafana-instance-id`
   - Runtime: **Python 3.11**
   - Architecture: **x86_64**
4. Click **Create function**

#### 3. Upload Code

1. In function page, click **Upload from** → **.zip file**
2. Select `function.zip`
3. Click **Save**

#### 4. Configure Function

**General Configuration:**
- Timeout: **10 minutes 30 seconds**
- Memory: **256 MB**

**Environment Variables:**
| Key | Value |
|-----|-------|
| `JENKINS_URL` | `https://jenkins.example.com` |
| `JENKINS_USER` | `jenkins-service` |
| `JENKINS_API_TOKEN` | Your Jenkins API token |

**Execution Role:**
- Attach policy: `lambda-execution-policy.json` (from `iam/` folder)

#### 5. Add Lambda Layer (for requests library)

1. Click **Add a layer**
2. Layer source: **AWS layers** or **Custom layers**
3. Layer: Search for "requests" or create custom layer

**OR** include requests in deployment package (already done if you followed step 1)

---

### Option 2: AWS CLI (Advanced)

```bash
# Navigate to lambda directory
cd lambda

# Install dependencies
pip install -r requirements.txt -t .

# Create ZIP
zip -r function.zip .

# Create IAM role
aws iam create-role \
  --role-name lambda-grafana-updater-role \
  --assume-role-policy-document file://../iam/lambda-trust-policy.json

# Attach execution policy
aws iam put-role-policy \
  --role-name lambda-grafana-updater-role \
  --policy-name LambdaGrafanaUpdaterPolicy \
  --policy-document file://../iam/lambda-execution-policy.json

# Create Lambda function
aws lambda create-function \
  --function-name update-grafana-instance-id \
  --runtime python3.11 \
  --role arn:aws:iam::ACCOUNT_ID:role/lambda-grafana-updater-role \
  --handler update_grafana_instance.lambda_handler \
  --zip-file fileb://function.zip \
  --timeout 630 \
  --memory-size 256 \
  --environment Variables="{JENKINS_URL=https://jenkins.example.com,JENKINS_USER=jenkins-service,JENKINS_API_TOKEN=YOUR_TOKEN}"
```

---

### Option 3: Terraform

```hcl
resource "aws_lambda_function" "grafana_updater" {
  filename         = "function.zip"
  function_name    = "update-grafana-instance-id"
  role            = aws_iam_role.lambda_role.arn
  handler         = "update_grafana_instance.lambda_handler"
  source_code_hash = filebase64sha256("function.zip")
  runtime         = "python3.11"
  timeout         = 630
  memory_size     = 256

  environment {
    variables = {
      JENKINS_URL       = "https://jenkins.example.com"
      JENKINS_USER      = "jenkins-service"
      JENKINS_API_TOKEN = var.jenkins_api_token
    }
  }
}
```

---

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `JENKINS_URL` | Jenkins server URL (with protocol) | `https://jenkins.example.com` |
| `JENKINS_USER` | Jenkins service account username | `jenkins-service` |
| `JENKINS_API_TOKEN` | Jenkins API token for authentication | `11a91b...` |

---

## IAM Permissions

The Lambda execution role needs these permissions:

### Minimal Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
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

---

## Testing the Function

### Test Event

Create a test event in Lambda console:

```json
{
  "version": "0",
  "id": "12345678-1234-1234-1234-123456789012",
  "detail-type": "AWS API Call via CloudTrail",
  "source": "aws.ec2",
  "account": "123456789012",
  "time": "2026-01-01T12:00:00Z",
  "region": "us-west-2",
  "resources": [],
  "detail": {
    "eventName": "RunInstances",
    "responseElements": {
      "instancesSet": {
        "items": [
          {
            "instanceId": "i-0123456789abcdef0"
          }
        ]
      }
    }
  }
}
```

**Note:** For testing, comment out the `time.sleep(600)` line to avoid waiting 10 minutes.

### Expected Output

```
=============================================================
🚀 Lambda Function Invoked: Grafana Dashboard Updater
=============================================================
🆕 New EC2 Instance Detected: i-0123456789abcdef0
✅ Successfully retrieved tags for instance i-0123456789abcdef0
🏷️  Instance Name Tag: app-server-production
🎯 Matched Jenkins Job: Update Grafana Dashboard - Production
⏳ Waiting 600 seconds for instance to fully initialize...
✅ Wait complete. Proceeding with Jenkins job trigger...
🔄 Triggering Jenkins job: Update Grafana Dashboard - Production
✅ Jenkins job 'Update Grafana Dashboard - Production' triggered successfully!
```

---

## Monitoring

### CloudWatch Logs

View logs:
```bash
aws logs tail /aws/lambda/update-grafana-instance-id --follow
```

### Metrics to Monitor

1. **Invocations** - Number of times Lambda triggered
2. **Duration** - Execution time (should be ~10 minutes)
3. **Errors** - Failed executions
4. **Throttles** - Concurrent execution limits

### CloudWatch Alarms

```bash
# Create alarm for Lambda errors
aws cloudwatch put-metric-alarm \
  --alarm-name lambda-grafana-updater-errors \
  --alarm-description "Alert on Lambda function errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=FunctionName,Value=update-grafana-instance-id
```

---

## Troubleshooting

### Error: "Unable to import module 'update_grafana_instance'"

**Cause:** Dependencies not included in deployment package

**Solution:**
```bash
pip install -r requirements.txt -t .
zip -r function.zip .
```

### Error: "Task timed out after 3.00 seconds"

**Cause:** Default timeout too short

**Solution:**
Set timeout to 10 minutes 30 seconds (630 seconds) in function configuration

### Error: "Unable to connect to Jenkins"

**Cause:** Network connectivity or incorrect URL

**Solution:**
1. Verify `JENKINS_URL` environment variable
2. Check if Lambda needs VPC configuration
3. Verify security groups allow outbound HTTPS

### Error: "401 Unauthorized" from Jenkins

**Cause:** Invalid Jenkins API token

**Solution:**
1. Generate new API token in Jenkins
2. Update Lambda environment variable
3. Ensure token has build permissions

---

## Security Best Practices

✅ **Encrypt environment variables** - Enable encryption helpers  
✅ **Use IAM roles** - Never hardcode AWS credentials  
✅ **Least privilege** - Only grant required permissions  
✅ **VPC isolation** - Deploy in private subnet if Jenkins is private  
✅ **Rotate tokens** - Update Jenkins API token quarterly  

---

## Cost Optimization

### Current Configuration
- Memory: 256 MB
- Duration: ~10 minutes (most is sleep time)
- Executions: ~30/month

**Monthly Cost:** ~$0.01

### Optimization Tips
- Reduce sleep time if instance bootstraps faster
- Use Step Functions for long waits (more cost-effective)
- Set appropriate memory (256 MB is sufficient)

---

## Updating the Function

```bash
# After making code changes
cd lambda
pip install -r requirements.txt -t .
zip -r function.zip .

aws lambda update-function-code \
  --function-name update-grafana-instance-id \
  --zip-file fileb://function.zip
```

---

## Additional Resources

- [AWS Lambda Python Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html)
- [boto3 EC2 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2.html)
- [requests Library Documentation](https://requests.readthedocs.io/)
