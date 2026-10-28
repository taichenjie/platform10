# ---------------------------------------------------------------------------
# Spot interruption capture.
#
# AWS sends two signals before it takes back a Spot instance:
#   - Rebalance recommendation: the instance is at higher risk of being
#     reclaimed. Often arrives minutes to hours early. Not every instance
#     that gets one is actually reclaimed.
#   - Interruption warning: the instance will be reclaimed in 2 minutes.
#
# This file records both signals for the K3s server, and nothing else,
# in a CloudWatch log group. The log group is destroyed with dev, so export
# any events you want to keep before running destroy.
# ---------------------------------------------------------------------------

# Where the events are written.
resource "aws_cloudwatch_log_group" "spot_events" {
  # checkov:skip=CKV_AWS_158:Logs are encrypted at rest with the AWS-owned key. A customer-managed KMS key costs about $1/month for interruption events only.
  # checkov:skip=CKV_AWS_338:Group is destroyed with dev every session. One-year retention adds nothing here.
  name              = "/aws/events/${var.name_prefix}-k3s-spot-interruptions"
  retention_in_days = 30

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-k3s-spot-interruptions"
  })
}

# Matches the two Spot signals, for this instance only.
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.name_prefix}-k3s-spot-interruption"
  description = "Records Spot rebalance recommendations and interruption warnings for the K3s server."

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation", "EC2 Spot Instance Interruption Warning"]
    detail = {
      instance-id = [aws_instance.server.id]
    }
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-k3s-spot-interruption"
  })
}

# Sends every matched event to the log group.
resource "aws_cloudwatch_event_target" "spot_to_logs" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "spot-events-to-logs"
  arn       = aws_cloudwatch_log_group.spot_events.arn
}

# Allows EventBridge to write into this log group, only for events
# coming from the rule above. CloudWatch Logs rejects the writes without it.
data "aws_iam_policy_document" "events_to_logs" {
  statement {
    sid     = "EventBridgeWriteSpotEvents"
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
    }

    resources = ["${aws_cloudwatch_log_group.spot_events.arn}:*"]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.spot_interruption.arn]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "events_to_logs" {
  policy_name     = "${var.name_prefix}-k3s-spot-events-to-logs"
  policy_document = data.aws_iam_policy_document.events_to_logs.json
}
