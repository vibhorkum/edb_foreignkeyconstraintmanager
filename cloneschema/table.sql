CREATE OR REPLACE FUNCTION edb_util.get_sequence_declaration(
  relid oid
)
RETURNS text
AS $$
  SELECT 'CREATE SEQUENCE ' || quote_ident(c.relname)
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
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_sequence(
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
      edb_util.get_sequence_declaration(c.oid)
      , source_schema || '.', target_schema || '.'
    )  as decl
      , c.relname as name
      from pg_class as c
     WHERE c.relkind = 'S'::"char"
       and c.relnamespace = source_schema::regnamespace
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'SEQUENCE', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_table_declaration(
  relid oid, on_tblspace boolean default FALSE
)
RETURNS text
AS $$
  with attrs as (
    SELECT quote_ident(c.relname) as relname
        , quote_ident(a.attname) as attname
        , a.attnotnull
        , format_type(a.atttypid, a.atttypmod) as attypdecl
        , (SELECT cl.collname
          FROM pg_catalog.pg_collation as cl
          WHERE a.attcollation > 0
            AND cl.oid = a.attcollation
            AND cl.collname <> 'default'
        ) as attcollation
      from pg_catalog.pg_class as c
    LEFT join pg_catalog.pg_attribute as a on c.oid = a.attrelid
    WHERE c.oid = relid
      and a.attnum > 0
      and NOT a.attisdropped
    ORDER BY a.attnum
  )
  , rel as (
    SELECT quote_ident(c.relname) as relname
      , CASE c.relpersistence
          WHEN 'u' then 'UNLOGGED ' else '' END as persistence
      , CASE when on_tblspace and t.spcname is NOT NULL
          then ' TABLESACE ' || t.spcname else '' END as tblspace
    FROM pg_catalog.pg_class as c
    LEFT join pg_catalog.pg_tablespace as t
      on c.reltablespace = t.oid
    WHERE c.oid = relid
  )
  SELECT 'CREATE ' || r.persistence
    || 'TABLE ' || r.relname
    || ' ('
      || string_agg(
        a.attname || ' ' || a.attypdecl
      || CASE when a.attcollation is NULL then ''
          else ' COLLATE ' || a.attcollation END
      -- || CASE when a.attdef is NULL then ''
      --     else ' DEFAULT (' || a.attdef || ')' END
      || CASE when a.attnotnull then ' NOT NULL' else '' END
      , ', ')
    || ')' || r.tblspace || ';'
    from attrs as a
    JOIN rel as r USING (relname)
  GROUP BY r.persistence, r.relname, r.tblspace
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_simple(
  source_schema text, target_schema text
  , on_tblspace boolean DEFAULT FALSE
  , verbose_bool boolean DEFAULT FALSE
)
-- copies table definition without indexes, constraints, defaults, or triggers
RETURNS boolean AS $$
DECLARE rec record;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT replace(
        edb_util.get_table_declaration(c.oid, on_tblspace)
        , source_schema || '.', target_schema || '.'
      ) as decl
      , c.relname as name
      from pg_catalog.pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'TABLE', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_partitions(
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
        pg_catalog.pg_get_partdef(c.oid)
        , source_schema || '.', target_schema || '.'
      ) as decl
      , c.relname as name
      from pg_catalog.pg_class as c
      join pg_catalog.edb_partdef as prt on c.oid = prt.pdefrel
     WHERE c.relnamespace = source_schema::regnamespace
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'TABLE PARTITION', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;

END;
$$ LANGUAGE plpgsql VOLATILE
;

CREATE OR REPLACE FUNCTION edb_util.get_table_insert_select(
  relid oid, source_schema text
)
RETURNS text
AS $$
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
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_data(
  source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
)
RETURNS boolean AS $$
DECLARE rec record;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  FOR rec in
    SELECT edb_util.get_table_insert_select(c.oid, target_schema) as statement
      , c.relname as name
      from pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = target_schema::regnamespace
  LOOP
    RAISE NOTICE 'COPYING TABLE DATA to %', rec.name;
    IF verbose_bool THEN
      RAISE NOTICE '%', rec.statement;
    END IF;
    EXECUTE rec.statement;
  END LOOP;

  RETURN TRUE;

END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_constraint_declaration(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT cn.conname, 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_check_constraint_declaration(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT cn.conname, 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'c'::"char"
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_unique_constraint_declaration(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT cn.conname, 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'u'::"char"
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_pk_constraint_declaration(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT cn.conname, 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'p'::"char"
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_exclusion_constraint_declaration(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT cn.conname, 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'x'::"char"
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_constraint_trigger_declaration(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT cn.conname, 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 't'::"char"
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_non_fk_constraint_declaration(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT cn.conname, 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype <> 'f'::"char"
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_fk_constraint_declaration(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT cn.conname, 'ALTER TABLE ' || quote_ident(c.relname) || ' ADD CONSTRAINT '
    || quote_ident(cn.conname) || ' '
    || pg_get_constraintdef(cn.oid) || ';'
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_constraint as cn on c.oid = cn.conrelid
  WHERE c.oid = relid
    and cn.contype = 'f'::"char"
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_constraint(
  source_schema text, target_schema text
  , verbose_bool boolean DEFAULT FALSE
)
RETURNS boolean AS $$
DECLARE rec record;
  rec_success boolean;
  all_success boolean DEFAULT TRUE;
BEGIN
  PERFORM set_config('search_path', target_schema, FALSE);

  -- exclude FK in first pass, as they require a unique constraint target on destination table
  FOR rec in
    SELECT replace(
      (x.dcltyp).decl, source_schema || '.', target_schema || '.'
    ) as decl
      , (x.dcltyp).name as name
    from (
    SELECT edb_util.get_non_fk_constraint_declaration(c.oid) as dcltyp
      from pg_catalog.pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
       and EXISTS (SELECT 1 from pg_catalog.pg_constraint
        where conrelid = c.oid)
    ) as x
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'TABLE CONSTRAINT', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  FOR rec in
    SELECT replace(
      (x.dcltyp).decl, source_schema || '.', target_schema || '.'
    ) as decl
      , (x.dcltyp).name as name
    from (
    SELECT edb_util.get_fk_constraint_declaration(c.oid) as dcltyp
      from pg_catalog.pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
       and EXISTS (SELECT 1 from pg_catalog.pg_constraint
        where conrelid = c.oid)
    ) as x
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'FK CONSTRAINT', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.get_column_default(
  relid oid
)
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT a.attname
    , 'ALTER TABLE ' || quote_ident(relname) || ' ALTER COLUMN '
      || quote_ident(a.attname) || ' SET DEFAULT '
      || substring(pg_catalog.pg_get_expr(d.adbin, d.adrelid) for 128) || ';'
    FROM pg_catalog.pg_class as c
    join pg_catalog.pg_attrdef as d
      on c.oid = d.adrelid
    join pg_catalog.pg_attribute as a
      on d.adrelid = a.attrelid AND d.adnum = a.attnum
   WHERE c.oid = relid
     and a.atthasdef
     and a.attnum > 0
     and NOT a.attisdropped
  ORDER BY a.attnum
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_default(
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
      (x.dcltyp).decl, source_schema || '.', target_schema || '.'
    ) as decl
      , (x.dcltyp).name as name
    from (
    SELECT edb_util.get_column_default(c.oid) as dcltyp
      from pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
       and EXISTS ( SELECT 1
         from pg_catalog.pg_attribute
        where attrelid = c.oid
         and atthasdef
         and attnum > 0
         and NOT attisdropped
       )
     ) as x
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'FK CONSTRAINT', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

-- indexes
CREATE OR REPLACE FUNCTION edb_util.get_index_declaration(
  relid oid
)
-- declarations for all non-unique indexes and non-pk indexes
RETURNS SETOF edb_util.declaration_type
AS $$
  SELECT (SELECT relname from pg_class WHERE oid = i.indexrelid)
    , pg_catalog.pg_get_indexdef(i.indexrelid)
    from pg_catalog.pg_class as c
  LEFT JOIN pg_catalog.pg_index as i
    on c.oid = i.indrelid
  WHERE c.oid = relid
    and i.indisprimary is FALSE -- pk created by constraint
    and i.indisunique is FALSE -- uq index creaed by constraint
    and i.indislive is TRUE
  ;
$$ LANGUAGE sql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_index(
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
      (x.dcltyp).decl, source_schema || '.', target_schema || '.'
    ) as decl
      , (x.dcltyp).name as name
    from (
    SELECT edb_util.get_index_declaration(c.oid) as dcltyp
      from pg_class as c
     WHERE c.relkind = 'r'::"char"
       and c.relnamespace = source_schema::regnamespace
       and EXISTS ( SELECT 1
         from pg_catalog.pg_index
        where indrelid = c.oid
          and indisprimary is FALSE and indisunique is FALSE
          and indislive is TRUE
        )
      ) as x
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'INDEX', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_trigger(
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
      pg_get_triggerdef(tg.oid)
      , source_schema || '.', target_schema || '.'
    ) as decl
      , tg.tgname as name
      from pg_catalog.pg_trigger as tg
     WHERE EXISTS ( SELECT 1 from pg_catalog.pg_class
       WHERE oid = tg.tgrelid
         and relnamespace = source_schema::regnamespace
       )
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'TRIGGER', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;

CREATE OR REPLACE FUNCTION edb_util.copy_table_rule(
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
      r.definition, source_schema || '.', target_schema || '.'
    ) as decl
      , r.rulename as name
      from pg_catalog.pg_rules as r
     WHERE r.schemaname = source_schema
  LOOP
    SELECT * from edb_util.object_create_runner(
      rec.name, rec.decl, 'RULE', FALSE, verbose_bool)
        INTO rec_success;

    IF NOT rec_success THEN
      all_success := FALSE;
    END IF;
  END LOOP;

  RETURN all_success;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT
;
