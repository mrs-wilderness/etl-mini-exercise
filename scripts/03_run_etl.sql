--RUN THE ETL PROCEDURES
CALL remove_duplicate_rows();
CALL process_missing_values_rows();
CALL process_incorrect_member_rows();
CALL retrieve_rows_with_both_times();
CALL process_incomplete_times();
CALL process_incorrect_times();
CALL insert_into_dim_date();
CALL insert_into_fact_visit();
CALL retrieve_from_incomplete_times();
CALL retrieve_rows_with_both_times();
CALL insert_into_dim_date();
CALL insert_into_fact_visit();