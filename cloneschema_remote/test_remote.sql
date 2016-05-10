CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE EXTENSION IF NOT EXISTS dblink;
--
-- CREATE FOREIGN DATA WRAPPER postgres_fdw;

CREATE SERVER kronos_test FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (hostaddr '10.0.0.5', dbname 'kronos')
;

CREATE ROLE target LOGIN PASSWORD 'target-pass'
;
CREATE USER MAPPING FOR target SERVER kronos_test
  OPTIONS (user 'tkcsowner', password 'some-password')
;
GRANT USAGE ON FOREIGN SERVER kronos_test TO target
;

DROP SCHEMA IF EXISTS target CASCADE;

CREATE SCHEMA target AUTHORIZATION target;

CREATE USER MAPPING FOR enterprisedb SERVER kronos_test
  OPTIONS (user 'tkcsowner', password 'some-password')
--  OPTIONS (user 'enterprisedb', password 'some-password')
;
GRANT USAGE ON FOREIGN SERVER kronos_test TO enterprisedb
;
