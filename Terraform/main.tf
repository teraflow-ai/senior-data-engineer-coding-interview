provider "aws" {
    region = "eu-west-1"
    profile = "aws_account"
}

variable "stack_name" {
    description = "Stack Prefix for resources"
    type        = string
    default     = "tera-project"
}

variable "connection_url" {
    description = "This the JDBC url for the glue connection e.g jdbc:protocol://host:port/databasename"
    type = string
}

variable "jdbc_path" {
    description = "This the db path the crawler must follow to crawler the db tables e.g banking/%"
    type = string
}

variable "DBUsername" {
    description = "This is the username of the database in the jdbc connection"
    type = string
}

variable "DBPassword" {
    description = "This is the password for the database in the jdbc connection"
    type = string
    sensitive = true
}

variable "AvailabilityZone" {
    description = "The AZ of the Cluster housing the data"
    type = string
}

variable "SubnetId" {
    description = "The subnet Id of the db instance"
    type = string
}

variable "SecurityGroupIds" {
    description = "The security group ids associated with the Cluster"
    type = list
    default = ["ids"]
}

variable "SupportEmail" {
    description = "This is the support email in the event of a job failure"
    type = string
    default = "data-support@mybigbank.co.za"
}
##Glue Catalog

resource "aws_glue_catalog_database" "glue_database" {
    catalog_id = data.aws_caller_identity.current.account_id
    name = "${var.stack_name}-db"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "glue_role" {
    name = "${var.stack_name}-glue-role"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "glue.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
    ]
}

resource "aws_s3_bucket" "extract_bucket" {
    bucket = "${var.stack_name}-aurora-monthly-extract"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "extract_bucket" {
    bucket = aws_s3_bucket.extract_bucket.id

    rule {
        apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
        }
    }
    
}

##GlueCrawler

resource "aws_glue_connection" "glue_connection" {
    name = "${var.stack_name}-connection"
    connection_type = "JDBC"
    connection_properties = {
    JDBC_CONNECTION_URL = "${var.connection_url}"
    PASSWORD            = "${var.DBPassword}"
    USERNAME            = "${var.DBUsername}"
    }
    physical_connection_requirements {
    availability_zone      = "${var.AvailabilityZone}"
    security_group_id_list = "${var.SecurityGroupIds}"
    subnet_id              = "${var.SubnetId}"
    }
}

resource "aws_glue_crawler" "glue_crawler" {
depends_on      = [aws_glue_catalog_database.glue_database, aws_glue_connection.glue_connection]
name            = "${var.stack_name}-crawler"
database_name   = aws_glue_catalog_database.glue_database.name
role            = aws_iam_role.glue_role.arn
schema_change_policy {
    delete_behavior = "DEPRECATE_IN_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
}
jdbc_target {
    connection_name = aws_glue_connection.glue_connection.name
    path            = "${var.jdbc_path}"
    }
}


##Gluejob

resource "aws_glue_job" "glue_job" {
    name        = "${var.stack_name}-bank-job"
    role_arn    = aws_iam_role.glue_role.arn
    command {
        name            = "glueetl"
        python_version  = "3"
        script_location = "s3://${aws_s3_bucket.extract_bucket.bucket}/scripts/etl.py"
    }
    default_arguments = {
        "--data_catalogue"                   = "AwsDataCatalog"
        "--enable-continuous-cloudwatch-log" = "true"
        "--job-bookmark-option"              = "job-bookmark-disable"
        "--output_location"                  = "s3://${aws_s3_bucket.extract_bucket.bucket}/output"
        "--TempDir"                          = "s3://${aws_s3_bucket.extract_bucket.bucket}/temp"
        "--database_name"                    = "${aws_glue_catalog_database.glue_database.name}"
        "--datalake-formats"                 = "delta"
    }
    execution_property {
        max_concurrent_runs = 2
    }
    glue_version = "3.0"
    number_of_workers = 3
    timeout           = 480
    worker_type       = "G.1X"
}

# Sceduling and orchestration

resource "aws_glue_workflow" "etl_workflow" {
    name        = "${var.stack_name}-workflow"
    description = "Workflow that triggers Glue job after crawler run"
    }

resource "aws_glue_trigger" "first_of_month_crawler_trigger" {
    name          = "${var.stack_name}-crawler-first-of-month-trigger"
    type          = "SCHEDULED"
    actions {
        crawler_name = aws_glue_crawler.glue_crawler.name
    }
    schedule      = "cron(0 5 1 * ? *)"
    start_on_creation = true
    workflow_name = aws_glue_workflow.etl_workflow.name
    }

resource "aws_glue_trigger" "gluejob_conditional_trigger" {
    name          = "${var.stack_name}-gluejob-trigger"
    type          = "CONDITIONAL"

    predicate {
        conditions {
        crawler_name = "${aws_glue_crawler.glue_crawler.name}"
        crawl_state    = "SUCCEEDED"
        }
    }

    actions {
        job_name = aws_glue_job.glue_job.name
    }
    start_on_creation = true
    workflow_name = aws_glue_workflow.etl_workflow.name
}

resource "aws_sns_topic" "sns_failure_topic" {
    name = "${var.stack_name}-failure-alert"
    tags = {
        Name = "${var.stack_name}-alert"
    }
}

resource "aws_sns_topic_subscription" "sns_topic_subscription" {
    topic_arn = aws_sns_topic.sns_failure_topic.arn
    protocol = "email"
    endpoint = "${var.SupportEmail}"
}
resource "aws_iam_role" "lambda_glue_role" {
    name = "${var.stack_name}-lambda-role"

    assume_role_policy = <<EOF
    {
    "Version": "2012-10-17",
    "Statement": [
        {
        "Sid": "",
        "Effect": "Allow",
        "Principal": {
            "Service": "lambda.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
        }
    ]
    }
    EOF

    managed_policy_arns = [
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
        "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
        "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
    ]
    }


resource "aws_lambda_function" "sns_failure_alert" {
    filename      = "lambda_function.zip"
    function_name = "${var.stack_name}-sns-glue-crawler-alert"
    role          = aws_iam_role.lambda_glue_role.arn
    handler       = "lambda_function.lambda_handler"
    runtime       = "python3.9"
    timeout       = 60
    description   = "This function will send an sns notification in the event of the ${var.stack_name}-bank-job failure."

    environment {
        variables = {
        SnsTopic = "${aws_sns_topic.sns_failure_topic.arn}",
        GlueJobName = "${aws_glue_job.glue_job.name}"
        }
    }
}

resource "aws_cloudwatch_log_group" "log_group" {
    name              = "/aws/lambda/${var.stack_name}-sns-glue-crawler-alert"
    retention_in_days = 14
    }


data "aws_iam_policy_document" "lambda_logging" {
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

resource "aws_iam_policy" "lambda_logging" {
    name        = "lambda_logging"
    path        = "/"
    description = "IAM policy for logging from a lambda"
    policy      = data.aws_iam_policy_document.lambda_logging.json
    }

resource "aws_iam_role_policy_attachment" "lambda_logs" {
    role       = aws_iam_role.lambda_glue_role.name
    policy_arn = aws_iam_policy.lambda_logging.arn
    }


resource "aws_cloudwatch_event_rule" "glue_job_event_pattern_rule" {
    name        = "${var.stack_name}-gluejob-failure-event"
    description = "Triggers a Lambda to run when the gluejob has failed."

    event_pattern = <<EOF
    {
    "detail": {
        "jobName": [
        "${aws_glue_job.glue_job.name}"
        ],
        "state": [
        "FAILED"
        ]
    },
    "detail-type": [
        "Glue Job State Change"
    ],
    "source": [
        "aws.glue"
    ]
    }
    EOF
    }

resource "aws_cloudwatch_event_target" "sns" {
    rule      = aws_cloudwatch_event_rule.glue_job_event_pattern_rule.name
    target_id = "${var.stack_name}-sns-glue-crawler-alert"
    arn       = aws_lambda_function.sns_failure_alert.arn
}

resource "aws_lambda_permission" "permission_for_glue_crawler_event_to_invoke_lambda" {
    action        = "lambda:InvokeFunction"
    function_name = "${var.stack_name}-sns-glue-crawler-alert"
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.glue_job_event_pattern_rule.arn
    }
