CREATE OR REPLACE FUNCTION edb_util.get_remote_table_fdw_definition(
  foreign_server_name text, relid oid, foreign_table_name text
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
          || 'SELECT c.relname as relname
              , quote_ident(c.relnamespace::regnamespace::text) as relnamespace
              , quote_ident(a.attname) as attname
              , format_type(a.atttypid, a.atttypmod) as atttypdecl
            from pg_catalog.pg_class as c
          LEFT join pg_catalog.pg_attribute as a on c.oid = a.attrelid
          WHERE c.oid = %L
            and a.attnum > 0
            and NOT a.attisdropped
          ORDER BY a.attnum;'
        , relid)
      ) as rmot(relname text, relnamespace text
        , attname text, atttypdecl text)
    )
    SELECT 'CREATE FOREIGN TABLE ' || quote_ident(foreign_table_name)
      || ' ('
        || string_agg(
          a.attname || ' ' || a.atttypdecl
        , ', ')
      || ') SERVER ' || quote_ident(foreign_server_name)
      || format(' OPTIONS (schema_name %L, table_name %L);'
          , a.relnamespace, a.relname)
      from attrs as a
    GROUP BY a.relnamespace, a.relname
  );

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_remote_table_insert_select(
  foreign_server_name text
  --, source_schema_name text, target_schema_name text
  , relid oid, foreign_table_name text
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
        , relid)
      ) as rmot(relname text, attname text, atttypdecl text)
    )
    SELECT 'INSERT INTO ' || attrs.relname
      || ' SELECT ' || string_agg(attrs.attname, ', ')
      || ' from ' || quote_ident(foreign_table_name) || ';'
      from attrs
    GROUP BY attrs.relname
  );

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_remote_table_data(
  foreign_server_name text
  , source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
  , snapshot_id text DEFAULT ''
)
RETURNS boolean AS $$
DECLARE rec record;
  connection_name text;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
  foreign_table_name text;
  fdw_decl text;
  insert_select_statement text;
BEGIN
  -- append public for dblink PERFORM steps
  PERFORM set_config(
    'search_path', target_schema || ',public', FALSE);
  connection_name := md5(random()::text);
  PERFORM dblink_connect(connection_name, foreign_server_name);

  FOR rec in
    SELECT rmot.relid, rmot.relname
      from dblink(connection_name
        , format('SELECT c.oid, c.relname from pg_catalog.pg_class as c
    WHERE c.relkind = ''r''::"char" AND c.relnamespace = %L::regnamespace;'
    , source_schema)
  ) as rmot(relid oid, relname text)
  LOOP
    RAISE NOTICE 'COPYING TABLE DATA to %;', rec.relname;
    foreign_table_name := md5(random()::text);

    fdw_decl := replace(edb_util.get_remote_table_fdw_definition(
      foreign_server_name, rec.relid, foreign_table_name, snapshot_id)
      , source_schema || '.', target_schema || '.'
    );

    insert_select_statement := edb_util.get_remote_table_insert_select(
      foreign_server_name, rec.relid, foreign_table_name, snapshot_id
    );

    IF verbose_bool THEN
      RAISE NOTICE '%', fdw_decl;
      RAISE NOTICE '%', insert_select_statement;
    END IF;

    EXECUTE fdw_decl;
    EXECUTE insert_select_statement;
    EXECUTE format('DROP FOREIGN TABLE %I;', foreign_table_name);
  END LOOP;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;
