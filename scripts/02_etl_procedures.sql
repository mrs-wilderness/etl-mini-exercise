--CREATE ADDITIONAL TABLES FOR WRONG/INCOMPLETE/INTERMEDIATE DATA
--incorrect data
create table if not exists Missing_Or_Wrong_Data(
	v_id serial primary key,
	visit_date date,
	gym_code text,
	personal_code text,
	visitor_name text,
	time_in time,
	time_out time,
	require_manual_processing int default 1
);

--otherwise correct data with incomplete times
create table if not exists Incomplete_Times_Rows(
	v_id serial primary key,
	visit_date date,
	gym_code text,
	personal_code text,
	visitor_name text,
	time_in time,
	time_out time,
	require_manual_processing int default 1
);

--rows with all the values (have both times)
create table if not exists  complete_visits (
	v_id1 int not null,
	v_id2 int not null,
	visit_date date not null,
	gym_code text not null,
	personal_code text not null,
	time_in time not null,
	time_out time not null
);

--DEFINE ALL THE PROCEDURES NEEDED
--remove full duplicate rows from staging
CREATE PROCEDURE remove_duplicate_rows()
LANGUAGE SQL
BEGIN ATOMIC
	DELETE FROM Staging_Gym_Visit
	WHERE v_id NOT IN
		(SELECT MIN(v_id) --select ids of unique rows
		FROM Staging_Gym_Visit
		GROUP BY visit_date, gym_code, personal_code, visitor_name, time_in, time_out);
END;

--move rows with unacceptable null values from staging to missing_or_wrong_data
CREATE PROCEDURE process_missing_values_rows()
LANGUAGE SQL
BEGIN ATOMIC
	UPDATE Staging_Gym_Visit
	SET require_manual_processing = 1
	WHERE visit_date IS NULL
		OR gym_code IS NULL
		OR personal_code IS NULL
		OR visitor_name IS NULL;

	INSERT INTO Missing_Or_Wrong_Data(visit_date, gym_code, personal_code, visitor_name, time_in, time_out)
	(SELECT visit_date, gym_code, personal_code, visitor_name, time_in, time_out
	FROM Staging_Gym_Visit
	WHERE require_manual_processing = 1
	);
	DELETE FROM Staging_Gym_Visit
	WHERE require_manual_processing = 1;
END;

--move rows with incorrect member info from staging to missing_or_wrong_data
CREATE PROCEDURE process_incorrect_member_rows()
LANGUAGE SQL
BEGIN ATOMIC
	--mark rows with incorrect member info
	WITH stg AS --select v_id, personal_code, split name
	(
	SELECT v_id, personal_code,
		CASE WHEN gym_code = 'Gym_1' THEN SPLIT_PART(visitor_name, ' ', 1)
			WHEN gym_code = 'Gym_2' THEN SPLIT_PART (visitor_name, ' ', 2)
			END AS last_name,
		CASE WHEN gym_code = 'Gym_1' THEN SPLIT_PART(visitor_name, ' ', 2)
			WHEN gym_code = 'Gym_2' THEN SPLIT_PART (visitor_name, ' ', 1)
			END AS first_name	
	FROM Staging_Gym_Visit
	)
	UPDATE Staging_Gym_Visit
	SET require_manual_processing = 1
	WHERE v_id NOT IN
		(SELECT v_id
		FROM stg
		INNER JOIN Dim_Member AS dm
		USING(personal_code, last_name, first_name));
	
	--move incorrect member info rows from staging to missing_or_wrong_data
	INSERT INTO Missing_Or_Wrong_Data(visit_date, gym_code, personal_code, visitor_name, time_in, time_out)
	(SELECT visit_date, gym_code, personal_code, visitor_name, time_in, time_out
	FROM Staging_Gym_Visit
	WHERE require_manual_processing = 1
	);
	DELETE FROM Staging_Gym_Visit
	WHERE require_manual_processing = 1;
END;

--retrieve rows with both times from staging to complete_visits temp table
CREATE PROCEDURE retrieve_rows_with_both_times()
LANGUAGE SQL
BEGIN ATOMIC
	INSERT INTO complete_visits
	(SELECT MIN(v_id) AS v_id1, MAX(v_id) AS v_id2,
		visit_date, gym_code, personal_code,
		MAX(time_in) AS time_in, MAX(time_out) AS time_out
		FROM Staging_Gym_Visit
		GROUP BY visit_date, gym_code, personal_code
		HAVING MAX(time_in) IS NOT NULL AND MAX(time_out) IS NOT NULL);
END;

--move rows with incomplete visit times from staging to incomplete_times_rows
CREATE PROCEDURE process_incomplete_times()
LANGUAGE SQL
BEGIN ATOMIC
	--mark incomplete visits
	UPDATE Staging_Gym_Visit
	SET require_manual_processing = 1
	WHERE v_id NOT IN
		(SELECT v_id1
		FROM complete_visits)
		AND v_id NOT IN
		(SELECT v_id2
		FROM complete_visits);
	
	--move incomplete times rows from staging to Incomplete_Times_Rows
	INSERT INTO Incomplete_Times_Rows(visit_date, gym_code, personal_code, visitor_name, time_in, time_out)
	(SELECT visit_date, gym_code, personal_code, visitor_name, time_in, time_out
	FROM Staging_Gym_Visit
	WHERE require_manual_processing = 1
	);
	DELETE FROM Staging_Gym_Visit
	WHERE require_manual_processing = 1;
END;

--move rows with incorrect times (in > out) from staging to missing_or_wrong_data
CREATE PROCEDURE process_incorrect_times()
LANGUAGE SQL
BEGIN ATOMIC
	--remove incorrect times from complete_visits temp table
	DELETE FROM complete_visits
	WHERE time_in > time_out;
	
	UPDATE Staging_Gym_Visit
	SET require_manual_processing = 1
	WHERE v_id NOT IN
		(SELECT v_id1
		FROM complete_visits)
		AND v_id NOT IN
		(SELECT v_id2
		FROM complete_visits);
	
	--move wrong times info rows from staging to missing_or_wrong_data
	INSERT INTO Missing_Or_Wrong_Data(visit_date, gym_code, personal_code, visitor_name, time_in, time_out)
	(SELECT visit_date, gym_code, personal_code, visitor_name, time_in, time_out
	FROM Staging_Gym_Visit
	WHERE require_manual_processing = 1
	);
	DELETE FROM Staging_Gym_Visit
	WHERE require_manual_processing = 1;
END;

--select new dates from complete_visits, dissect, insert into Dim_Date
CREATE PROCEDURE insert_into_dim_date()
LANGUAGE SQL
BEGIN ATOMIC
	WITH new_dates AS
	(
		SELECT DISTINCT visit_date,
		EXTRACT(day FROM visit_date) AS day_number_of_month,
		EXTRACT(month FROM visit_date) AS month_number_of_year,
		EXTRACT(year FROM visit_date) AS year_number,
		TO_CHAR(visit_date, 'DY') AS day_name,
		TO_CHAR(visit_date, 'MON') AS month_name
		FROM complete_visits
		EXCEPT
		SELECT *
		FROM Dim_Date
	)
	INSERT INTO Dim_Date(date_key, day_number_of_month, month_number_of_year, year_number, day_name, month_name)
	(SELECT *
	FROM new_dates);
END;

--insert the correct rows into fact_visit
CREATE or replace PROCEDURE insert_into_fact_visit()
LANGUAGE SQL
BEGIN ATOMIC
	WITH vals AS
	(SELECT dg.gym_id, dm.member_id, cv.visit_date AS visit_date_key, EXTRACT(EPOCH FROM (cv.time_out - cv.time_in))::INT/60 AS visit_duration,
		CASE WHEN cv.time_in <= '10:00' THEN 'Morning'::day_part_enum
			WHEN cv.time_in >= '17:01' THEN 'Evening'::day_part_enum
			ELSE 'Day'::day_part_enum END AS day_part
	FROM complete_visits AS cv
	LEFT JOIN Dim_Gym AS dg
	USING(gym_code)
	LEFT JOIN Dim_Member AS dm
	USING(personal_code))
	INSERT INTO Fact_Visit (gym_id, member_id, visit_date_key, visit_duration, day_part)
	(SELECT *
	FROM vals
	EXCEPT
	SELECT gym_id, member_id, visit_date_key, visit_duration, day_part
	FROM Fact_Visit);

	DELETE FROM Staging_Gym_Visit;
	DELETE FROM complete_visits;
END;

--retrieve rows that got complete after the latest batch
CREATE PROCEDURE retrieve_from_incomplete_times()
LANGUAGE SQL
BEGIN ATOMIC
	WITH com AS (
	SELECT MIN(v_id) AS v_id1, MAX(v_id) AS v_id2
		FROM Incomplete_Times_Rows
		GROUP BY visit_date, gym_code, personal_code
		HAVING MAX(time_in) IS NOT NULL AND MAX(time_out) IS NOT NULL
			AND MAX(time_in) <= MAX(time_out))
	UPDATE Incomplete_Times_Rows
	SET require_manual_processing = 0
	WHERE v_id IN
		(SELECT v_id1 FROM com)
		OR v_id IN
		(SELECT v_id2 FROM com);
	
	INSERT INTO Staging_Gym_Visit(visit_date, gym_code, personal_code, visitor_name, time_in, time_out)
	(SELECT visit_date, gym_code, personal_code, visitor_name, time_in, time_out
	FROM Incomplete_Times_Rows
	WHERE require_manual_processing = 0);
	DELETE FROM Incomplete_Times_Rows
	WHERE require_manual_processing = 0;
END;