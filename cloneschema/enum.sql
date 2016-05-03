-- SELECT array_to_string(enum_range(NULL, NULL::tkcsowner.card_type), ',');
CREATE OR REPLACE FUNCTION edb_util.get_enum_declaration(relid oid)
RETURNS text
AS $$
BEGIN
  RETURN (
    with lbls as (
      SELECT t.typname
          , e.enumlabel
        from pg_catalog.pg_enum as e
      LEFT join pg_catalog.pg_type as t on e.enumtypid = t.oid
      WHERE e.enumtypid = relid
      ORDER BY e.enumsortorder
    )
  SELECT 'CREATE TYPE ' || l.typname
    || ' AS ENUM (' || string_agg(quote_literal(l.enumlabel), ', ') || ');'
    from lbls as l
  GROUP BY l.typname
);
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_enum(
  source_schema text, target_schema text
)
RETURNS boolean
AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT edb_util.get_enum_declaration(x.oid) as decl
    from (
      SELECT DISTINCT t.oid
        from pg_enum as e
      LEFT JOIN pg_type as t on e.enumtypid = t.oid
       WHERE EXISTS ( SELECT 1
           from pg_namespace WHERE oid = t.typnamespace
            and nspname = source_schema
           )
    ) as x
  LOOP
    RAISE NOTICE '%', rec.decl;
    EXECUTE rec.decl;
    --EXCEPTION WHEN duplicate_object THEN
      --RAISE NOTICE 'duplicate';
  END LOOP;

  RETURN TRUE;

-- WHEN others THEN
--   RETURN FALSE;
END;
$$ LANGUAGE plpgsql VOLATILE
;
