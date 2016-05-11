CREATE OR REPLACE FUNCTION edb_util.remotecopyschema(
  foreign_server_name text
  , source_schema_name text, target_schema_name text
  , verbose_bool boolean DEFAULT FALSE
  , on_tblspace boolean DEFAULT FALSE
)
RETURNS boolean
AS $$
DECLARE status_bool boolean;
  connection_name text;
  snapshot_id text;
BEGIN

  SELECT edb_util.exists_remote_schema(foreign_server_name, source_schema_name)
    INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Specified remote schema % does not exist on the foreign server %'
      , source_schema_name, foreign_server_name
      ;
    RETURN FALSE;
  END IF;

  IF on_tblspace THEN
    SELECT edb_util.validate_remote_tablespace(
      foreign_server_name, source_schema_name
    ) INTO status_bool;
    IF NOT status_bool THEN
      RAISE NOTICE 'Specified create objects on tablespaces, but all required tablespaces are not found.';
      RETURN FALSE;
    END IF;
  END IF;

  -- verify target exists. Attempt to create if not.
  IF NOT EXISTS ( SELECT 1 from pg_catalog.pg_namespace
    where nspname = target_schema_name and nspparent = 0
  ) THEN
    RAISE NOTICE 'Specified target catalog % does not exist.', target_schema_name;
    RAISE NOTICE 'ATTEMPTING TO CREATE';
    EXECUTE format('CREATE SCHEMA %s;', target_schema_name);
  END IF;

  EXECUTE 'TRUNCATE TABLE edb_util.tracking;';

  SELECT x.connection_name
    , x.snapshot_id
    from ( SELECT *
      from edb_util.get_remote_snapshot_id(foreign_server_name)
  ) as x
    INTO connection_name, snapshot_id
  ;

  SELECT edb_util.copy_remote_enum(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy ENUM from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_remote_datatype(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy DATA TYPE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_remote_sequence(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy SEQUENCE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_remote_table_simple(
    foreign_server_name
    , source_schema_name, target_schema_name
    , on_tblspace, verbose_bool
    , snapshot_id
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TABLE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  PERFORM edb_util.copy_remote_view(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  );

  PERFORM edb_util.copy_remote_package(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  );

  PERFORM edb_util.copy_remote_procedure(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  );

  PERFORM edb_util.copy_remote_function(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  );

  SELECT edb_util.copy_remote_table_data(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TABLE DATA from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  -- SELECT edb_util.copy_remote_table_constraint(
  --   foreign_server_name
  --   , source_schema_name, target_schema_name
  --   , verbose_bool, snapshot_id
  -- ) INTO status_bool;
  -- IF NOT status_bool THEN
  --   RAISE NOTICE 'Failed to copy TABLE CONSTRAINT from % to %. ROLLING BACK CHANGES'
  --     , source_schema_name, target_schema_name;
  --   RETURN FALSE;
  -- END IF;

  -- SELECT edb_util.copy_remote_table_default(
  --   foreign_server_name
  --   , source_schema_name, target_schema_name
  --   , verbose_bool, snapshot_id
  -- ) INTO status_bool;
  -- IF NOT status_bool THEN
  --   RAISE NOTICE 'Failed to copy TABLE CONSTRAINT from % to %. ROLLING BACK CHANGES'
  --     , source_schema_name, target_schema_name;
  --   RETURN FALSE;
  -- END IF;

  SELECT edb_util.copy_remote_table_index(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy INDEX from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_remote_table_trigger(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TRIGGER from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_remote_table_rule(
    foreign_server_name
    , source_schema_name, target_schema_name
    , verbose_bool, snapshot_id
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TRIGGER from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  PERFORM dblink(connection_name, 'COMMIT;');
  PERFORM dblink_disconnect(connection_name);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

-- SELECT edb_util.remotecopyschema('kronos_test','tkcsowner','target');
