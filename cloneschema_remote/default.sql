CREATE OR REPLACE FUNCTION edb_util.get_remote_default_declaration(
  foreign_server_name text
  , attrelid oid, attname text
  , snapshot_id text DEFAULT ''
)
RETURNS text
AS $$
DECLARE return_decl text;
  connection_name text;
  transaction_header text;
BEGIN
  connection_name := md5(random()::text);

  transaction_header := 'BEGIN ISOLATION LEVEL REPEATABLE READ; '
    || CASE when snapshot_id > ''
      then format('SET TRANSACTION SNAPSHOT %L; ', snapshot_id) else '' END
    ;

  PERFORM dblink_connect(connection_name, foreign_server_name);
  return_decl := (
    SELECT format('ALTER TABLE %I ALTER COLUMN %I SET DEFAULT '
      , rmot.relname, rmot.name
    ) || rmot.decl || ';'
    FROM dblink(connection_name
      , transaction_header || format(
'SELECT c.relname, a.attname
  , substring(pg_catalog.pg_get_expr(d.adbin, d.adrelid) for 128)
FROM pg_catalog.pg_class as c
join pg_catalog.pg_attrdef as d
  on c.oid = d.adrelid
join pg_catalog.pg_attribute as a
  on d.adrelid = a.attrelid AND d.adnum = a.attnum
WHERE a.atthasdef AND a.attrelid = %L AND a.attname = %L;'
      , attrelid, attname
      )
    ) as rmot(relname text, name text, decl text)
  );

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_remote_table_default(
  foreign_server_name text, source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
  , snapshot_id text DEFAULT ''
)
RETURNS boolean AS $$
DECLARE rec record;
  connection_name text;
  transaction_header text;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
BEGIN
  -- append public for dblink PERFORM steps
  PERFORM pg_catalog.set_config(
    'search_path', format('%I,%I', target_schema, 'public'), FALSE
  );
  connection_name := md5(random()::text);
  PERFORM dblink_connect(connection_name, foreign_server_name);

  transaction_header := 'BEGIN ISOLATION LEVEL REPEATABLE READ; '
    || CASE when snapshot_id > ''
      then format('SET TRANSACTION SNAPSHOT %L; ', snapshot_id) else '' END
    ;

  FOR rec in
    SELECT replace(
        edb_util.get_remote_default_declaration(
          foreign_server_name, rmot.attrelid, rmot.attname, snapshot_id
        ), source_schema || '.', target_schema || '.'
      ) as decl
      , rmot.relname || '.' || rmot.attname as name
    FROM dblink(connection_name
        , transaction_header || format(
'SELECT c.relname, a.attrelid, a.attname
from pg_catalog.pg_attribute as a
join pg_catalog.pg_class as c on a.attrelid = c.oid
WHERE a.atthasdef AND a.attnum > 0
  and NOT a.attisdropped
  and c.relnamespace = %L::regnamespace;'
          , source_schema)
    ) as rmot(relname text, attrelid oid, attname text)
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'DEFAULT', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;
