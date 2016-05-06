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
  , verbose_bool boolean DEFAULT FALSE
)
RETURNS boolean
AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT replace(
      edb_util.get_enum_declaration(x.oid)
      , source_schema || '.', target_schema || '.'
    ) as decl
      , x.oid::regtype as name
    from (
      SELECT DISTINCT t.oid
        from pg_enum as e
      LEFT JOIN pg_type as t on e.enumtypid = t.oid
       WHERE t.typnamespace = source_schema::regnamespace
    ) as x
  LOOP
    RAISE NOTICE 'COPYING ENUM %', rec.name;
    IF verbose_bool THEN
      RAISE NOTICE '%', rec.decl;
    END IF;
    EXECUTE rec.decl;
  END LOOP;

  RETURN TRUE;

END;
$$ LANGUAGE plpgsql VOLATILE
;
