from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from pyspark.sql import SQLContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.window import Window
from pyspark.sql import functions
import sys
import boto3
from datetime import datetime, timedelta

## @params: [JOB_NAME]
args = getResolvedOptions(sys.argv, ['JOB_NAME','output_location','database_name'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
spark_session = glueContext.spark_session
sqlContext = SQLContext(spark_session.sparkContext, spark_session)
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

glue = boto3.client("glue")
DATABASE_NAME = args['database_name']
OUTPUT_LOCATION = args['output_location']

def table_reader(table_name: str, database_name: str):
    df = glueContext.create_dynamic_frame.from_catalog(
        database= database_name,
        table_name= table_name,
        transformation_ctx="read_table"
    )
    
    df = df.toDF()
    return df

banking_account = table_reader("banking_account", DATABASE_NAME)
banking_bank = table_reader("banking_bank", DATABASE_NAME)
banking_branch = table_reader("banking_branch", DATABASE_NAME)
banking_client = table_reader("banking_client", DATABASE_NAME)
banking_loans = table_reader("banking_loans", DATABASE_NAME)

banking_branch = banking_branch.withColumnRenamed("Bank_idBank","idBank")
banking_client = banking_client.withColumnRenamed("Branch_idBranch","idBranch")
banking_account = banking_account.withColumnRenamed("Client_idClient","idClient")
banking_loans = banking_loans.withColumnRenamed("Account_idAccount","idAccount")

total = banking_loans.join(banking_account,"idAccount").join(banking_client.select(["idClient","Surname","idBranch"]),"idClient").join(banking_branch,"idBranch").join(banking_bank,"idBank")
comp = banking_branch.join(banking_bank,"idBank").select(["idBranch","Name"])

selected_columns = ["Name","idBranch","Surname","Amount","loan_date"]
final = total.select(selected_columns)

current_date = datetime.now()
moving_data = final.select(["idBranch","Amount","loan_date"]).orderBy(col("idBranch").asc(), col("loan_date").asc())

pan_comp = comp.toPandas()
Banks = list(set(pan_comp["Name"].to_list()))

three_months_ago = current_date - timedelta(days=90)
three_months_ago = three_months_ago.strftime("%Y-%m-%d")

for bank in Banks:
    branch_ids = comp.filter(comp["Name"] == bank).select("idBranch").rdd.flatMap(lambda x: x).collect()
    window_spec = Window.partitionBy("idBranch").orderBy("loan_date").rowsBetween(Window.unboundedPreceding, Window.currentRow)
    df = moving_data.filter((moving_data["idBranch"].isin(branch_ids)) & (moving_data["loan_date"] >= three_months_ago)) \
        .withColumn("moving_average", functions.avg("Amount").over(window_spec)) \
        .groupBy("idBranch").agg(functions.last("moving_average").alias("Moving_Average"))
    df.show()
    df = df.toPandas()
    df.to_csv(f"{OUTPUT_LOCATION}/bank_name = {bank}/year = {current_date.strftime('%Y')}/month = {current_date.strftime('%m')}/{bank}_{current_date.strftime('%Y_%m_%d')}.csv", index = False)
    # df.write.format("csv").option("header", "true").mode("overwrite").save(f"{OUTPUT_LOCATION}/bank_name = {bank}/year = {current_date.strftime('%Y')}/month = {current_date.strftime('%m')}/{bank}_{current_date.strftime('%Y_%m_%d')}.csv")

    
job.commit()