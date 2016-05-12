CREATE OR REPLACE FUNCTION edb_util.get_remote_constraint_declaration(
  foreign_server_name text
  , relname text, constraintid oid
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
    SELECT format('ALTER TABLE %I ADD CONSTRAINT %I '
      , relname, name
    ) || rmot.decl || ';'
    FROM dblink(connection_name
      , transaction_header || format(
        'SELECT cn.conname::text, pg_get_constraintdef(cn.oid)
        from pg_constraint as cn WHERE cn.oid = %L;'
        , constraintid
      )
    ) as rmot(name text, decl text)
  );

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_remote_table_constraint(
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

  -- exclude FK in first pass, as they require a unique constraint target on destination table
  FOR rec in
    SELECT replace(
      edb_util.get_remote_constraint_declaration(
        foreign_server_name, rmot.relname, rmot.constraintid, snapshot_id
      ), source_schema || '.', target_schema || '.'
    ) as decl
    , rmot.name
    FROM dblink(connection_name
      , transaction_header || format(
'SELECT c.relname, cn.conname, cn.oid
FROM pg_catalog.pg_class as c
LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
where c.relnamespace = %L::regnamespace
  and cn.contype <> ''f''::"char"
;'
      , source_schema)
    ) as rmot(relname text, name text, constraintid oid)
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'TABLE CONSTRAINT', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  PERFORM dblink(connection_name, 'COMMIT;');
  --PERFORM dblink_disconnect(connection_name)
  -- now create FK
  FOR rec in
    SELECT replace(
      edb_util.get_remote_constraint_declaration(
        foreign_server_name, rmot.relname, rmot.constraintid, snapshot_id
      ), source_schema || '.', target_schema || '.'
    ) as decl
    , rmot.name
    FROM dblink(connection_name
      , transaction_header || format(
'SELECT c.relname, cn.conname, cn.oid
FROM pg_catalog.pg_class as c
LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
where c.relnamespace = %L::regnamespace
  and cn.contype = ''f''::"char"
;'
      , source_schema)
    ) as rmot(relname text, name text, constraintid oid)
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'TABLE FK CONSTRAINT', FALSE, verbose_bool)
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
