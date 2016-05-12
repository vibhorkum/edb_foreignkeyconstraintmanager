CREATE OR REPLACE FUNCTION edb_util.copy_remote_table_rule(
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
        rmot.decl, source_schema || '.', target_schema || '.'
    ) as decl
    , rmot.name as name
    FROM dblink(connection_name
      , transaction_header || format(
'SELECT r.definition, r.rulename
FROM pg_catalog.pg_rules as r
WHERE r.schemaname = %L;'
        , source_schema)
    ) as rmot(decl text, name text)
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'RULE', FALSE, verbose_bool)
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
