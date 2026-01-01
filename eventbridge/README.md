# EventBridge Configuration

This directory contains the AWS EventBridge configuration that triggers the automation workflow.

## Files

- **event_pattern.json** - The event pattern that matches EC2 RunInstances events
- **rule_definition.json** - Complete EventBridge rule definition including targets

## Event Pattern Explained

```json
{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["RunInstances"]
  }
}
```

This pattern triggers when:
- **Service**: EC2
- **Event Type**: API call logged by CloudTrail
- **Action**: `RunInstances` (new EC2 instance launched)

## Creating the EventBridge Rule

### Option 1: AWS Console

1. Go to **Amazon EventBridge** → **Rules**
2. Click **Create rule**
3. Enter rule details:
   - Name: `grafana-instance-id-change-detector`
   - Description: `Triggers Lambda function when new EC2 instances are launched`
   - Event bus: `default`
4. Under **Build event pattern**:
   - Event source: `AWS events or EventBridge partner events`
   - Copy the content from `event_pattern.json`
5. Select targets:
   - Target type: `Lambda function`
   - Function: `update-grafana-instance-id`
6. Click **Create**

### Option 2: AWS CLI

```bash
# Create the EventBridge rule
aws events put-rule \
  --name grafana-instance-id-change-detector \
  --description "Triggers Lambda function when new EC2 instances are launched" \
  --event-pattern file://eventbridge/event_pattern.json \
  --state ENABLED \
  --region us-west-2

# Add Lambda as target
aws events put-targets \
  --rule grafana-instance-id-change-detector \
  --targets Id=1,Arn=arn:aws:lambda:REGION:ACCOUNT_ID:function:update-grafana-instance-id \
  --region us-west-2
```

### Option 3: CloudFormation

```yaml
Resources:
  GrafanaInstanceChangeRule:
    Type: AWS::Events::Rule
    Properties:
      Name: grafana-instance-id-change-detector
      Description: Triggers Lambda function when new EC2 instances are launched
      State: ENABLED
      EventPattern:
        source:
          - aws.ec2
        detail-type:
          - AWS API Call via CloudTrail
        detail:
          eventSource:
            - ec2.amazonaws.com
          eventName:
            - RunInstances
      Targets:
        - Id: GrafanaUpdaterLambda
          Arn: !GetAtt UpdateGrafanaInstanceFunction.Arn
```

## Required Permissions

The EventBridge rule needs permission to invoke the Lambda function:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "events.amazonaws.com"
  },
  "Action": "lambda:InvokeFunction",
  "Resource": "arn:aws:lambda:REGION:ACCOUNT_ID:function:update-grafana-instance-id",
  "Condition": {
    "ArnLike": {
      "AWS:SourceArn": "arn:aws:events:REGION:ACCOUNT_ID:rule/grafana-instance-id-change-detector"
    }
  }
}
```

Add this permission to your Lambda function:

```bash
aws lambda add-permission \
  --function-name update-grafana-instance-id \
  --statement-id AllowEventBridgeInvoke \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:REGION:ACCOUNT_ID:rule/grafana-instance-id-change-detector \
  --region us-west-2
```

## Testing the Rule

### Test Event Pattern

You can test the event pattern in the EventBridge console using this sample event:

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
    "eventVersion": "1.05",
    "userIdentity": {
      "type": "AssumedRole"
    },
    "eventTime": "2026-01-01T12:00:00Z",
    "eventSource": "ec2.amazonaws.com",
    "eventName": "RunInstances",
    "awsRegion": "us-west-2",
    "sourceIPAddress": "203.0.113.0",
    "userAgent": "console.ec2.amazonaws.com",
    "requestParameters": {
      "instancesSet": {
        "items": [
          {
            "imageId": "ami-0123456789abcdef0",
            "minCount": 1,
            "maxCount": 1,
            "instanceType": "t3.medium"
          }
        ]
      }
    },
    "responseElements": {
      "instancesSet": {
        "items": [
          {
            "instanceId": "i-0123456789abcdef0",
            "imageId": "ami-0123456789abcdef0",
            "instanceState": {
              "code": 0,
              "name": "pending"
            },
            "instanceType": "t3.medium"
          }
        ]
      }
    }
  }
}
```

## Monitoring

View EventBridge rule metrics:

```bash
# Get rule invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name Invocations \
  --dimensions Name=RuleName,Value=grafana-instance-id-change-detector \
  --start-time 2026-01-01T00:00:00Z \
  --end-time 2026-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum \
  --region us-west-2

# Get failed invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name FailedInvocations \
  --dimensions Name=RuleName,Value=grafana-instance-id-change-detector \
  --start-time 2026-01-01T00:00:00Z \
  --end-time 2026-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum \
  --region us-west-2
```

## Troubleshooting

### Rule Not Triggering

1. **Check CloudTrail is enabled** in your region
2. **Verify the event pattern** matches your EC2 launch events
3. **Check Lambda permissions** - EventBridge must be able to invoke Lambda
4. **Review CloudWatch Logs** for Lambda errors

### Too Many Triggers

If you want to filter specific instances:

```json
{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["RunInstances"],
    "responseElements": {
      "instancesSet": {
        "items": {
          "tagSet": {
            "items": {
              "key": ["Environment"],
              "value": ["production"]
            }
          }
        }
      }
    }
  }
}
```

This filters to only trigger on production instances.

## Cost Considerations

- EventBridge rules are **free** for AWS service events
- CloudTrail may incur charges if not already enabled
- Lambda invocations are charged per request

**Estimated Monthly Cost**: ~$0.01 (assuming 10 EC2 launches/month)
