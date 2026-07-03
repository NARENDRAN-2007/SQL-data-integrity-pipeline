
DROP TABLE IF EXISTS employee_sandbox;
DROP TABLE IF EXISTS salary_sandbox;
DROP TABLE IF EXISTS deletion_audit;
DROP TABLE IF EXISTS pre_update;

CREATE TABLE employee_sandbox AS
SELECT * FROM employees LIMIT 1000;

ALTER TABLE employee_sandbox ADD PRIMARY KEY (emp_no);

SELECT '--- Sandbox created ---' AS step;
SELECT COUNT(*) AS sandbox_row_count FROM employee_sandbox;


SELECT '--- 1. INSERT ---' AS step;

-- Single record
INSERT INTO employee_sandbox
(emp_no, birth_date, first_name, last_name, gender, hire_date)
VALUES
(500001, '1995-08-14', 'Emma', 'Johnson', 'F', '2023-06-01');

-- Bulk insert
INSERT INTO employee_sandbox VALUES
(500002, '1990-11-03', 'Liam', 'Smith', 'M', '2023-06-01'),
(500003, '1988-04-22', 'Olivia', 'Brown', 'F', '2023-06-01');

-- Verify
SELECT * FROM employee_sandbox WHERE emp_no >= 500000;


SELECT '--- 2. UPDATE ---' AS step;

-- Correct name spelling
UPDATE employee_sandbox
SET first_name = 'Amelia'
WHERE emp_no = 500003;

-- Department transfer simulation (update hire_date for a named employee)
UPDATE employee_sandbox
SET hire_date = '2023-07-15'
WHERE first_name = 'Georgi' AND last_name = 'Facello';

-- Verify
SELECT * FROM employee_sandbox WHERE first_name IN ('Amelia', 'Georgi');


SELECT '--- 3. DELETE ---' AS step;

DELETE FROM employee_sandbox
WHERE hire_date = '2023-06-01' AND emp_no > 500000;

-- Verify deletion (should be 0 -- Amelia/500003 has hire_date
-- 2003-xx from original data, only 500001/500002 match this filter)
SELECT COUNT(*) AS remaining_after_delete
FROM employee_sandbox
WHERE hire_date = '2023-06-01' AND emp_no > 500000;



SELECT '--- 4a. Primary Key violation (expected to fail) ---' AS step;

-- Attempt duplicate employee number -- this WILL raise an error;
-- that error is the point of the exercise (constraint is working).
-- INSERT INTO employee_sandbox VALUES (10001, '1953-09-02', 'John', 'Doe', 'M', '1986-06-26');
-- Left commented so the script can run start-to-finish without halting.
-- Uncomment to see: ERROR 1062 (23000): Duplicate entry '10001' for key 'PRIMARY'

SELECT '--- 4b. Foreign Key enforcement ---' AS step;

CREATE TABLE salary_sandbox AS SELECT * FROM salaries LIMIT 1000;
ALTER TABLE salary_sandbox ADD PRIMARY KEY (emp_no, from_date);

ALTER TABLE salary_sandbox
ADD CONSTRAINT fk_emp
FOREIGN KEY (emp_no) REFERENCES employee_sandbox(emp_no);

-- Attempt invalid insert (emp_no 999999 doesn't exist in employee_sandbox)
-- this WILL raise an error; that error is the point of the exercise.
-- INSERT INTO salary_sandbox VALUES (999999, 80000, '2023-01-01', '9999-01-01');
-- Uncomment to see: ERROR 1452: Cannot add or update a child row: a foreign key constraint fails


SELECT '--- 5a. Atomic update + ROLLBACK ---' AS step;

START TRANSACTION;

UPDATE employee_sandbox
SET first_name = 'Alexander'
WHERE emp_no = 10002;

INSERT INTO salary_sandbox
VALUES (10002, 75000, CURDATE(), '9999-01-01');

SELECT * FROM employee_sandbox WHERE emp_no = 10002;
SELECT * FROM salary_sandbox WHERE emp_no = 10002;

ROLLBACK;

-- Verify rollback -- name should be back to original, salary row gone
SELECT * FROM employee_sandbox WHERE emp_no = 10002;
SELECT COUNT(*) AS salary_row_after_rollback FROM salary_sandbox WHERE emp_no = 10002;


SELECT '--- 5b. SAVEPOINT ---' AS step;

START TRANSACTION;

UPDATE employee_sandbox
SET hire_date = '2023-01-01'
WHERE emp_no = 10003;

SAVEPOINT sp1;

-- Risky bulk operation
-- (excludes emp_nos referenced by salary_sandbox's FK constraint --
--  those would raise a separate FK error, which is a different
--  lesson than the one this SAVEPOINT demo is showing)
DELETE FROM employee_sandbox
WHERE first_name LIKE 'A%'
  AND emp_no NOT IN (SELECT emp_no FROM salary_sandbox);

SELECT COUNT(*) AS remaining_after_risky_delete FROM employee_sandbox;

-- Revert only the risky delete, keep the hire_date update
ROLLBACK TO SAVEPOINT sp1;

SELECT COUNT(*) AS remaining_after_savepoint_rollback FROM employee_sandbox;

COMMIT;  -- only the hire_date update is persisted

SELECT hire_date FROM employee_sandbox WHERE emp_no = 10003;

SELECT '--- 6. Consistency snapshot ---' AS step;

CREATE TABLE pre_update AS SELECT * FROM employee_sandbox;

-- Simulate a batch of changes
DELETE FROM employee_sandbox WHERE emp_no = 500001;

SELECT
    (SELECT COUNT(*) FROM pre_update) AS old_count,
    (SELECT COUNT(*) FROM employee_sandbox) AS new_count,
    (SELECT COUNT(*) FROM pre_update) - (SELECT COUNT(*) FROM employee_sandbox) AS delta;



SELECT '--- 7a. Adding a UNIQUE constraint ---' AS step;

ALTER TABLE employee_sandbox ADD COLUMN email VARCHAR(255);
ALTER TABLE employee_sandbox ADD CONSTRAINT uc_email UNIQUE (email);

UPDATE employee_sandbox SET email = 'test@company.com' WHERE emp_no = 10001;
-- Second identical email WILL fail the UNIQUE constraint -- left commented:
-- UPDATE employee_sandbox SET email = 'test@company.com' WHERE emp_no = 10004;
-- Uncomment to see: ERROR 1062 (23000): Duplicate entry 'test@company.com' for key 'uc_email'

SELECT '--- 7b. Dropping and re-adding FK with ON DELETE CASCADE ---' AS step;

ALTER TABLE salary_sandbox DROP FOREIGN KEY fk_emp;

ALTER TABLE salary_sandbox
ADD CONSTRAINT fk_emp
FOREIGN KEY (emp_no) REFERENCES employee_sandbox(emp_no)
ON DELETE CASCADE;

SELECT 'FK re-added with ON DELETE CASCADE' AS result;

SELECT '--- 8a. Scenario: Department consolidation ---' AS step;

START TRANSACTION;

SET @peopleops_dept = (SELECT dept_no FROM departments WHERE dept_name = 'Human Resources');

-- (Using the existing 'Human Resources' dept as both source/target proxy,
--  since a 'People Ops' department doesn't exist in the sample data --
--  this demonstrates the pattern the brief describes.)
UPDATE dept_emp
SET dept_no = @peopleops_dept
WHERE dept_no = @peopleops_dept
  AND to_date > CURDATE()
LIMIT 0;  -- LIMIT 0 keeps this a dry-run demonstration; remove to execute for real

SELECT COUNT(*) AS active_hr_employees
FROM dept_emp
WHERE dept_no = @peopleops_dept AND to_date > CURDATE();

ROLLBACK;  -- dry-run only, nothing committed


SELECT '--- 8b. Scenario: GDPR data purge (on sandbox only) ---' AS step;

CREATE TABLE deletion_audit (
    emp_no INT PRIMARY KEY,
    delete_date DATE
);

START TRANSACTION;

INSERT INTO deletion_audit
SELECT emp_no, CURDATE()
FROM employee_sandbox
WHERE hire_date < '1990-01-01';

DELETE FROM employee_sandbox
WHERE hire_date < '1990-01-01';

SELECT COUNT(*) AS remaining_pre_1990
FROM employee_sandbox
WHERE hire_date < '1990-01-01';  -- should be 0

SELECT COUNT(*) AS audited_deletions FROM deletion_audit;

COMMIT;

SELECT '--- ALL EXERCISES COMPLETE ---' AS step;
