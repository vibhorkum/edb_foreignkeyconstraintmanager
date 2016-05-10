CREATE OR REPLACE FUNCTION edb_util.get_remote_datatype_declaration(
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
    with attrs as (
      SELECT * from dblink(connection_name
        , format(transaction_header
          || 'SELECT quote_ident(c.relname) as relname
              , quote_ident(a.attname) as attname
              , format_type(a.atttypid, a.atttypmod) as atttypdecl
            from pg_catalog.pg_class as c
          LEFT join pg_catalog.pg_attribute as a on c.oid = a.attrelid
          WHERE c.oid = %L
            and a.attnum > 0
            and NOT a.attisdropped
          ORDER BY a.attnum;'
        , relid)) as rmot(relname text, attname text, atttypdecl text)
    )
    SELECT 'CREATE TYPE ' || quote_ident(a.relname)
      || ' AS (' || string_agg(a.attname || ' ' || a.atttypdecl,', ') || ');'
      from attrs as a
    GROUP BY a.relname
  );

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_remote_datatype(
  foreign_server_name text, source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
  , snapshot_id text DEFAULT ''
)
RETURNS boolean AS $$
DECLARE rec record;
  connection_name text;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
BEGIN
  -- append public for dblink PERFORM steps
  PERFORM set_config(
    'search_path', target_schema || ',public', FALSE);
  connection_name := md5(random()::text);
  PERFORM dblink_connect(connection_name, foreign_server_name);

  FOR rec in
    SELECT replace(
        edb_util.get_remote_datatype_declaration(
          foreign_server_name, rmot.relid, snapshot_id)
        , source_schema || '.', target_schema || '.'
      ) as decl
      , rmot.name
      FROM dblink(connection_name
        , format('SELECT c.oid, c.relname as name
          from pg_class as c
         WHERE c.relkind = ''c''
           and c.relnamespace = %L::regnamespace;'
        , source_schema)
      ) as rmot(relid oid, name text)
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'DATATYPE', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  PERFORM dblink_disconnect(connection_name);
  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE
;
