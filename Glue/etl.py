import boto3
import csv
from datetime import datetime
import logging
import smtplib

glue_context = boto3.client("glue", region_name="us-east-1")

# Creating an SFTP server on EC2 using Terraform
# TODO: Definining the Terraform configuration to create an EC2 instance with an SFTP server
def etl_job():
    try:
        # Database connection details
        connection_string = "jdbc:postgresql://mycluster.cluster-123456789012.us-east-1.rds.amazonaws.com:5432/bankdatabase"
        username = "postgres"
        password = "5Y67bg#r#"

        # Creating a connection to the database using AWS Glue
        connection = glue_context.create_connection(
            ConnectionName="AuroraConnection",
            ConnectionType="JDBC",
            DriverName="PostgreSQL",
            ConnectionString=connection_string,
            Username=username,
            Password=password
        )

        # Fetching tables from AWS Glue catalog
        banks = glue_context.get_table("Banks")
        branches = glue_context.get_table("Branches")
        loans = glue_context.get_table("Loans")

        moving_averages = {}
        # Calculate moving averages for each branch
        for branch in branches:
            # Filtering loans for the last three months
            loans_in_last_three_months = loans.filter(
                "loan_date > CURRENT_DATE - INTERVAL '3' MONTH"
            )
            # Aggregating total loan amount
            total_loan_amount = loans_in_last_three_months.aggregate("SUM(amount)")
            moving_averages[branch["idBranch"]] = total_loan_amount / 3

        # Generate CSV files for each bank and branch
        for bank in banks:
            filename = f"{bank['name']}_{str(datetime.now()).replace(' ', '_')}.csv"

            with open(filename, "w") as f:
                writer = csv.writer(f)
                writer.writerow(["Bank", "Branch", "Moving Average"])

                for branch in branches:
                    # Writing bank, branch, and moving average to CSV
                    writer.writerow([bank["name"], branch["name"], moving_averages[branch["idBranch"]]])

        # Close the database connection
        connection.close()

        # Adding logging
        logging.basicConfig(filename='etl_job.log', level=logging.INFO)
        logging.info('ETL job completed successfully')

        # Sending notifications upon job failure to a support email address
        send_email("ETL Job Notification", "ETL job completed successfully")

    except Exception as e:
        # Handling job failure
        logging.error(f'ETL job failed: {str(e)}')

        # Sending failure notifications to data-support@mybigbank.co.za
        send_email("ETL Job Failure", f'ETL job failed: {str(e)}')

        raise e

# Ensuring idempotency of the ETL system
# TODO: Implement idempotency measures using a flag or a version control system to avoid duplicate data processing

def send_email(subject, message):
    from_addr = 'user@gmail.com'
    to_addr = 'data-support@mybigbank.co.za'
    smtp_server = 'smtp.example.com'

    email_body = f"Subject: {subject}\n\n{message}"

    try:
        with smtplib.SMTP(smtp_server) as server:
            server.sendmail(from_addr, to_addr, email_body)
            logging.info('Notification email sent successfully')
    except Exception as e:
        logging.error(f'Failed to send notification email: {str(e)}')

etl_job()
