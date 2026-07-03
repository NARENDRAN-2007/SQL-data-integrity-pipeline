"""
Task 4 — Data Validation Framework
Pre/Post Change Checks (real implementation of the brief's pseudocode)
------------------------------------------------------------------
Demonstrates: an update wrapped in pre-check -> execute -> post-check
-> rollback-on-violation logic, using employee_sandbox in the
employees database. Detects and blocks any attempt to change an
"immutable" attribute (gender) as part of what should have been a
name-only update.
"""

import pymysql
import sys


class IntegrityError(Exception):
    pass


def get_connection():
    return pymysql.connect(
        host='127.0.0.1',
        user='appuser',
        password='apppass123',
        database='employees',
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
    )


def fetch_employee(cursor, emp_no):
    cursor.execute("SELECT * FROM employee_sandbox WHERE emp_no = %s", (emp_no,))
    return cursor.fetchone()


def log_change(old_record, new_record):
    print(f"  [LOG] emp_no={old_record['emp_no']}: "
          f"first_name '{old_record['first_name']}' -> '{new_record['first_name']}'")


def update_employee_name(conn, emp_no, new_name, simulate_gender_corruption=False):
    """
    Updates an employee's first name with pre/post-validation.
    If simulate_gender_corruption=True, deliberately corrupts gender
    in the same statement to demonstrate the integrity check catching
    an unintended side effect (the kind of bug this pattern exists to
    catch in a real update statement gone wrong).
    """
    with conn.cursor() as cursor:
        # --- Pre-check ---
        old_record = fetch_employee(cursor, emp_no)
        if old_record is None:
            raise ValueError(f"emp_no {emp_no} not found")

        # --- Execute update ---
        if simulate_gender_corruption:
            flipped_gender = 'F' if old_record['gender'] == 'M' else 'M'
            cursor.execute(
                "UPDATE employee_sandbox SET first_name = %s, gender = %s WHERE emp_no = %s",
                (new_name, flipped_gender, emp_no)
            )
        else:
            cursor.execute(
                "UPDATE employee_sandbox SET first_name = %s WHERE emp_no = %s",
                (new_name, emp_no)
            )

        # --- Post-validation ---
        new_record = fetch_employee(cursor, emp_no)

        if old_record['gender'] != new_record['gender']:
            conn.rollback()
            raise IntegrityError(
                f"Gender cannot be modified (emp_no={emp_no}): "
                f"{old_record['gender']} -> {new_record['gender']}. Rolled back."
            )

        log_change(old_record, new_record)
        conn.commit()
        return new_record


def consistency_check(conn):
    """Row-count delta check against the pre_update snapshot table."""
    with conn.cursor() as cursor:
        cursor.execute("""
            SELECT
                (SELECT COUNT(*) FROM pre_update) AS old_count,
                (SELECT COUNT(*) FROM employee_sandbox) AS new_count,
                (SELECT COUNT(*) FROM pre_update) - (SELECT COUNT(*) FROM employee_sandbox) AS delta
        """)
        return cursor.fetchone()


def get_sample_emp_nos(conn, n=2):
    """Pull real, currently-existing emp_nos from the sandbox table
    rather than hardcoding IDs that may have been deleted/renumbered
    earlier in the exercise sequence."""
    with conn.cursor() as cursor:
        cursor.execute("SELECT emp_no FROM employee_sandbox ORDER BY emp_no LIMIT %s", (n,))
        return [row['emp_no'] for row in cursor.fetchall()]


if __name__ == '__main__':
    conn = get_connection()
    print("=" * 60)
    print("Data Validation Framework — pre/post integrity checks")
    print("=" * 60)

    emp_a, emp_b = get_sample_emp_nos(conn, 2)
    print(f"\nUsing live sample emp_nos from employee_sandbox: {emp_a}, {emp_b}")

    # --- Case 1: normal, valid update ---
    print(f"\nCase 1: valid name-only update on emp_no={emp_a} (should succeed)")
    try:
        result = update_employee_name(conn, emp_no=emp_a, new_name='Christian')
        print(f"  SUCCESS: {result['emp_no']} is now '{result['first_name']}', "
              f"gender unchanged ({result['gender']})")
    except IntegrityError as e:
        print(f"  BLOCKED: {e}")

    # --- Case 2: update that corrupts an immutable field ---
    print(f"\nCase 2: update that also corrupts gender on emp_no={emp_b} "
          f"(should be blocked + rolled back)")
    try:
        result = update_employee_name(conn, emp_no=emp_b, new_name='Kyoichi',
                                       simulate_gender_corruption=True)
        print(f"  SUCCESS (unexpected): {result}")
    except IntegrityError as e:
        print(f"  BLOCKED: {e}")

        # Verify the rollback actually held
        with conn.cursor() as cursor:
            row = fetch_employee(cursor, emp_b)
            print(f"  Verified post-rollback state: emp_no={row['emp_no']}, "
                  f"first_name='{row['first_name']}', gender='{row['gender']}'")

    # --- Consistency snapshot check ---
    print("\nConsistency check (pre_update snapshot vs. current employee_sandbox):")
    delta = consistency_check(conn)
    print(f"  old_count={delta['old_count']}, new_count={delta['new_count']}, "
          f"delta={delta['delta']}")

    conn.close()
    print("\nDone.")
