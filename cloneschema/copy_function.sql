CREATE OR REPLACE FUNCTION edb_util.localcopyschema(
  source_schema_name text, target_schema_name text []
)
RETURNS boolean
AS $$
DECLARE snapshot_id integer;
  status_bool boolean;
  target text;
BEGIN
  FOREACH target in ARRAY target_schema_name
  LOOP
    RAISE NOTICE 'COPYING SCHEMA % to %', source_schema_name, target;
    SELECT edb_util.copy_schema(source_schema_name, target)
      INTO status_bool;
    IF status_bool is FALSE THEN
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
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_schema(
  source_schema_name text, target_schema_name text
)
RETURNS boolean
AS $$
DECLARE status_bool boolean;
  snapshot_id integer;
BEGIN
  SELECT edb_util.copy_package(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy PACKAGE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_procedure(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy PROCEDURE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_function(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy FUNCTION from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_enum(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy ENUM from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_datatype(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy DATATYPE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_table_simple(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy TABLE from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_table_data(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy TABLE DATA from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_table_constraint(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy TABLE CONSTRAINT from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_table_index(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy TABLE INDEX from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_table_trigger(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy TABLE TRIGGER from % to %. ROLLING BACK CHANGES'
      , source_schema_name, target_schema_name;
    RETURN FALSE;
  END IF;

  SELECT edb_util.copy_view(source_schema_name, target_schema_name)
    INTO status_bool;
  IF status_bool is FALSE THEN
    RAISE NOTICE 'Failed to copy VIEW from % to %. ROLLING BACK CHANGES'
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
$$ LANGUAGE plpgsql VOLATILE
;
