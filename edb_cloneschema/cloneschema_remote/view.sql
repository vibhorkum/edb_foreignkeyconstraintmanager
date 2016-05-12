CREATE OR REPLACE FUNCTION edb_util.get_remote_view_declaration(
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
        || 'SELECT pg_catalog.pg_get_viewdef('
          || relid::text || ');'
      ) as rmot(decl text)
  );

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_remote_view_dependency_order(
  foreign_server_name text, source_schema text
  , snapshot_id text DEFAULT ''
)
RETURNS TABLE (relid oid, relname text, ancestors integer)
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
  CREATE TEMPORARY TABLE ret_table (
    relid oid, relname text, ancestors integer
  ) ON COMMIT DROP;

  INSERT INTO ret_table
  SELECT * from dblink(connection_name
    , transaction_header || format(
'with RECURSIVE viewing AS (
  SELECT c.oid as relid, c.relname, NULL::oid as refobjid, 0 as ancestors
    from pg_catalog.pg_class as c WHERE c.relkind = ''v''::"char"
     AND c.relnamespace = %L::regnamespace
  UNION ALL
  SELECT DISTINCT c.oid, c.relname, d.refobjid
    , viewing.ancestors + 1
    from pg_catalog.pg_depend as d
    join viewing on d.refobjid = viewing.relid
    join pg_catalog.pg_rewrite as rw on d.objid = rw.oid
    join pg_catalog.pg_class as c
      on rw.ev_class = c.oid and c.relkind = ''v''::"char"
  WHERE c.oid <> d.refobjid
) SELECT relid, relname, max(ancestors) as ancestors
FROM viewing GROUP BY relid, relname
ORDER BY ancestors;'
    , source_schema)
  ) as rmot(relid oid, relname text, ancestors integer)
  ;

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN QUERY SELECT * FROM ret_table;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_remote_view(
  foreign_server_name text, source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
  , snapshot_id text DEFAULT ''
)
RETURNS boolean AS $$
DECLARE rec record;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
BEGIN
  -- append public for dblink PERFORM steps
  PERFORM pg_catalog.set_config(
    'search_path', format('%I,%I', target_schema, 'public'), FALSE
  );

  FOR rec in
    SELECT format('CREATE VIEW %I AS ', relname)
      || replace(
        edb_util.get_remote_view_declaration(
          foreign_server_name, relid, snapshot_id
        ), source_schema || '.', target_schema || '.'
      ) || ';' as decl
      , relname as name
      from edb_util.get_remote_view_dependency_order(
        foreign_server_name, source_schema, snapshot_id
      )
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'VIEW', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;
