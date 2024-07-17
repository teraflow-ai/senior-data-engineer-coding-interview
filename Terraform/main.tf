# Assume Aurora DB and VPC have already been create
# Choose to put Glue in Aurora DB VPC
# Otherwise need to open peering connection to NAT gateway in public subnet

provider "aws" {
  region = "eu-west-2"
}

# Aurora DB & VPC settings

variable "jdbc_connection" {
  description = "JDBC Connection details to DB"
  type = object({
    url                    = string
    username               = string
    password               = string
    availability_zone      = string
    security_group_id_list = list(string)
    subnet_id              = string
    vpc_id                 = string
    cidr_block             = string
    route_table_id         = string
  })
  default = {
    url                    = "jdbc:postgresql://teraflow-bank-cluster.cluster-c5006gu4eoha.eu-west-2.rds.amazonaws.com:5432/bank_db"
    username               = "postgres"
    password               = "5Y67bg#r#"
    availability_zone      = "eu-west-2a"
    security_group_id_list = ["sg-04da9ab6ffbb71755"]
    subnet_id              = "subnet-07ad29a57f6ef601e"
    vpc_id                 = "vpc-018604568d6878d2f"
    cidr_block             = "172.30.0.0/16"
    route_table_id         = "rtb-0a2c2280722b7e1fd"
  }
}

###################
# Glue Connection #
###################

resource "aws_glue_connection" "teraflow_bank_glue_connection" {
  connection_properties = {
    JDBC_CONNECTION_URL = "${var.jdbc_connection.url}"
    PASSWORD            = "${var.jdbc_connection.password}"
    USERNAME            = "${var.jdbc_connection.username}"
  }

  name = "teraflow_bank_glue_connection"

  physical_connection_requirements {
    availability_zone      = var.jdbc_connection.availability_zone
    security_group_id_list = var.jdbc_connection.security_group_id_list
    subnet_id              = var.jdbc_connection.subnet_id
  }
}

# Create role to run glue

resource "aws_iam_role" "teraflow_bank_glue_iam_role" {
  name               = "teraflow_bank_glue_iam_role"
  assume_role_policy = data.aws_iam_policy_document.teraflow_bank_glue_policy_document_assume_role.json
}

data "aws_iam_policy_document" "teraflow_bank_glue_policy_document_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "teraflow_bank_glue_policy_attachment_rds" {
  role       = aws_iam_role.teraflow_bank_glue_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_role_policy_attachment" "teraflow_bank_glue_policy_attachment_glue" {
  role       = aws_iam_role.teraflow_bank_glue_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "teraflow_bank_glue_policy_attachment_admin" {
  role       = aws_iam_role.teraflow_bank_glue_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Remove after debug

resource "aws_iam_role_policy" "example_role_policy" {
  name = "example_role_policy"
  role = aws_iam_role.teraflow_bank_glue_iam_role.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "iam:PassRole",
        "Resource" : "${aws_iam_role.teraflow_bank_glue_iam_role.arn}"
      }
    ]
  })
}

# Create S3 VPC Endpoint

resource "aws_vpc_endpoint" "teraflow_bank_endpoint_s3" {
  vpc_id            = var.jdbc_connection.vpc_id
  service_name      = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "teraflow_bank_endpoint_s3"
  }
}

# Create NAT Gateway

resource "aws_eip" "teraflow_bank_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "teraflow_bank_nat_gateway" {
  allocation_id     = aws_eip.teraflow_bank_eip.id
  subnet_id         = var.jdbc_connection.subnet_id
  connectivity_type = "public"

  tags = {
    Name = "teraflow_bank_nat_gateway"
  }
}

resource "aws_route" "teraflow_bank_route_nat_gateway" {
  route_table_id         = var.jdbc_connection.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.teraflow_bank_nat_gateway.id
}

# Open ingress ports for security group

resource "aws_security_group_rule" "teraflow_bank_sg_rule" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "All"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = var.jdbc_connection.security_group_id_list[0]
}

###################
# Glue Catalog    #
###################

resource "aws_glue_catalog_database" "teraflow_bank_glue_catalog_db" {
  name = "teraflow_bank_glue_catalog_db"
}

###################
# Glue Crawler    #
###################

resource "aws_glue_crawler" "teraflow_bank_glue_catalog_db" {
  database_name = aws_glue_catalog_database.teraflow_bank_glue_catalog_db.name
  name          = "teraflow_bank_glue_catalog_db"
  role          = aws_iam_role.teraflow_bank_glue_iam_role.arn

  jdbc_target {
    connection_name = aws_glue_connection.teraflow_bank_glue_connection.name
    path            = "bank_db/%"
  }
}

###################
# Glue Job        #
###################

resource "aws_glue_job" "teraflow_bank_glue_job_etl" {
  name     = "teraflow_bank_glue_job_etl"
  role_arn = aws_iam_role.teraflow_bank_glue_iam_role.arn

  command {
    script_location = "s3://${aws_s3_bucket.teraflow_bank_assets.bucket}/Glue/scripts/etl.py"
  }
}

resource "aws_glue_trigger" "teraflow_bank_schedule_monthly_glue_job" {
  name     = "teraflow_bank_schedule_monthly_glue_job"
  schedule = "cron(0 0 1 * ? *)"
  type     = "SCHEDULED"

  actions {
    job_name = aws_glue_job.teraflow_bank_glue_job_etl.name
  }
}

resource "aws_s3_bucket" "teraflow_bank_data" {
  bucket = "teraflow-bank-data"

  tags = {
    Name = "teraflow-bank-data"
  }
}

resource "aws_s3_bucket" "teraflow_bank_assets" {
  bucket = "teraflow-bank-glue-assets"

  tags = {
    Name = "teraflow-bank-glue-assets"
  }
}

resource "aws_kms_key" "teraflow_bank_s3_key" {
  description             = "This key is used to encrypt S3 bucket objects"
  deletion_window_in_days = 10
}

resource "aws_s3_bucket_server_side_encryption_configuration" "teraflow_bank_data_sse" {
  bucket = aws_s3_bucket.teraflow_bank_data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.teraflow_bank_s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "teraflow_bank_assets_sse" {
  bucket = aws_s3_bucket.teraflow_bank_data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.teraflow_bank_s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

###################
# SFTP            #
###################

resource "aws_transfer_server" "teraflow_bank_data_sftp" {
  protocols = ["SFTP"]

  tags = {
    Name = "teraflow_bank_data_ts"
  }
}

resource "aws_iam_role" "teraflow_bank_data_sftp_iam_role" {
  name               = "teraflow_bank_data_sftp_iam_role"
  assume_role_policy = data.aws_iam_policy_document.teraflow_bank_data_sftp_policy_document_assume_role.json
}

data "aws_iam_policy_document" "teraflow_bank_data_sftp_policy_document_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["transfer.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "teraflow_bank_data_sftp_policy_document_s3_access" {
  statement {
    sid       = "AllowFullAccesstoS3"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "teraflow_bank_data_sftp_role_policy" {
  name   = "teraflow_bank_data_sftp_role_policy"
  role   = aws_iam_role.teraflow_bank_data_sftp_iam_role.id
  policy = data.aws_iam_policy_document.teraflow_bank_data_sftp_policy_document_s3_access.json
}

resource "aws_transfer_user" "teraflow_bank_data_sftp_user" {
  server_id = aws_transfer_server.teraflow_bank_data_sftp.id
  user_name = "tftestuser"
  role      = aws_iam_role.teraflow_bank_data_sftp_iam_role.arn

  home_directory_type = "LOGICAL"
  home_directory_mappings {
    entry  = "/"
    target = "/${aws_s3_bucket.teraflow_bank_data.bucket}"
  }
}

# Add public key from local ssh to Server Transfer

######################
# Email Notification #
######################

resource "aws_sns_topic" "teraflow_bank_sns_topic_glue_job_fail" {
  name = "teraflow_bank_sns_topic_glue_job_fail"
}

resource "aws_cloudwatch_event_rule" "teraflow_bank_cloudwatch_event_rule_glue_job_fail" {
  name        = "teraflow_bank_cloudwatch_event_rule_glue_job_fail"
  description = "Rule to detect Glue job failures"
  event_pattern = jsonencode({
    source      = ["aws.glue"]
    detail_type = ["Glue Job State Change"]
    detail = {
      state = ["FAILED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "teraflow_bank_cloudwatch_event_target_glue_job_fail_sns" {
  rule      = aws_cloudwatch_event_rule.teraflow_bank_cloudwatch_event_rule_glue_job_fail.name
  target_id = "teraflow_bank_cloudwatch_event_target_glue_job_fail_sns"
  arn       = aws_sns_topic.teraflow_bank_sns_topic_glue_job_fail.arn
}

resource "aws_sns_topic_policy" "teraflow_bank_sns_topic_policy_glue_job_fail" {
  arn    = aws_sns_topic.teraflow_bank_sns_topic_glue_job_fail.arn
  policy = data.aws_iam_policy_document.teraflow_bank_sns_topic_policy_document_glue_job_fail.json
}

data "aws_iam_policy_document" "teraflow_bank_sns_topic_policy_document_glue_job_fail" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.teraflow_bank_sns_topic_glue_job_fail.arn]
  }
}

resource "aws_sns_topic_subscription" "teraflow_bank_sns_topic_subscription" {
  topic_arn = aws_sns_topic.teraflow_bank_sns_topic_glue_job_fail.arn
  protocol  = "email"
  endpoint  = "data-support@mybigbank.co.za"
}
