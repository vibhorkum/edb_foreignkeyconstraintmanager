-- views
CREATE OR REPLACE FUNCTION edb_util.copy_view(
  source_schema text, target_schema text
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT 'CREATE VIEW ' || c.relname || ' AS '
      || replace(
        pg_catalog.pg_get_viewdef(c.oid)
        , source_schema || '.', target_schema || '.'
      ) || ';'
     as decl
      from pg_catalog.pg_class as c
     WHERE c.relkind = 'v'::"char"
       and c.relnamespace = source_schema::regnamespace
  LOOP
    RAISE NOTICE '%', rec.decl;
    EXECUTE rec.decl;
  END LOOP;

  RETURN TRUE;

EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Duplicate object';
 -- WHEN others THEN
 --   RETURN FALSE;
 END;
 $$ LANGUAGE plpgsql VOLATILE
 ;


-- materialized views
