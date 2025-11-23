## Gym ETL SQL Mini-Project

This small project demonstrates a basic SQL ETL workflow using PostgreSQL.
It was originally completed as a university homework on ETL fundamentals.

### Task overview
The dataset simulates gym visitor check-ins stored in a staging table.
The task originally provided a create script, the first data batch, and a second data batch to check rerunnability.

The goal of the ETL flow is to perform the basic operations specified in the task. The procedures defined in the script have self-explanatory names that reflect those operations.

### How to run:
1. Create a PostgreSQL database and run 01_task_setup_initial_batch.sql (schema creation + initial staging load).
2. Run 02_etl_procedures.sql (define ETL procedures).
3. Run 03_run_etl.sql (execute the ETL pipeline).
4. Run 04_task_setup_second_batch.sql (second dataset batch for incremental load).
5. Rerun 03_run_etl.sql to check rerunnability.
