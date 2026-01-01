"""
AWS Lambda Function: Grafana Dashboard Auto-Updater
====================================================

This Lambda function automatically triggers Jenkins jobs to update Grafana dashboards
when new EC2 instances are launched in your environment.

Trigger: AWS EventBridge (CloudTrail RunInstances event)
Purpose: Detect EC2 instance launches and update Grafana with new instance IDs

Author: DevOps Team
Version: 1.0.0
"""

import boto3
import json
import requests
import os
import time

# Initialize AWS clients
ec2 = boto3.client("ec2")

# Constants
TARGET_TAG_KEY = "Name"
DELAY_SECONDS = 600  # 10-minute delay to ensure instance is fully running


def get_instance_tags(instance_id):
    """
    Fetches all tags for a given EC2 instance.
    
    Args:
        instance_id (str): The EC2 instance ID
        
    Returns:
        dict: Dictionary of tag key-value pairs
    """
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        tags = response["Reservations"][0]["Instances"][0].get("Tags", [])
        tag_dict = {tag["Key"]: tag["Value"] for tag in tags}
        print(f"✅ Successfully retrieved tags for instance {instance_id}")
        return tag_dict
    except Exception as e:
        print(f"❌ Error fetching tags for instance {instance_id}: {str(e)}")
        return {}


def trigger_jenkins_job(jenkins_url, jenkins_job_name, jenkins_user, jenkins_api_token):
    """
    Triggers a Jenkins job via REST API.
    
    Args:
        jenkins_url (str): Base URL of Jenkins server
        jenkins_job_name (str): Name of the Jenkins job to trigger
        jenkins_user (str): Jenkins service account username
        jenkins_api_token (str): Jenkins API token for authentication
        
    Returns:
        dict: Response with status code and body
    """
    try:
        # Construct Jenkins job trigger URL
        job_url = f"{jenkins_url}/job/{jenkins_job_name}/build"
        
        print(f"🔄 Triggering Jenkins job: {jenkins_job_name}")
        print(f"📍 URL: {job_url}")
        
        # Send POST request to Jenkins API
        # Note: SSL verification is disabled for internal Jenkins servers
        response = requests.post(
            job_url,
            auth=(jenkins_user, jenkins_api_token),
            verify=False,
            timeout=30
        )
        
        if response.status_code == 201:
            print(f"✅ Jenkins job '{jenkins_job_name}' triggered successfully!")
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": "Jenkins job triggered successfully",
                    "job": jenkins_job_name
                })
            }
        else:
            print(f"❌ Failed to trigger Jenkins job! Status code: {response.status_code}")
            print(f"Response: {response.text}")
            return {
                "statusCode": response.status_code,
                "body": json.dumps({
                    "error": "Failed to trigger Jenkins job",
                    "details": response.text
                })
            }
            
    except Exception as e:
        print(f"🚨 Exception while triggering Jenkins job: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": "Internal server error",
                "details": str(e)
            })
        }


def lambda_handler(event, context):
    """
    Main Lambda handler function.
    
    Workflow:
    1. Parse EventBridge event to extract new EC2 instance ID
    2. Retrieve instance tags
    3. Match instance name to appropriate Jenkins job
    4. Wait 10 minutes for instance to fully initialize
    5. Trigger Jenkins job to update Grafana dashboard
    
    Args:
        event (dict): EventBridge event payload
        context (object): Lambda context object
        
    Returns:
        dict: Response with status code and body
    """
    print("=" * 60)
    print("🚀 Lambda Function Invoked: Grafana Dashboard Updater")
    print("=" * 60)
    print("📥 Received Event:", json.dumps(event, indent=2))
    
    # Extract instance ID from CloudTrail event
    try:
        instance_id = event["detail"]["responseElements"]["instancesSet"]["items"][0]["instanceId"]
        print(f"🆕 New EC2 Instance Detected: {instance_id}")
    except KeyError as e:
        error_msg = "Invalid event structure: Could not extract instance ID"
        print(f"❌ {error_msg}")
        print(f"Missing key: {str(e)}")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": error_msg})
        }
    
    # Retrieve instance tags
    instance_tags = get_instance_tags(instance_id)
    
    # Get instance name from tags
    try:
        instance_name = instance_tags[TARGET_TAG_KEY]
        print(f"🏷️  Instance Name Tag: {instance_name}")
    except KeyError:
        warning_msg = f"Instance {instance_id} does not have a 'Name' tag"
        print(f"⚠️  {warning_msg}")
        return {
            "statusCode": 200,
            "body": json.dumps({"message": warning_msg})
        }
    
    # Define mapping between EC2 instance names and Jenkins jobs
    # This allows automatic job selection based on environment
    instance_to_job_map = {
        "app-server-dev": "Update Grafana Dashboard - Development",
        "app-server-staging": "Update Grafana Dashboard - Staging",
        "app-server-production": "Update Grafana Dashboard and Alerts - Production"
    }
    
    # Check if instance name matches any configured environment
    if instance_name not in instance_to_job_map:
        info_msg = f"No Grafana update configured for instance: {instance_name}"
        print(f"ℹ️  {info_msg}")
        return {
            "statusCode": 200,
            "body": json.dumps({"message": info_msg})
        }
    
    # Get Jenkins job name for this environment
    jenkins_job_name = instance_to_job_map[instance_name]
    print(f"🎯 Matched Jenkins Job: {jenkins_job_name}")
    
    # Load Jenkins configuration from Lambda environment variables
    try:
        jenkins_url = os.environ['JENKINS_URL']
        jenkins_user = os.environ['JENKINS_USER']
        jenkins_api_token = os.environ['JENKINS_API_TOKEN']
    except KeyError as e:
        error_msg = f"Missing required environment variable: {str(e)}"
        print(f"❌ {error_msg}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": error_msg})
        }
    
    # Wait for instance to fully initialize before updating Grafana
    print(f"⏳ Waiting {DELAY_SECONDS} seconds for instance to fully initialize...")
    time.sleep(DELAY_SECONDS)
    print("✅ Wait complete. Proceeding with Jenkins job trigger...")
    
    # Trigger Jenkins job
    return trigger_jenkins_job(jenkins_url, jenkins_job_name, jenkins_user, jenkins_api_token)
