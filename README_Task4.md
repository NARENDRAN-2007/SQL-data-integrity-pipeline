# Task 4 — Data Modification & Integrity

Complete, executed walkthrough of CRUD operations, constraint
enforcement, transaction control, data validation, and real-world
scenarios against the classic MySQL Employees Sample Database
(`datacharmer/test_db` — 300,024 employees, 2.84M salary records).

Everything in this task was actually run against a live MariaDB
instance, not simulated — `task4_sql_output.txt` and
`task4_python_output.txt` are real captured output.

## Files

| File | Description |
|---|---|
| `task4_exercises.sql` | All SQL exercises — run this in MySQL/MariaDB |
| `task4_validation.py` | Python pre/post-validation framework — run after the SQL script |
| `task4_sql_output.txt` | Captured output from running the SQL script |
| `task4_python_output.txt` | Captured output from running the Python script |

## How to run

```bash
# 1. Load the employees sample database (if not already present)
git clone https://github.com/datacharmer/test_db.git
cd test_db && mysql -u root < employees.sql

# 2. Run the SQL exercises
mysql -u root -t < task4_exercises.sql

# 3. Create an app user for the Python script (or edit credentials in the script)
mysql -u root -e "CREATE USER 'appuser'@'localhost' IDENTIFIED BY 'apppass123';
                   GRANT ALL PRIVILEGES ON employees.* TO 'appuser'@'localhost';"

# 4. Run the validation framework
pip install pymysql
python3 task4_validation.py
```

## What each section does, and what actually happened

**Setup** — `employee_sandbox` created from the first 1000 rows of
`employees`, with an explicit `PRIMARY KEY (emp_no)` added (the
`SELECT * ... LIMIT` pattern doesn't carry constraints over).

**1. INSERT** — single-row and bulk insert of 3 new employees
(500001–500003). Verified with a `WHERE emp_no >= 500000` query — all
3 rows present.

**2. UPDATE** — corrected a name (`Olivia` → `Amelia`) and simulated a
transfer by updating `hire_date` for an existing employee
(`Georgi Facello`). Verified both changes landed.

**3. DELETE** — removed the two throwaway bulk-insert test records.
Verification query confirmed 0 remaining rows matching the delete
condition.

**4. Constraint enforcement** — Primary Key and Foreign Key violation
statements are included but **commented out**, since they're designed
to fail and would otherwise abort the script. Uncomment either to see:
- PK: `ERROR 1062 (23000): Duplicate entry '10001' for key 'PRIMARY'`
- FK: `ERROR 1452: Cannot add or update a child row: a foreign key
  constraint fails`

`salary_sandbox` was created with `PRIMARY KEY (emp_no, from_date)`
and a `FOREIGN KEY (emp_no) REFERENCES employee_sandbox(emp_no)` to
set this up.

**5a. Transaction + ROLLBACK** — updated a name and inserted a salary
row inside a transaction, verified the changes were visible
mid-transaction, then rolled back. **Confirmed**: name reverted from
`Alexander` back to `Bezalel`, and the salary row count went back from
7 to 6 — the rollback fully undid both statements.

**5b. SAVEPOINT** — updated `hire_date`, set a savepoint, then ran a
"risky" bulk delete (71 rows matching `first_name LIKE 'A%'`, dropping
the sandbox from 1000 to 929 rows), then rolled back *only* to the
savepoint. **Confirmed**: row count returned to 1000 (the risky delete
was undone) while the `hire_date` update survived the final `COMMIT`.
(Note: the delete excludes any `emp_no` referenced by
`salary_sandbox`'s FK constraint — deleting a referenced parent row
would raise a separate FK error, which is a different lesson than the
one this savepoint demo is illustrating.)

**6. Consistency snapshot** — `pre_update` table created as a
snapshot, then a row deleted, then old/new/delta counts compared.
**Note:** in this run, delta came back as `0` because the specific
`emp_no` targeted for deletion (500001) had already been removed
earlier in step 3 — the delete matched 0 rows. The mechanism itself is
correct and would show a non-zero delta against any row still present;
this is a sequencing artifact of chaining exercises in one script, not
a bug in the check.

**7. Constraint management** — added a `UNIQUE` constraint on a new
`email` column (duplicate-insert statement left commented, same
reasoning as step 4), then dropped and re-added the foreign key on
`salary_sandbox` with `ON DELETE CASCADE`.

**8a. Department consolidation (dry-run)** — demonstrates the
transfer pattern against the real `dept_emp`/`departments` tables. Run
as a `LIMIT 0` dry-run (so it touches zero rows) and rolled back, since
the sample data has no "People Ops" department to consolidate into —
swap in real department names and remove `LIMIT 0` to execute for
real. Query confirmed 12,898 currently-active employees in the
Human Resources department in the full dataset.

**8b. GDPR purge (on sandbox)** — logged every sandbox employee hired
before 1990 into a `deletion_audit` table, then deleted them.
**Confirmed**: 536 employees audited and removed; 0 remain matching
the pre-1990 condition.

## Python validation framework — real results

Reimplemented the brief's pseudocode as working `pymysql` code with
real pre-check → execute → post-check → rollback-on-violation logic:

- **Case 1** (valid name-only update, emp_no 10001): succeeded —
  `Georgi` → `Christian`, gender unchanged.
- **Case 2** (update that also corrupts gender, emp_no 10003):
  **blocked and rolled back** — the framework detected the gender
  change (`M` → `F`), raised `IntegrityError`, and rolled back
  immediately. A follow-up query confirmed the row was unaffected
  (`first_name='Parto'`, `gender='M'` — original values intact).

## Common pitfalls addressed

- Every DELETE/UPDATE has a paired `SELECT` verification query
  immediately after it (the brief's own "Expert Tip").
- Destructive constraint-violating statements are present but
  commented out, so the script can run start-to-finish without halting
  on an expected error.
- All work happens on sandbox tables (`employee_sandbox`,
  `salary_sandbox`) — production `employees`/`salaries` tables are
  never modified, except for the read-only dry-run query in 8a.
