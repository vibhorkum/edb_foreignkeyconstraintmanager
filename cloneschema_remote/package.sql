CREATE OR REPLACE FUNCTION edb_util.get_remote_package_declaration(
  foreign_server_name text, relid oid
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
    SELECT decl from dblink(connection_name
      , transaction_header
        || 'SELECT pg_catalog.edb_get_packagedef('
          || relid::text || ');'
      ) as rmot(decl text)
  );

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_remote_package(
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
  PERFORM set_config(
    'search_path', target_schema || ',public', FALSE);
  connection_name := md5(random()::text);
  PERFORM dblink_connect(connection_name, foreign_server_name);

  transaction_header := 'BEGIN ISOLATION LEVEL REPEATABLE READ; '
    || CASE when snapshot_id > ''
      then format('SET TRANSACTION SNAPSHOT %L; ', snapshot_id) else '' END
    ;

  FOR rec in
    SELECT replace(
      edb_util.get_remote_package_declaration(
        foreign_server_name, rmot.oid, snapshot_id
      ), source_schema || '.', target_schema || '.'
    ) as decl
    , rmot.name
    FROM dblink(connection_name
      , transaction_header || format(
        'SELECT n.oid, n.nspname from pg_catalog.pg_namespace as n
        WHERE n.nspobjecttype = 0 AND n.nspparent = %L::regnamespace;'
        , source_schema)
    ) as rmot(oid oid, name text)
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'PACKAGE', FALSE, verbose_bool)
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
