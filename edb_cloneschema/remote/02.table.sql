CREATE OR REPLACE FUNCTION edb_util.get_remote_table_declaration(
  foreign_server_name text, relid oid
  , on_tblspace boolean DEFAULT FALSE
  , snapshot_id text DEFAULT ''
)
RETURNS text
AS $$
DECLARE return_decl text;
  connection_name text;
  transaction_header text;
BEGIN
  connection_name := md5(random()::text);
  PERFORM dblink_connect(connection_name, foreign_server_name);

  transaction_header := 'BEGIN ISOLATION LEVEL REPEATABLE READ; '
    || CASE when snapshot_id > ''
      then format('SET TRANSACTION SNAPSHOT %L; ', snapshot_id) else '' END
    ;

  return_decl := (
    with attrs as (
      SELECT * from dblink(connection_name
        , transaction_header || format(
'SELECT quote_ident(c.relname) as relname
    , quote_ident(a.attname) as attname
    , a.attnotnull
    , format_type(a.atttypid, a.atttypmod) as atttypdecl
    , (SELECT cl.collname
      FROM pg_catalog.pg_collation as cl
      WHERE a.attcollation > 0
        AND cl.oid = a.attcollation
        AND cl.collname <> ''default''
    ) as attcollation
  from pg_catalog.pg_class as c
LEFT join pg_catalog.pg_attribute as a on c.oid = a.attrelid
WHERE c.oid = %L
  and a.attnum > 0
  and NOT a.attisdropped
ORDER BY a.attnum;'
        , relid)
    ) as rmot(relname text, attname text
        , attnotnull boolean, atttypdecl text, attcollation text)
  )
  , rel as (
    SELECT rmot.relname
      , CASE rmot.relpersistence
        WHEN 'u' THEN 'UNLOGGED ' else '' END as persistence
      , CASE when on_tblspace and rmot.spcname is NOT NULL
          then ' TABLESPACE ' || rmot.spcname else '' END as tblspace
      from dblink(connection_name, format(
'BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT quote_ident(c.relname) as relname
  , c.relpersistence
  , t.spcname
FROM pg_catalog.pg_class as c
LEFT join pg_catalog.pg_tablespace as t on c.reltablespace = t.oid
WHERE c.oid = %L;'
      , relid)
    ) as rmot(relname text, relpersistence text, spcname text)
  )
  SELECT 'CREATE ' || r.persistence
    || 'TABLE ' || r.relname
    || ' ('
      || string_agg(
        a.attname || ' ' || a.atttypdecl
      || CASE when a.attcollation is NULL then ''
          else ' COLLATE ' || a.attcollation END
      || CASE when a.attnotnull then ' NOT NULL' else '' END
      , ', ')
    || ')' || r.tblspace || ';'
    from attrs as a
    JOIN rel as r USING (relname)
  GROUP BY r.persistence, r.relname, r.tblspace
);

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_remote_table_simple(
  foreign_server_name text, source_schema text, target_schema text
  , on_tblspace boolean DEFAULT FALSE
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
      edb_util.get_remote_table_declaration(
        foreign_server_name, rmot.oid, on_tblspace
        , snapshot_id
      ), source_schema || '.', target_schema || '.'
    ) as decl
    , rmot.name
    from dblink(connection_name, format(
'SELECT c.oid, c.relname as name
  from pg_catalog.pg_class as c
 WHERE c.relkind = ''r''::"char"
   and c.relnamespace = %L::regnamespace'
      , source_schema)
    ) as rmot(oid oid, name text)
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'TABLE', FALSE, verbose_bool)
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
