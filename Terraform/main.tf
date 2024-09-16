##################
# Glue Catalog   #
##################

# Creating a Glue Catalog Database named "bank_data"
resource "aws_glue_catalog_database" "bank_data" {
  name = "bank_data"
}


##################
# Glue Crawler   #
##################

# Creating a Glue Crawler to crawl and catalog the data in an S3 bucket
resource "aws_glue_crawler" "bank_data_crawler" {
  name           = "bank_data_crawler"
  database_name  = aws_glue_catalog_database.bank_data.name
  role           = "arn:aws:iam::123456789012:role/glue-crawler-role"
  schedule       = "cron(0 0 1 * * ? *)"   # Run the crawler once a month on the 1st day

  s3_target {
    path = "s3://my-bucket/bank-data/"    # Specify the path of the S3 bucket to crawl
  }
}


##################
# Glue Job       #
##################

# Creating a Glue Job to perform ETL operations on the data
resource "aws_glue_job" "bank_data_job" {
  name        = "bank_data_job"
  role_arn    = "arn:aws:iam::123456789012:role/glue-job-role"
  description = "This job reads data from the Aurora cluster Data Store and writes it to S3."

  command {
    script_location = "s3://my-bucket/bank-data/etl.py"   # Specify the location of the ETL script in S3
  }

  dag {
    nodes {
      name = "read_data"
      action = "ReadFromJdbc"
      arguments {
        query            = "SELECT * FROM bank_data"    # Specify the SQL query to read data from the Aurora cluster
        connection_name  = "mycluster.cluster-123456789012.us-east-1.rds.amazonaws.com"    # Specify the Aurora cluster endpoint
        username         = db_username   # Specify the database username (retrieve from secure storage)
        password         = db_password   # Specify the database password (retrieve from secure storage)
      }
    }

    nodes {
      name = "write_data"
      action = "WriteToS3"
      arguments {
        path   = "s3://my-bucket/bank-data/"    # Specify the path in the S3 bucket to write the data
        format = "CSV"   # Specify the output format for the data
      }
    }

    edges {
      from = "read_data"
      to   = "write_data"
    }
  }
}


##################
# S3 Bucket      #
##################

# Create an S3 bucket to store the data
resource "aws_s3_bucket" "bank_data_bucket" {
  name     = "my-bucket"
  region   = "us-east-1"
  versioning {
    enabled = true   # Enable versioning for the bucket
  }
}


##################
# EC2 Instance   #
##################

# Create an EC2 instance for the SFTP server
resource "aws_instance" "sftp_server" {
  ami           = "ami-1234567890"   # Specify the appropriate AMI for the EC2 instance
  instance_type = "t2.micro"   # Specify the instance type for the EC2 instance
  key_name      = "my-key-pair"   # Specify the key pair to use for SSH access

  # Other necessary configurations for the EC2 instance
  # ...

  # Provisioning script to set up the SFTP server
  user_data = <<-EOF
    # setting up local SFTP server
  EOF
}

##################
# Notifications  #
##################

# Setting up notifications for job failure
resource "aws_cloudwatch_event_rule" "job_failure_notification_rule" {
  name        = "job_failure_notification_rule"
  description = "Trigger notification on Glue Job failure"

  schedule_expression = "cron(0 12 * * ? *)"

  event_pattern = <<PATTERN
    {
      "source": [
        "aws.glue"
      ],
      "detail-type": [
        "Glue Job State Change"
      ],
      "detail": {
        "jobName": [
          "bank_data_job"
        ],
        "state": [
          "FAILED"
        ]
      }
    }
  PATTERN
}

resource "aws_cloudwatch_event_target" "job_failure_notification_target" {
  rule      = aws_cloudwatch_event_rule.job_failure_notification_rule.name
  target_id = "send_job_failure_notification"
  arn       = "arn:aws:sns:us-east-1:123456789012:job_failure_notification_topic"  # Specifying the ARN of the SNS topic to send notifications to
}

##################
# Idempotency    #
##################

# Ensure idempotency of the ETL system by using Terraform's state management and resource lifecycle management

##################
# Security       #
##################

# Store passwords and connection details securely, such as using AWS Secrets Manager or environment variables
# Enable encryption for S3 bucket data using AWS S3 Server-Side Encryption or other suitable encryption methods
# Rotate passwords regularly according to security policies