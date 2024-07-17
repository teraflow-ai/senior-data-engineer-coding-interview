import sys
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.sql import functions as F
from pyspark.sql.window import Window
import datetime
import pandas as pd
import boto3

# Define glue spark context
sc = SparkContext.getOrCreate()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)

# Define database and table names
database = 'teraflow_bank_glue_catalog_db'
loans_table = 'bank_db_public_loans'
account_table = 'bank_db_public_account'
branch_table = 'bank_db_public_branch'
bank_table = 'bank_db_public_bank'
client_table = 'bank_db_public_client'

# Get the current date and calculate the date four months ago and the previous month
current_date = datetime.datetime.now()
first_day_of_current_month = current_date.replace(day=1)
last_day_of_previous_month = first_day_of_current_month - datetime.timedelta(days=1)
first_day_of_previous_month = last_day_of_previous_month.replace(day=1)
four_months_ago_date = first_day_of_previous_month - datetime.timedelta(days=3*30)

# Load data from Glue Catalog with predicate pushdown for loans from the last four months
loans_pushdown_predicate = f"loan_date >= '{four_months_ago_date.strftime('%Y-%m-%d')}'"
loans = glueContext.create_dynamic_frame.from_catalog(
    database=database, 
    table_name=loans_table,
    push_down_predicate=loans_pushdown_predicate
).toDF()
accounts = glueContext.create_dynamic_frame.from_catalog(database=database, table_name=account_table).toDF()
branches = glueContext.create_dynamic_frame.from_catalog(database=database, table_name=branch_table).toDF()
banks = glueContext.create_dynamic_frame.from_catalog(database=database, table_name=bank_table).toDF()
clients = glueContext.create_dynamic_frame.from_catalog(database=database, table_name=client_table).toDF()

# Join tables to get necessary columns
loans_with_accounts = loans.join(accounts, loans.account_idaccount == accounts.idaccount, 'inner')
loans_with_clients = loans_with_accounts.join(clients, loans_with_accounts.client_idclient == clients.idclient, 'inner')
loans_with_branches = loans_with_clients.join(branches, loans_with_clients.branch_idbranch == branches.idbranch, 'inner')
loans_complete = loans_with_branches.join(banks, loans_with_branches.bank_idbank == banks.idbank, 'inner').select(loans_with_branches['*'], banks['idBank'], banks['Name'].alias('BankName'))

# Calculate the 3-month moving average
window_spec = Window.partitionBy('idBank', 'idBranch').orderBy(F.col('loan_date').cast('long')).rangeBetween(-90*86400, 0)
loans_complete = loans_complete.withColumn('moving_avg_3_months', F.round(F.avg('Amount').over(window_spec),2))

# Select relevant columns with aliases
output_df = loans_complete.select(
    F.col('BankName').alias('BankName'),
    F.col('Address').alias('BranchAddress'),
    F.col('Account_idAccount').alias('AccountId'),
    F.col('idLoan').alias('LoanId'),
    F.col('Amount').alias('LoanAmount'),
    F.col('moving_avg_3_months').alias('LoanMovingAvg3Months'),
    F.col('loan_date').alias('LoanDate')
).orderBy('Address','loan_date')

# Filter the loans to include only those from the previous month
previous_month_loans = output_df.filter((F.col('LoanDate') >= first_day_of_previous_month) & (F.col('LoanDate') <= last_day_of_previous_month))

# Write the result to S3 in the specified format
bucket_name = 'teraflow-bank-glue-output'
client = boto3.client('s3')
prefix = 'output/'

for bank_name in previous_month_loans.select('BankName').distinct().collect():
    bank_name = bank_name['BankName']
    bank_data = previous_month_loans.filter(F.col('BankName') == bank_name)
    
    bank_data.write_dynamic_frame.from_options(
        frame=bank_data,
        connection_type="s3",
        format="csv",
        connection_options={"path": "s3://"+bucket_name, "partitionKeys": []},
        format_options={"compression": "none"},
    )

    response = client.list_objects(
        Bucket=bucket_name, Prefix=prefix)

    name = response['Contents'][0]['Key']
    
    year = first_day_of_previous_month.year
    month = first_day_of_previous_month.month
    current_date_str = current_date.strftime('%Y%m%d')
    
    output_file_path = f"{bank_name}/{year}/{month:02d}/{bank_name}_{current_date_str}.csv"

    client.copy_object(Bucket=bucket_name, CopySource=bucket_name+'/'+name, Key=output_file_path)
    client.delete_object(Bucket=bucket_name ,Key=name)

job.commit()