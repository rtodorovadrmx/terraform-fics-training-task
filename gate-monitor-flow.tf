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
  runtime = "java17"
  handler = "gate.monitor.GateMonitorLambdaHandler"

  create_package = false
#  local_existing_package = "C:\\Users\\ralitsa.todorova\\Documents\\projects\\gate-monitor-lambda\\target\\gate-monitor-lambda-1.0-SNAPSHOT.jar"

# if used, set  create_package = true
#  source_path = "C:\\Users\\ralitsa.todorova\\Documents\\projects\\gate-monitor-lambda\\src\\main"

# if used, set  create_package = false
  s3_existing_package = {
    bucket = "training-task-bucket"
    key = "53712e58d0c56dd8b320e37d87c4040d"
  }

  attach_policy = true
  policy = aws_iam_policy.tf-gate-monitor-lambda-policy.arn

}

###### Gate Monitor Lambda Function End ########################

###### Step Function Start ###########
data "aws_iam_policy_document" "tf-step-function-ses-access" {
  statement {
    effect = "Allow"
    actions = ["ses:SendTemplatedEmail"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = ["lambda:InvokeFunction"]
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
  policy = aws_iam_policy.tf-step-function-access-policy.arn
}


###### Step Function End ############


