CREATE OR REPLACE FUNCTION edb_util.get_remote_sequence_declaration(
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
    SELECT 'CREATE SEQUENCE ' || rmot.name
      || ' INCREMENT BY ' || rmot.increment
      || ' MINVALUE ' || rmot.minimum_value
      || ' MAXVALUE ' || rmot.maximum_value
      || ' START WITH ' || rmot.next_value
      || CASE WHEN rmot.cycle_option is FALSE
        then ' NO CYCLE' else ' CYCLE' END
      || ';'
    FROM dblink(connection_name
      , transaction_header || format(
'SELECT quote_ident(c.relname) as name
  , parm.increment::text as increment
  , parm.minimum_value::text as minimum_value
  , parm.maximum_value::text as maximum_value
  , pg_catalog.nextval(c.oid)::text as next_value
  , parm.cycle_option
FROM pg_catalog.pg_class as c
JOIN LATERAL pg_catalog.pg_sequence_parameters(c.oid) as parm on 1=1
WHERE c.oid = %L;'
      , relid)
    ) as rmot(name text, increment text
      , minimum_value text, maximum_value text, next_value text
      , cycle_option boolean
    )
  );

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN return_decl;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_remote_sequence(
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
      edb_util.get_remote_sequence_declaration(
        foreign_server_name, rmot.relid, snapshot_id
      ), source_schema || '.', target_schema || '.'
    ) as decl
    , rmot.name
    FROM dblink(connection_name
      , transaction_header || format(
'SELECT c.oid, c.relname
from pg_catalog.pg_class as c
WHERE c.relkind = ''S''::"char"
  and c.relnamespace = %L::regnamespace;'
        , source_schema)
      ) as rmot(relid oid, name text)
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'SEQUENCE', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);
  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE
;
