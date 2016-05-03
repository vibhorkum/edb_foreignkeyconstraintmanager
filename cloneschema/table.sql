--  SELECT * from pg_get_viewdef('information_schema.sequences');
CREATE OR REPLACE FUNCTION edb_util.get_sequence_declaration(
  relid oid
)
RETURNS text
AS $$
BEGIN
  RETURN (
    SELECT 'CREATE SEQUENCE ' || c.relname
      || ' INCREMENT BY ' || parm.increment::text
      || ' MINVALUE ' || parm.minimum_value::text
      || ' MAXVALUE ' || parm.maximum_value::text
      || ' START WITH ' || pg_catalog.nextval(c.oid)::text
      || CASE
        WHEN parm.cycle_option is FALSE then ' NO ' else ' ' END
      || 'CYCLE;'
      from pg_catalog.pg_class as c
    JOIN LATERAL pg_catalog.pg_sequence_parameters(c.oid) as parm on 1=1
    WHERE c.oid = relid
);
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_sequence(
  source_schema text, target_schema text
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT edb_util.get_sequence_declaration(c.oid) as decl
      from pg_class as c
     WHERE c.relkind = 'S'::"char"
       and c.relnamespace = source_schema::regnamespace
  LOOP
    RAISE NOTICE '%', replace(rec.decl, source_schema || '.', target_schema || '.');
    EXECUTE replace(rec.decl, source_schema || '.', target_schema || '.');
  END LOOP;

  RETURN TRUE;

EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Duplicate object';
-- WHEN others THEN
--   RETURN FALSE;
END;
$$ LANGUAGE plpgsql VOLATILE
;


-- partitioned table

CREATE OR REPLACE FUNCTION edb_util.get_table_declaration(
  relid oid, on_tblspace boolean default FALSE
)
RETURNS text
AS $$
BEGIN
  RETURN (
    with attrs as (
      SELECT c.relname
          , a.attname
          , a.attnotnull
          , format_type(a.atttypid, a.atttypmod) as attypdecl
          , (SELECT substring(pg_catalog.pg_get_expr(d.adbin, d.adrelid) for 128)
            FROM pg_catalog.pg_attrdef d
            WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum AND a.atthasdef
          ) as attdef
          , (SELECT cl.collname
            FROM pg_catalog.pg_collation as cl
            WHERE a.attcollation > 0 AND cl.oid = a.attcollation
          ) as attcollation
        from pg_catalog.pg_class as c
      LEFT join pg_catalog.pg_attribute as a on c.oid = a.attrelid
      WHERE c.oid = relid
        and a.attnum > 0
        and NOT a.attisdropped
      ORDER BY a.attnum
    )
  , table_opts as (
    SELECT t.spcname
    FROM pg_catalog.pg_tablespace as t
    WHERE EXISTS ( SELECT 1
      from pg_class where reltablespace = t.oid
      )
  )
  SELECT 'CREATE TABLE ' || quote_ident(a.relname)
    || ' (' || string_agg(
      quote_ident(a.attname) || ' ' || a.attypdecl
      || coalesce( ' '
        || CASE when a.attdef is NULL then ''
          else 'DEFAULT (' || a.attdef || ')' END
        , '')   -- ('source.some_table_this_id_seq'::regclass)
      || CASE when a.attnotnull is TRUE then ' NOT NULL' else '' END
      ,', ') || ');'  -- tablespace, table storage options
    from attrs as a
  GROUP BY a.relname
);
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_simple(
  source_schema text, target_schema text
  , on_tblspace boolean default FALSE
)
-- simple copies table definition without indexes, constraints, or triggers
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT edb_util.get_table_declaration(c.oid, on_tblspace) as decl
      from pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
  LOOP
    RAISE NOTICE '%', replace(rec.decl, source_schema || '.', target_schema || '.');
    EXECUTE replace(rec.decl, source_schema || '.', target_schema || '.');
  END LOOP;

  RETURN TRUE;

EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Duplicate object';
-- WHEN others THEN
--   RETURN FALSE;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_table_insert_select(
  relid oid, source_schema text
)
RETURNS text
AS $$
BEGIN
  RETURN (
    with cols as (
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
  SELECT 'INSERT INTO ' || cols.relname
    || ' SELECT ' || string_agg(cols.attname || '::' || cols.atttypdecl, ',')
    || ' from ' || source_schema || '.' || cols.relname || ';'
    from cols
  GROUP BY cols.relname
);
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_data(
  source_schema text, target_schema text
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT edb_util.get_table_insert_select(c.oid, target_schema) as statement
      from pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = target_schema::regnamespace
  LOOP
    RAISE NOTICE '%', rec.statement;
    EXECUTE rec.statement;
  END LOOP;

  RETURN TRUE;

END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_constraint_declaration(
  relid oid
)
RETURNS SETOF text
AS $$
  SELECT 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_check_constraint_declaration(
  relid oid
)
RETURNS SETOF text
AS $$
  SELECT 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'c'::"char"
;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_unique_constraint_declaration(
  relid oid
)
RETURNS SETOF text
AS $$
  SELECT 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'u'::"char"
;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_pk_constraint_declaration(
  relid oid
)
RETURNS SETOF text
AS $$
  SELECT 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'p'::"char"
;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_exclusion_constraint_declaration(
  relid oid
)
RETURNS SETOF text
AS $$
  SELECT 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'x'::"char"
;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_constraint_trigger_declaration(
  relid oid
)
RETURNS SETOF text
AS $$
  SELECT 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 't'::"char"
;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_non_fk_constraint_declaration(
  relid oid
)
RETURNS SETOF text
AS $$
  SELECT 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype <> 'f'::"char"
;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_fk_constraint_declaration(
  relid oid
)
RETURNS SETOF text
AS $$
  SELECT 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'f'::"char"
;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_constraint(
  source_schema text, target_schema text
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT replace(
      edb_util.get_non_fk_constraint_declaration(c.oid)
      , source_schema || '.', target_schema || '.'
    ) as statement
      from pg_catalog.pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
       and EXISTS (SELECT 1 from pg_catalog.pg_constraint
        where conrelid = c.oid)
  LOOP
    RAISE NOTICE '%', rec.statement;
    EXECUTE rec.statement;
  END LOOP;

  FOR rec in
    SELECT replace(
      edb_util.get_fk_constraint_declaration(c.oid)
      , source_schema || '.', target_schema || '.'
    ) as statement
      from pg_catalog.pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
       and EXISTS (SELECT 1 from pg_catalog.pg_constraint
        where conrelid = c.oid)
  LOOP
    RAISE NOTICE '%', rec.statement;
    EXECUTE rec.statement;
  END LOOP;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql VOLATILE
;

-- indexes
CREATE OR REPLACE FUNCTION edb_util.get_index_declaration(
  relid oid
)
-- declarations for all non-unique indexes and non-pk indexes
RETURNS SETOF text
AS $$
  SELECT pg_catalog.pg_get_indexdef(i.indexrelid)
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_index as i
    on c.oid = i.indrelid
  WHERE c.oid = relid
    and i.indisprimary is FALSE -- pk created by contraint
    and i.indisunique is FALSE -- uq index creaed by constraint
    and i.indislive is TRUE
  ;
$$ LANGUAGE sql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_index(
  source_schema text, target_schema text
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT edb_util.get_index_declaration(c.oid) as decl
      from pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
       and EXISTS ( SELECT 1
         from pg_catalog.pg_index
        where indrelid = c.oid
          and indisprimary is FALSE and indisunique is FALSE
          and indislive is TRUE
        )
  LOOP
    RAISE NOTICE '%', replace(rec.decl, source_schema || '.', target_schema || '.');
    EXECUTE replace(rec.decl, source_schema || '.', target_schema || '.');
  END LOOP;

  RETURN TRUE;

EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Duplicate object';
-- WHEN others THEN
--   RETURN FALSE;
END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.copy_rules(
  source_schema text, target_schema text
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT r.definition as decl
      from pg_catalog.pg_rules as r
     WHERE r.schemaname = source_schema
  LOOP
    RAISE NOTICE '%', replace(rec.decl, source_schema || '.', target_schema || '.');
    EXECUTE replace(rec.decl, source_schema || '.', target_schema || '.');
  END LOOP;

  RETURN TRUE;

EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Duplicate object';
 -- WHEN others THEN
 --   RETURN FALSE;
 END;
 $$ LANGUAGE plpgsql VOLATILE
 ;


-- triggers
-- ACL
