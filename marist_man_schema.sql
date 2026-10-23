PRAGMA foreign_keys = ON;


CREATE TABLE config (
    key   TEXT PRIMARY KEY,
    value REAL NOT NULL
);
INSERT INTO config VALUES
 ('service_hours_required', 20),
 ('attendance_min_pct',     85),
 ('minor_pastoral_max_per_term', 2),
 ('effort_avg_min_exclusive',   3.7),
 ('mass_attendance_min_pct',    80);  

-- ---------- People ---------------------------------------------------
CREATE TABLE teachers (
    teacher_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name     TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE,         -- school email = login
    role          TEXT NOT NULL DEFAULT 'Teacher'
                  CHECK (role IN ('Teacher','Deputy Principal')),
    password_hash TEXT NOT NULL                 -- never store plain text
);

CREATE TABLE students (
    student_id     TEXT PRIMARY KEY,            -- e.g. S1001
    full_name      TEXT NOT NULL,
    email          TEXT NOT NULL UNIQUE,        -- school email = login
    year_level     INTEGER NOT NULL CHECK (year_level BETWEEN 9 AND 13),
    form_class     TEXT NOT NULL,               -- e.g. 10B (requested by stakeholder)
    attendance_pct REAL NOT NULL DEFAULT 100 CHECK (attendance_pct BETWEEN 0 AND 100),
    re_status      TEXT NOT NULL DEFAULT 'Active'
                   CHECK (re_status IN ('Active','Some','Low')),
    mass_attended  INTEGER NOT NULL DEFAULT 0,
    mass_total     INTEGER NOT NULL DEFAULT 0,
    badge_status   TEXT NOT NULL DEFAULT 'none'
                   CHECK (badge_status IN ('none','awarded','withheld')),
    badge_reason   TEXT,
    badge_decided_by INTEGER REFERENCES teachers(teacher_id),
    password_hash  TEXT NOT NULL
);

-- ---------- Integrity data (copied from KAMAR / teachers) -------------
CREATE TABLE pastoral_entries (
    entry_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id TEXT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    term       INTEGER NOT NULL CHECK (term BETWEEN 1 AND 4),
    entry_date TEXT NOT NULL,
    severity   TEXT NOT NULL CHECK (severity IN ('minor','major')),
    note       TEXT
);

CREATE TABLE effort_grades (
    grade_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id TEXT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    fortnight  INTEGER NOT NULL,
    grade      REAL NOT NULL CHECK (grade BETWEEN 1 AND 5),
    UNIQUE (student_id, fortnight)
);

-- ---------- Service ---------------------------------------------------
CREATE TABLE service_hours (
    submission_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id     TEXT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    form_class     TEXT NOT NULL,
    hours          REAL NOT NULL CHECK (hours > 0 AND hours <= 40),
    activity       TEXT NOT NULL,
    supervisor_email TEXT NOT NULL,
    submitted_on   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status         TEXT NOT NULL DEFAULT 'Pending Verification'
                   CHECK (status IN ('Pending Verification','Approved','Rejected')),
    reviewed_by    INTEGER REFERENCES teachers(teacher_id),
    reviewed_on    TEXT,
    reject_reason  TEXT
);

CREATE TABLE jobs (
    job_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT NOT NULL,
    description TEXT NOT NULL,
    hours       REAL NOT NULL,
    location    TEXT,
    event_date  TEXT,
    contact     TEXT,
    only_year   INTEGER CHECK (only_year BETWEEN 9 AND 13),  -- NULL = all years
    posted_by   INTEGER REFERENCES teachers(teacher_id)
);

CREATE TABLE job_signups (
    signup_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id     INTEGER NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
    student_id TEXT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    reason     TEXT,
    status     TEXT NOT NULL DEFAULT 'Applied'
               CHECK (status IN ('Applied','Accepted','Declined','Completed')),
    UNIQUE (job_id, student_id)
);

CREATE INDEX idx_hours_student  ON service_hours(student_id, status);
CREATE INDEX idx_pastoral       ON pastoral_entries(student_id, term, severity);
CREATE INDEX idx_students_form  ON students(form_class);

-- ---------- Views: the "single transparent interface" -----------------
CREATE VIEW v_service_totals AS
SELECT s.student_id,
       COALESCE(SUM(CASE WHEN h.status = 'Approved'             THEN h.hours END), 0) AS approved_hours,
       COALESCE(SUM(CASE WHEN h.status = 'Pending Verification' THEN h.hours END), 0) AS pending_hours
FROM students s
LEFT JOIN service_hours h ON h.student_id = s.student_id
GROUP BY s.student_id;

CREATE VIEW v_effort_avg AS
SELECT student_id, ROUND(AVG(grade), 2) AS effort_avg
FROM effort_grades
GROUP BY student_id;

CREATE VIEW v_worst_term_pastoral AS
SELECT student_id, MAX(n) AS max_minor_in_a_term
FROM (SELECT student_id, term, COUNT(*) AS n
      FROM pastoral_entries WHERE severity = 'minor'
      GROUP BY student_id, term)
GROUP BY student_id;

CREATE VIEW v_marist_man_progress AS
SELECT s.student_id, s.full_name, s.year_level, s.form_class,
       t.approved_hours, t.pending_hours,
       COALESCE(e.effort_avg, 0)               AS effort_avg,
       COALESCE(p.max_minor_in_a_term, 0)      AS worst_term_minor,
       s.attendance_pct,
       -- Faith
       (s.re_status = 'Active'
        AND s.mass_total > 0
        AND 100.0 * s.mass_attended / s.mass_total >=
            (SELECT value FROM config WHERE key = 'mass_attendance_min_pct')) AS faith_met,
       -- Integrity
       (s.attendance_pct >= (SELECT value FROM config WHERE key = 'attendance_min_pct')
        AND COALESCE(p.max_minor_in_a_term, 0) <=
            (SELECT value FROM config WHERE key = 'minor_pastoral_max_per_term')
        AND COALESCE(e.effort_avg, 0) >
            (SELECT value FROM config WHERE key = 'effort_avg_min_exclusive')) AS integrity_met,
       -- Service
       (t.approved_hours >= (SELECT value FROM config WHERE key = 'service_hours_required')) AS service_met,
       s.badge_status
FROM students s
JOIN v_service_totals t ON t.student_id = s.student_id
LEFT JOIN v_effort_avg e ON e.student_id = s.student_id
LEFT JOIN v_worst_term_pastoral p ON p.student_id = s.student_id;

-- ---------- Sample data -----------------------------------------------
INSERT INTO teachers (full_name, email, role, password_hash) VALUES
 ('Mr Ardern',  'ardern@stjohns.example.nz', 'Deputy Principal', 'HASH_ME'),
 ('Ms Johnson', 'johnson@stjohns.example.nz','Teacher',          'HASH_ME');

INSERT INTO students (student_id, full_name, email, year_level, form_class,
                      attendance_pct, re_status, mass_attended, mass_total, password_hash) VALUES
 ('S1001','Aroha Ngata',  'aroha@stjohns.example.nz',  9, '9A', 94,'Active', 9,10,'HASH_ME'),
 ('S1003','Tane Rewi',    's1003@stjohns.example.nz', 11,'11C', 96,'Active',10,10,'HASH_ME'),
 ('S1007','Noah Kingi',   'noah@stjohns.example.nz',  10,'10A', 86,'Active', 9,10,'HASH_ME');

INSERT INTO effort_grades (student_id, fortnight, grade) VALUES
 ('S1001',1,4),('S1001',2,4),('S1001',3,5),
 ('S1003',1,5),('S1003',2,4),('S1003',3,4),
 ('S1007',1,4),('S1007',2,4),('S1007',3,4);

INSERT INTO pastoral_entries (student_id, term, entry_date, severity, note) VALUES
 ('S1007',2,'2026-05-02','minor','Late to class'),
 ('S1007',2,'2026-05-14','minor','Uniform'),
 ('S1007',2,'2026-06-01','minor','No homework');

INSERT INTO service_hours (student_id, form_class, hours, activity, supervisor_email, status) VALUES
 ('S1001','9A', 6,'Weet-Bix programme','johnson@stjohns.example.nz','Approved'),
 ('S1001','9A', 3,'Library helper',     'johnson@stjohns.example.nz','Pending Verification'),
 ('S1003','11C',22,'SPCA volunteering', 'volunteer@spca.example.nz', 'Approved');

-- ---------- Queries the website runs ----------------------------------
-- Student dashboard (live progress for one student)
-- SELECT * FROM v_marist_man_progress WHERE student_id = 'S1001';

-- Teacher search + form class filter
-- SELECT * FROM v_marist_man_progress


-- Students who have met everything but are not yet confirmed
-- SELECT * FROM v_marist_man_progress
-- WHERE faith_met AND integrity_met AND service_met AND badge_status = 'none';

-- Approve a service submission
-- UPDATE service_hours SET status='Approved', reviewed_by=1, reviewed_on=CURRENT_TIMESTAMP
-- WHERE submission_id = 2;

-- Hours waiting for review, by form class
-- SELECT h.*, s.full_name FROM service_hours h JOIN students s USING (student_id)
-- WHERE h.status = 'Pending Verification' ORDER BY h.form_class, h.submitted_on;
