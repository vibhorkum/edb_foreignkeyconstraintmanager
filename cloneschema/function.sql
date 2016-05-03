
-- must amend to ignore functions that are part of a package.
-- Import package and package body seperately
CREATE OR REPLACE FUNCTION edb_util.copy_function(
  source_schema text, target_schema text
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT pg_catalog.pg_get_functiondef(p.oid) as decl
      from pg_catalog.pg_proc as p
     WHERE EXISTS ( SELECT 1
         from pg_namespace WHERE oid = p.pronamespace
          and nspname = source_schema
         )
  LOOP
    RAISE NOTICE '%', replace(rec.decl, source_schema, target_schema);
    EXECUTE replace(rec.decl, source_schema, target_schema);
  END LOOP;

-- EXCEPTION WHEN duplicate_object THEN
-- WHEN others THEN
--   RETURN FALSE;
-- END;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql VOLATILE
;
