-- views
CREATE OR REPLACE FUNCTION edb_util.copy_view(
  source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    with RECURSIVE viewing AS (
      SELECT c.oid as relid, c.relname, NULL::oid as refobjid
        , 0 as ancestors
        from pg_class as c
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
    RAISE NOTICE 'CREATING VIEW %', rec.name;
    IF verbose_bool THEN
      RAISE NOTICE '%', rec.decl;
    END IF;
    EXECUTE rec.decl;
  END LOOP;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql VOLATILE
;

    SELECT 'CREATE VIEW ' || quote_ident(c.relname) || ' AS '
      || replace(
        pg_catalog.pg_get_viewdef(c.oid)
        , source_schema || '.', target_schema || '.'
      ) || ';'
     as decl
     , c.relname as name
      from pg_catalog.pg_class as c
     WHERE c.relkind = 'v'::"char"
       and c.relnamespace = source_schema::regnamespace
  LOOP
    RAISE NOTICE 'CREATING VIEW %', rec.name;
    IF verbose_bool THEN
      RAISE NOTICE '%', rec.decl;
    END IF;
    EXECUTE rec.decl;
  END LOOP;

  RETURN TRUE;
 END;
 $$ LANGUAGE plpgsql VOLATILE
 ;

-- -- materialized views
--
-- CREATE SCHEMA test;
-- CREATE VIEW test.basement AS SELECT 1 fnk ;
-- CREATE VIEW test.floor_one AS SELECT * from test.basement ;
-- CREATE OR REPLACE FUNCTION test.monkey_wrench() RETURNS boolean AS $$ SELECT TRUE; $$ LANGUAGE sql;
-- CREATE OR REPLACE VIEW test.porch AS SELECT fnk, test.monkey_wrench() as mw from test.floor_one ;
-- CREATE OR REPLACE VIEW test.floor_two AS SELECT fnk, FALSE as mw from test.floor_one
--   UNION ALL SELECT * from test.porch;
-- CREATE VIEW test.penthouse AS SELECT * from test.floor_two ;
--
-- SELECT DISTINCT classid::regclass
--   ,
--
-- SELECT DISTINCT c.oid, c.relname, c.relnamespace::regnamespace
--   , c.relkind
--   , d.refobjid, d.refobjid::regclass
--     from pg_catalog.pg_depend as d
--     join pg_catalog.pg_rewrite as rw on d.objid = rw.oid
--   LEFT join pg_catalog.pg_class as c
--     on rw.ev_class = c.oid
--    WHERE c.oid <> d.refobjid
--      and EXISTS ( SELECT 1
--     from pg_class where oid = d.refobjid
--      and relkind NOT in ('r'::"char")
--      and relnamespace = 'test'::regnamespace
-- )
-- ;
--
-- with RECURSIVE viewing AS (
--   SELECT c.oid as relid, c.relname, NULL::oid as refobjid
--     , 0 as ancestors
--     from pg_class as c
--    WHERE c.relkind = 'v'::"char"
--      and c.relnamespace = 'test'::regnamespace
--   UNION ALL
--   SELECT DISTINCT c.oid, c.relname, d.refobjid
--     , viewing.ancestors + 1
--     from pg_catalog.pg_depend as d
--     join viewing on d.refobjid = viewing.relid
--     join pg_catalog.pg_rewrite as rw on d.objid = rw.oid
--     join pg_catalog.pg_class as c
--       on rw.ev_class = c.oid and c.relkind = 'v'::"char"
--   WHERE c.oid <> d.refobjid
-- )
-- SELECT relid, relname
--   , max(ancestors) as ancestors
-- from viewing
-- GROUP BY relid, relname
-- ORDER BY ancestors
-- ;
--
-- SELECT * from viewing ORDER BY relid, refobjid, ancestors
--
-- SELECT relid, relname
--   , max(ancestors)
-- from viewing
-- GROUP BY relid, relname
-- ORDER BY 3
-- ;
--
-- SELECT c.oid, c.relname
--   from pg_class as c
--  WHERE c.relkind = 'v'::"char"
--    and c.relnamespace = 'test'::regnamespace
