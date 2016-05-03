CREATE OR REPLACE FUNCTION edb_util.get_datatype_declaration(relid oid)
RETURNS text
AS $$
BEGIN
  RETURN (
    with attrs as (
      SELECT quote_ident(c.relname) as relname
          , quote_ident(a.attname) as attname
          , format_type(a.atttypid, a.atttypmod) as atttypdecl
        from pg_class as c
      LEFT join pg_catalog.pg_attribute as a on c.oid = a.attrelid
      WHERE c.oid = relid
        and a.attnum > 0
        and NOT a.attisdropped
      ORDER BY a.attnum
    )
  SELECT 'CREATE TYPE ' || quote_ident(a.relname)
    || ' AS (' || string_agg(a.attname || ' ' || a.atttypdecl,', ') || ');'
    from attrs as a
  GROUP BY a.relname
);
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_datatype(
  source_schema text, target_schema text
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT edb_util.get_datatype_declaration(c.oid) as decl
      from pg_class as c
     WHERE c.relkind = 'c'
       and EXISTS ( SELECT 1
         from pg_namespace WHERE oid = c.relnamespace
          and nspname = source_schema
         )
  LOOP
    RAISE NOTICE '%', rec.decl;
    EXECUTE rec.decl;
  END LOOP;

  RETURN TRUE;

EXCEPTION WHEN duplicate_object THEN
  RETURN FALSE;
WHEN others THEN
  RETURN FALSE;
END;
$$ LANGUAGE plpgsql VOLATILE
;
