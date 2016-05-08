CREATE OR REPLACE FUNCTION edb_util.localcopyschema(
  source_schema_name text, target_schema_name text []
  , verbose_bool boolean DEFAULT FALSE
  , on_tblspace boolean DEFAULT FALSE
)
RETURNS boolean
AS $$
DECLARE snapshot_id integer;
  status_bool boolean;
  target text;
BEGIN
  IF NOT EXISTS ( SELECT 1 from pg_catalog.pg_namespace
    where nspname = source_schema_name and nspparent = 0
  ) THEN
    RAISE NOTICE 'Specified source catalog % does not exist.', source_schema_name;
    RETURN FALSE;
  END IF;

  -- check if source schema contains FK that references other schema.
  -- alter to only use source schema once, and learn from copy attempts.

  FOREACH target in ARRAY target_schema_name
  LOOP
    RAISE NOTICE 'COPYING SCHEMA % to %', source_schema_name, target;
    SELECT edb_util.copy_schema(source_schema_name, target, on_tblspace)
      INTO status_bool;
    IF NOT status_bool THEN
      RAISE NOTICE 'Failed to copy SCHEMA % to %', source_schema_name, target;
    END IF;
  END LOOP;

  RETURN TRUE;

EXCEPTION WHEN others THEN
  RAISE NOTICE 'Encoutered exception in copy_schema.';
  RAISE NOTICE 'ROLLING BACK CHANGES';
  RAISE NOTICE '% %', sqlstate, sqlerrm;

  RETURN FALSE;

END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_schema(
  source_schema_name text, target_schema_name text
  , verbose_bool boolean DEFAULT FALSE
  , on_tblspace boolean DEFAULT FALSE
)
RETURNS boolean
AS $$
DECLARE status_bool boolean;
BEGIN
  IF NOT EXISTS ( SELECT 1 from pg_catalog.pg_namespace
    where nspname = source_schema_name and nspparent = 0
  ) THEN
    RAISE NOTICE 'Specified source catalog % does not exist.', source_schema_name;
    RETURN FALSE;
  END IF;

  IF NOT EXISTS ( SELECT 1 from pg_catalog.pg_namespace
    where nspname = target_schema_name and nspparent = 0
  ) THEN
    RAISE NOTICE 'Specified target catalog % does not exist. CREATING', source_schema_name;
    EXECUTE format('CREATE SCHEMA %s;', target_schema_name);
  END IF;

  EXECUTE 'TRUNCATE TABLE edb_util.tracking;';

  -- check if FK in source schema references object in other schema

  -- enums, other data types, and sequences will not have dependencies
  -- copy these first
  SELECT edb_util.copy_enum(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy ENUM from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_datatype(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy DATA TYPE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_sequence(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy SEQUENCE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  -- table currently includes DEFAULT declaration, may need functions,
  -- or split DEFAULTs to seperate function
  SELECT edb_util.copy_table_simple(
    source_schema_name, target_schema_name, on_tblspace, verbose_bool
  ) INTO status_bool;

  -- verify that no table creates fail, then add this back in.
  -- IF NOT status_bool THEN
  --   RAISE NOTICE 'Failed to copy TABLE from % to %. ROLLING BACK CHANGES'
  --     , source_schema_name, target_schema_name;
  --   RETURN FALSE;
  -- END IF;

  -- first pass at views (can be required for packages)
  -- views, packages, procs, and functions can depend on eachother, but only
  -- views are tracked in pg_depend. try creating in batch, and logging
  -- failures, then creating failed objects recursively.

  SELECT edb_util.copy_view(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
    -- Could probably ignore status_bool for these with PERFORM.

  SELECT edb_util.copy_package(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;

  SELECT edb_util.copy_procedure(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;

  SELECT edb_util.copy_function(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;

  -- SELECT edb_util.resolve(target_schema_name)
  --   INTO status_bool;

  -- all objects should now exist. Partition any tables setup with EPAS syntax
  SELECT edb_util.copy_table_partitions(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TABLE PARTITIONS from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  -- copy table data
  SELECT edb_util.copy_table_data(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TABLE DATA from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  -- create constraints, indexes, triggers, rules
  SELECT edb_util.copy_table_constraint(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TABLE CONSTRAINT from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_table_index(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TABLE INDEX from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_table_trigger(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TABLE INDEX from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_table_rule(
    source_schema_name, target_schema_name, verbose_bool
  ) INTO status_bool;
  IF NOT status_bool THEN
    RAISE NOTICE 'Failed to copy TABLE INDEX from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  RETURN TRUE;

EXCEPTION WHEN others THEN
  RAISE NOTICE 'Encoutered exception in copy_schema.';
  RAISE NOTICE 'ROLLING BACK CHANGES';
  RAISE NOTICE '% %', sqlstate, sqlerrm;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;
