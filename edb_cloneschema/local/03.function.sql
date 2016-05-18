CREATE OR REPLACE FUNCTION edb_util.copy_package(
  source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
)
RETURNS boolean AS $$
DECLARE rec record;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT replace(
      pg_catalog.edb_get_packagedef(n.oid)
      , source_schema || '.', target_schema || '.'
    ) as decl
      , n.nspname as name
      from pg_catalog.pg_namespace as n
     WHERE n.nspparent = source_schema::regnamespace
       and n.nspobjecttype = 0
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'PACKAGE', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

-- pg_proc protype 0 = function, 1 = procedure, 2 = trigger
CREATE OR REPLACE FUNCTION edb_util.copy_function(
  source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
)
RETURNS boolean AS $$
DECLARE rec record;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT replace(
        pg_catalog.pg_get_functiondef(p.oid)
        , source_schema || '.', target_schema || '.'
      ) as decl
      , p.proname as name
      from pg_catalog.pg_proc as p
     WHERE p.pronamespace = source_schema::regnamespace
       and p.protype in ('0'::"char", '2'::"char")
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'FUNCTION', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_procedure(
  source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
)
RETURNS boolean AS $$
DECLARE rec record;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT replace(
        pg_catalog.pg_get_functiondef(p.oid)
        , source_schema || '.', target_schema || '.'
      ) as decl
      , p.proname as name
      from pg_catalog.pg_proc as p
     WHERE p.pronamespace = source_schema::regnamespace
       and p.protype = '1'::"char"
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'PROCEDURE', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;