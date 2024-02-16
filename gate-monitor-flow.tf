# Email Templates

resource "aws_ses_template" "tf-gate-monitor-success" {
  name    = "tf-gate-monitor-success"
  subject = "Gate Monitor Check succeeded"
  html    = "<div style=\"font-family:verdana;font-size:12px\">Gate Monitor validation completed successfully<p><ul><li><b>Message ID:</b>{{#if messageId}} {{messageId}} {{else}} Unknown {{/if}}</li></ul></p></div>"
  text    = "Gate Monitor validation completed successfully\n  -Message ID: {{#if messageId}} {{messageId}} {{else}} Unknown {{/if}}"
}

resource "aws_ses_template" "tf-gate-monitor-error" {
  name    = "tf-gate-monitor-error"
  subject = "Gate Monitor Check Error"
  html    = "<div style=\"font-family:verdana;font-size:12px\">Gate Monitor validation completed with an error<p><ul><li><b>Error:</b>{{#if Error}} {{Error}} {{else}} Unknown {{/if}}</li><li><b>Cause:</b>{{#if Cause}} {{Cause}} {{else}} Unknown {{/if}}</li></ul></p></div>"
  text    = "Gate Monitor validation completed with an error\n  -Error: {{#if Error}} {{Error}} {{else}} Unknown {{/if}} \n   -Cause: {{#if Cause}} {{Cause}} {{else}} Unknown {{/if}}"
}

###### Gate Monitor Lambda Function Start ########################
data "aws_iam_policy_document" "tf-gate-monitor-lambda-policy-doc" {
  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject"
    ]

    resources = ["arn:aws:s3:::training-task-bucket/*"]
  }
}

resource "aws_iam_policy" "tf-gate-monitor-lambda-policy" {
  policy = data.aws_iam_policy_document.tf-gate-monitor-lambda-policy-doc.json
}

module "tf-gate-monitor-lambda" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "tf-gate-monitor-lambda"
  runtime       = "java17"
  handler       = "gate.monitor.GateMonitorLambdaHandler"

  create_package = false
  s3_existing_package = {
    bucket = "training-task-bucket"
    key    = "53712e58d0c56dd8b320e37d87c4040d"
  }

  attach_policy = true
  policy        = aws_iam_policy.tf-gate-monitor-lambda-policy.arn

}

###### Gate Monitor Lambda Function End ########################

###### Step Function Start ###########
data "aws_iam_policy_document" "tf-step-function-ses-access" {
  statement {
    effect    = "Allow"
    actions   = ["ses:SendTemplatedEmail"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "tf-step-function-access-policy" {
  policy = data.aws_iam_policy_document.tf-step-function-ses-access.json
}

module "tf-validate-message-workflow-standard" {
  source = "terraform-aws-modules/step-functions/aws"

  name = "tf-validate-message-workflow-standard"
  type = "STANDARD"

  definition = <<EOF
{
  "Comment": "A description of my state machine",
  "StartAt": "Map",
  "States": {
    "Map": {
      "Type": "Map",
      "ItemProcessor": {
        "ProcessorConfig": {
          "Mode": "INLINE"
        },
        "StartAt": "Lambda Invoke",
        "States": {
          "Lambda Invoke": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "OutputPath": "$.Payload",
            "Parameters": {
              "Payload.$": "$",
              "FunctionName": "arn:aws:lambda:eu-central-1:730335318009:function:tf-gate-monitor-lambda:$LATEST"
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException",
                  "Lambda.TooManyRequestsException"
                ],
                "IntervalSeconds": 1,
                "MaxAttempts": 3,
                "BackoffRate": 2
              }
            ],
            "Catch": [
              {
                "ErrorEquals": [
                  "jakarta.validation.ValidationException"
                ],
                "Next": "SendErrorEmail"
              }
            ],
            "Next": "SendSuccessfulEmail"
          },
          "SendSuccessfulEmail": {
            "Type": "Task",
            "Parameters": {
              "Destination": {
                "ToAddresses": [
                  "ralitsa.todorova@dreamix.eu"
                ]
              },
              "Source": "ralitsa.todorova@dreamix.eu",
              "Template": "tf-gate-monitor-success",
              "TemplateData": {
                "messageId.$": "$.messageId"
              }
            },
            "Resource": "arn:aws:states:::aws-sdk:ses:sendTemplatedEmail",
            "End": true
          },
          "SendErrorEmail": {
            "Type": "Task",
            "Parameters": {
              "Destination": {
                "ToAddresses": [
                  "ralitsa.todorova@dreamix.eu"
                ]
              },
              "Source": "ralitsa.todorova@dreamix.eu",
              "Template": "tf-gate-monitor-error",
              "TemplateData": {
                "Error.$": "$.Error",
                "Cause.$": "$.Cause"
              }
            },
            "Resource": "arn:aws:states:::aws-sdk:ses:sendTemplatedEmail",
            "End": true
          }
        }
      },
      "End": true
    }
  }
}
EOF
  #  service_integrations = {
  #    lambda = {
  #      lambda = [module.tf-gate-monitor-lambda.lambda_function_arn]
  #    }
  #  }

  attach_policy = true
  policy        = aws_iam_policy.tf-step-function-access-policy.arn
}

###### Step Function End ############

###### EventBridge Pipe Start ############
data "aws_iam_policy_document" "tf-gate-monitor-ebpipe-assume-policy-doc" {

  statement {
    effect = "Allow"

    principals {
      identifiers = ["pipes.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "tf-gate-monitor-ebpipe-access-policy-doc" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]

    resources = [aws_sqs_queue.tf-gate-monitor-queue.arn]
  }
  statement {
    effect = "Allow"

    actions = [
      "states:StartExecution"
    ]

    resources = [module.tf-validate-message-workflow-standard.state_machine_arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:PutLogEventsBatch",
    ]

    resources = ["arn:aws:logs:*"]

  }
}

resource "aws_iam_policy" "tf-gate-monitor-ebpipe-access-policy" {
  policy = data.aws_iam_policy_document.tf-gate-monitor-ebpipe-access-policy-doc.json
}

resource "aws_iam_role" "tf-gate-monitor-ebpipe-access-role" {
  name                = "tf-gate-monitor-ebpipe-access-role"
  assume_role_policy  = data.aws_iam_policy_document.tf-gate-monitor-ebpipe-assume-policy-doc.json
  managed_policy_arns = [aws_iam_policy.tf-gate-monitor-ebpipe-access-policy.arn]

}

variable "tf-gate-monitor-ebpipe" {
  default = "tf-gate-monitor-ebpipe"
}

resource "aws_cloudwatch_log_group" "tf-gate-monitor-ebpipe-cloudwatch-log-group" {
  name              = "/aws/vendedlogs/pipes/${var.tf-gate-monitor-ebpipe}"
  retention_in_days = 14
}

resource "aws_pipes_pipe" "tf-gate-monitor-ebpipe" {
  name     = "${var.tf-gate-monitor-ebpipe}"
  role_arn = aws_iam_role.tf-gate-monitor-ebpipe-access-role.arn
  source   = aws_sqs_queue.tf-gate-monitor-queue.arn
  target   = module.tf-validate-message-workflow-standard.state_machine_arn

  #
  #  source_parameters {
  #    sqs_queue_parameters {
  #      batch_size                         = 10
  #      maximum_batching_window_in_seconds = 100
  #    }
  #  }
  #
  target_parameters {
    input_template = <<EOF
      {
        "gate": "<$.body.gate>",
        "flight": "<$.body.flight>",
        "messageId": "<$.messageId>"
      }
    EOF
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }
}

###### EventBridge Pipe End ############
