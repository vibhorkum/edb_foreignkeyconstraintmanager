CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE EXTENSION IF NOT EXISTS dblink;

CREATE SCHEMA IF NOT EXISTS edb_util AUTHORIZATION enterprisedb;

CREATE OR REPLACE TYPE edb_util.remote_snapshot_ret_type AS (
  connection_name text, snapshot_id text
);

CREATE OR REPLACE FUNCTION edb_util.get_remote_snapshot_id(
  foreign_server_name text
)
RETURNS edb_util.remote_snapshot_ret_type
AS $$
DECLARE snapshot_id text;
  connection_name text;
BEGIN
  connection_name := md5(random()::text);

  PERFORM dblink_connect(connection_name, foreign_server_name);
  SELECT rmot.snapshot_id INTO snapshot_id
    FROM dblink(connection_name
      , 'BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ; SELECT pg_export_snapshot();'
    ) as rmot(snapshot_id text)
  ;

  RETURN (connection_name, snapshot_id);
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.exists_remote_schema(
  foreign_server_name text, source_schema text
)
-- return TRUE if source_schema exists on foreign server; else FALSE
RETURNS boolean AS $$
DECLARE ret boolean;
  connection_name text;
BEGIN
  connection_name := md5(random()::text);

  PERFORM dblink_connect(connection_name, foreign_server_name);
  ret := (
    SELECT * FROM dblink(connection_name
      , format('SELECT EXISTS (
        SELECT 1 from pg_namespace WHERE nspname = %L
      );', source_schema)
    ) as rmot(does_exist boolean)
  );

  PERFORM dblink_disconnect(connection_name);
  RETURN ret;
END;
$$ LANGUAGE plpgsql VOLATILE
;

-- validate that no table has a foreign key that references a different tablespace

-- validate remote languages
-- SELECT DISTINCT(lanname) from pg_catalog.pg_language as l
--   JOIN pg_catalog.pg_proc as p on l.oid = p.prolang
--  WHERE p.pronamespace = source_schema::regnamespace

CREATE OR REPLACE FUNCTION edb_util.validate_remote_tablespace(
  foreign_server_name text, source_schema text
)
-- returns TRUE if all tablespaces needed for source_schema on remote server
--  are also present on local host; else FALSE.
RETURNS boolean AS $$
DECLARE ret boolean;
  connection_name text;
BEGIN
  connection_name := md5(random()::text);

  PERFORM dblink_connect(connection_name, foreign_server_name);
  ret := (
    with remote_tablespace as (
      SELECT rmot.spcname from dblink(connection_name
        , format('SELECT DISTINCT t.spcname
          from pg_catalog.pg_tablespace as t
          join pg_catalog.pg_class as c
            on c.reltablespace = t.oid
         WHERE c.relnamespace = %L::regnamespace;'
        , source_schema)
       ) as rmot(spcname text)
    )
  SELECT CASE when EXISTS (
    SELECT * from remote_tablespace as r
     where NOT EXISTS ( SELECT 1
      from pg_catalog.pg_tablespace where spcname = r.spcname
      )
    ) then FALSE else TRUE END
  );

  PERFORM dblink_disconnect(connection_name);
  RETURN ret;
END;
$$ LANGUAGE plpgsql VOLATILE
;
