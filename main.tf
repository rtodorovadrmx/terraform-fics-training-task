#SNS Topic
resource "aws_sns_topic" "tf-fics-sns-topic-fifo" {
  name       = "tf-fics-sns-topic.fifo"
  fifo_topic = true
}

resource "aws_sns_topic_policy" "default" {
  arn    = aws_sns_topic.tf-fics-sns-topic-fifo.arn
  policy = data.aws_iam_policy_document.tf-fics-topic-policy.json
}

data "aws_iam_policy_document" "tf-fics-topic-policy" {
  policy_id = "__default_policy_ID"

  statement {
    actions = ["SNS:Publish",
      "SNS:RemovePermission",
      "SNS:SetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:AddPermission",
    "SNS:Subscribe"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        var.account_id,
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [aws_sns_topic.tf-fics-sns-topic-fifo.arn]

    sid = "__default_statement_ID"
  }
}

#SQS Queue - Gate Monitor
resource "aws_sqs_queue" "tf-gate-monitor-queue" {
  name = "tf-gate-monitor-queue.fifo"
  fifo_queue = true
  content_based_deduplication = false

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.tf-gate-monitor-dlq.arn
    maxReceiveCount= 3
  })
}

data "aws_iam_policy_document" "tf-gate-monitor-queue-access-policy-doc" {

  statement {
    sid    = "First"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.tf-gate-monitor-queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.tf-fics-sns-topic-fifo.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "tf-gate-monitor-queue-access-policy" {
  queue_url = aws_sqs_queue.tf-gate-monitor-queue.id
  policy    = data.aws_iam_policy_document.tf-gate-monitor-queue-access-policy-doc.json
}

#Gate Monitor topic subscription
resource "aws_sns_topic_subscription" "tf-gate-monitor-subscription" {
  endpoint  = aws_sqs_queue.tf-gate-monitor-queue.arn
  protocol  = "sqs"
  topic_arn = aws_sns_topic.tf-fics-sns-topic-fifo.arn
}

#Gate Monitor DLQ
resource "aws_sqs_queue" "tf-gate-monitor-dlq" {
  name = "tf-gate-monitor-dlq.fifo"
  fifo_queue = true
}

resource "aws_sqs_queue_redrive_allow_policy" "tf-gate-monitor-queue-redrive-allow-policy" {
  queue_url = aws_sqs_queue.tf-gate-monitor-dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns = [aws_sqs_queue.tf-gate-monitor-queue.arn]
  })
}

#########
#SQS Queue - Control system
resource "aws_sqs_queue" "tf-control-system-queue" {
  name = "tf-control-system-queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.tf-control-system-dlq.arn
    maxReceiveCount= 3
  })
}

data "aws_iam_policy_document" "tf-control-system-queue-access-policy-doc" {

  statement {
    sid    = "First"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.tf-control-system-queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.tf-fics-sns-topic-fifo.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "tf-control-system-queue-access-policy" {
  queue_url = aws_sqs_queue.tf-control-system-queue.id
  policy    = data.aws_iam_policy_document.tf-control-system-queue-access-policy-doc.json
}

#Control System topic subscription
resource "aws_sns_topic_subscription" "tf-control-system-subscription" {
  endpoint  = aws_sqs_queue.tf-control-system-queue.arn
  protocol  = "sqs"
  topic_arn = aws_sns_topic.tf-fics-sns-topic-fifo.arn
}

#Control System DLQ
resource "aws_sqs_queue" "tf-control-system-dlq" {
  name = "tf-control-system-dlq"
}

resource "aws_sqs_queue_redrive_allow_policy" "tf-control-system-queue-redrive-allow-policy" {
  queue_url = aws_sqs_queue.tf-control-system-dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns = [aws_sqs_queue.tf-control-system-queue.arn]
  })
}

