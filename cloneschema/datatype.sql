CREATE OR REPLACE FUNCTION edb_util.get_datatype_declaration(relid oid)
RETURNS text
AS $$
  with attrs as (
    SELECT quote_ident(c.relname) as relname
        , quote_ident(a.attname) as attname
        , format_type(a.atttypid, a.atttypmod) as atttypdecl
      from pg_catalog.pg_class as c
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
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_datatype(
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
      edb_util.get_datatype_declaration(c.oid)
      , source_schema || '.', target_schema || '.'
    ) as decl
      , c.relname as name
      from pg_class as c
     WHERE c.relkind = 'c'
       and c.relnamespace = source_schema::regnamespace
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'DATATYPE', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;
