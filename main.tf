# SNS Topic
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

# SQS Queue - Gate Monitor
resource "aws_sqs_queue" "tf-gate-monitor-queue" {
  name                        = "tf-gate-monitor-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = false

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.tf-gate-monitor-dlq.arn
    maxReceiveCount     = 3
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

# Gate Monitor topic subscription
resource "aws_sns_topic_subscription" "tf-gate-monitor-subscription" {
  endpoint  = aws_sqs_queue.tf-gate-monitor-queue.arn
  protocol  = "sqs"
  topic_arn = aws_sns_topic.tf-fics-sns-topic-fifo.arn
}

# Gate Monitor DLQ
resource "aws_sqs_queue" "tf-gate-monitor-dlq" {
  name       = "tf-gate-monitor-dlq.fifo"
  fifo_queue = true
}

resource "aws_sqs_queue_redrive_allow_policy" "tf-gate-monitor-queue-redrive-allow-policy" {
  queue_url = aws_sqs_queue.tf-gate-monitor-dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.tf-gate-monitor-queue.arn]
  })
}

#########
# SQS Queue - Control system
resource "aws_sqs_queue" "tf-control-system-queue" {
  name = "tf-control-system-queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.tf-control-system-dlq.arn
    maxReceiveCount     = 3
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

# Control System topic subscription
resource "aws_sns_topic_subscription" "tf-control-system-subscription" {
  endpoint  = aws_sqs_queue.tf-control-system-queue.arn
  protocol  = "sqs"
  topic_arn = aws_sns_topic.tf-fics-sns-topic-fifo.arn
}

# Control System DLQ
resource "aws_sqs_queue" "tf-control-system-dlq" {
  name = "tf-control-system-dlq"
}

resource "aws_sqs_queue_redrive_allow_policy" "tf-control-system-queue-redrive-allow-policy" {
  queue_url = aws_sqs_queue.tf-control-system-dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.tf-control-system-queue.arn]
  })
}

############# Control System Lambda start #####################
data "aws_iam_policy_document" "tf-lambda-assume-role" {
  statement {
    effect = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "tf-iam-lambda" {
  name               = "tf-iam-lambda"
  assume_role_policy = data.aws_iam_policy_document.tf-lambda-assume-role.json
}

resource "aws_lambda_function" "tf-control-system-lambda" {
  function_name = "tf-control-system-lambda"
  role          = aws_iam_role.tf-iam-lambda.arn
  handler       = "control.system.ControlSystemLambdaHandler::handleRequest"
  s3_bucket = "training-task-bucket"
  s3_key = "3cd6c96bd8f2487f415aec4e73914361"
  runtime  = "java17"

  depends_on = [
    aws_iam_role_policy_attachment.tf-lambda-logs-cs,
    aws_cloudwatch_log_group.tf-lambda-cloudwatch-log-group-cs,
    aws_iam_role_policy_attachment.tf-lambda-sqs-queue-execution-role-cs,
  ]

}

variable "lambda_function_name" {
  default = "tf-control-system-lambda"
}

resource "aws_cloudwatch_log_group" "tf-lambda-cloudwatch-log-group-cs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "tf-lambda-logging-cs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "tf-lambda-logging-cs" {
  name        = "tf-lambda-logging-cs"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.tf-lambda-logging-cs.json
}

resource "aws_iam_role_policy_attachment" "tf-lambda-logs-cs" {
  role       = aws_iam_role.tf-iam-lambda.name
  policy_arn = aws_iam_policy.tf-lambda-logging-cs.arn
}

data "aws_iam_policy_document" "tf-lambda-sqs-queue-execution-cs" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.tf-control-system-queue.arn]
  }
}

resource "aws_iam_policy" "tf-lambda-sqs-queue-execution-cs" {
  name        = "tf-lambda-sqs-queue-execution-cs"
  path        = "/"
  description = "IAM policy for receiving messages from SQS queue"
  policy      = data.aws_iam_policy_document.tf-lambda-sqs-queue-execution-cs.json
}

resource "aws_iam_role_policy_attachment" "tf-lambda-sqs-queue-execution-role-cs" {
  role      = aws_iam_role.tf-iam-lambda.name
  policy_arn = aws_iam_policy.tf-lambda-sqs-queue-execution-cs.arn
}

resource "aws_lambda_event_source_mapping" "tf-control-system-sqs-to-lambda" {
  event_source_arn = aws_sqs_queue.tf-control-system-queue.arn
  function_name    = aws_lambda_function.tf-control-system-lambda.arn
  batch_size = 10
}

######### Control System Lambda end #############
