import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

route53 = boto3.client("route53")
HOSTED_ZONE_ID = os.environ["HOSTED_ZONE_ID"]
RECORD_NAME = os.environ["RECORD_NAME"].rstrip(".") + "."
PRIMARY_DNS = os.environ["PRIMARY_DNS"].rstrip(".") + "."
SECONDARY_DNS = os.environ["SECONDARY_DNS"].rstrip(".") + "."
PRIMARY_SET_ID = os.environ.get("PRIMARY_SET_ID", "primary")
SECONDARY_SET_ID = os.environ.get("SECONDARY_SET_ID", "secondary")
TTL = int(os.environ.get("TTL", "30"))


def set_weights(primary_weight: int, secondary_weight: int) -> dict:
    changes = [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": RECORD_NAME,
                "Type": "CNAME",
                "SetIdentifier": PRIMARY_SET_ID,
                "Weight": primary_weight,
                "TTL": TTL,
                "ResourceRecords": [{"Value": PRIMARY_DNS}],
            },
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": RECORD_NAME,
                "Type": "CNAME",
                "SetIdentifier": SECONDARY_SET_ID,
                "Weight": secondary_weight,
                "TTL": TTL,
                "ResourceRecords": [{"Value": SECONDARY_DNS}],
            },
        },
    ]
    response = route53.change_resource_record_sets(
        HostedZoneId=HOSTED_ZONE_ID,
        ChangeBatch={
            "Comment": f"Automated regional failover: {primary_weight}/{secondary_weight}",
            "Changes": changes,
        },
    )
    return {"change_id": response["ChangeInfo"]["Id"]}


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))
    # SNS-triggered CloudWatch alarm notifications include an SNS Message string.
    message = event.get("Records", [{}])[0].get("Sns", {}).get("Message", "{}")
    try:
        alarm = json.loads(message) if isinstance(message, str) else message
    except json.JSONDecodeError:
        alarm = {}

    state = alarm.get("NewStateValue") or event.get("state")
    if state == "ALARM":
        result = set_weights(0, 100)
        action = "secondary"
    elif state == "OK":
        result = set_weights(100, 0)
        action = "primary"
    else:
        logger.warning("No routing change for state=%s", state)
        return {"statusCode": 202, "body": json.dumps({"action": "none", "state": state})}

    logger.info("Routed traffic preference to %s: %s", action, result)
    return {"statusCode": 200, "body": json.dumps({"action": action, **result})}
