CREATE OR REPLACE FUNCTION edb_util.copy_view(
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
    with RECURSIVE viewing AS (
      SELECT c.oid as relid, c.relname, NULL::oid as refobjid
        , 0 as ancestors
        from pg_catalog.pg_class as c
       WHERE c.relkind = 'v'::"char"
         and c.relnamespace = source_schema::regnamespace
      UNION ALL
      SELECT DISTINCT c.oid, c.relname, d.refobjid
        , viewing.ancestors + 1
        from pg_catalog.pg_depend as d
        join viewing on d.refobjid = viewing.relid
        join pg_catalog.pg_rewrite as rw on d.objid = rw.oid
        join pg_catalog.pg_class as c
          on rw.ev_class = c.oid and c.relkind = 'v'::"char"
      WHERE c.oid <> d.refobjid
    )
    SELECT 'CREATE VIEW ' || quote_ident(c.relname) || ' AS '
      || replace(
        pg_catalog.pg_get_viewdef(c.relid)
        , source_schema || '.', target_schema || '.'
      ) || ';'
     as decl
     , c.relname as name
      from (
        SELECT relid, relname
          , max(ancestors) as ancestors
        from viewing
        GROUP BY relid, relname
        ORDER BY ancestors
      ) as c
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'VIEW', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;
