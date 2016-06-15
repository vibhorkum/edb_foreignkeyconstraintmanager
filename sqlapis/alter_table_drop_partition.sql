
CREATE OR REPLACE FUNCTION edb_util.get_nulls(table_oid oid) RETURNS TEXT AS $$
DECLARE
    null_count INT;
    null_list TEXT;
BEGIN
    SELECT COUNT (1) INTO null_count FROM
    (SELECT unnest(conkey)
    FROM pg_constraint c
    WHERE c.conrelid =table_oid
         AND c.contype = 'f');

    SELECT '('
           || repeat('NULL,',null_count-1)
           || 'NULL)'
           INTO null_list;
    RETURN null_list;
END; $$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION edb_util.get_key_name(table_oid oid, key_type char) RETURNS TEXT AS $$
DECLARE
    key_name TEXT;
BEGIN
    SELECT '(' ||
           array_to_string ( ARRAY (
           SELECT a.attname
           FROM pg_attribute a
           WHERE a.attrelid = table_oid
                 AND a.attnum IN
                 (
                   SELECT unnest(conkey)
                   FROM pg_constraint c
                   WHERE c.conrelid =table_oid
                         AND c.contype = key_type
                 ) ),',') || ')' INTO key_name;
    RETURN key_name;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION edb_util.check_tables(pk_table_name name, partition_name name, fk_table_name name) RETURNS BOOLEAN AS $$
DECLARE
    pk_tab_count INT;
    fk_tab_count INT;
    fk_tab_oid OID;
    pk_tab_oid OID;
    fk_count INT;
    par_count INT;
BEGIN
    SELECT COUNT(1) INTO pk_tab_count FROM pg_catalog.pg_class WHERE relname = pk_table_name;
    IF (pk_tab_count = 0) THEN
      RAISE EXCEPTION 'The database has no table with the name %', pk_table_name
      USING HINT = 'Please use correct name';
    END IF;
    IF (pk_tab_count > 1) THEN
      RAISE EXCEPTION 'The database has more that one tables with the name %', pk_table_name
      USING HINT = 'Please use schema qualified name';
    END IF;

    SELECT oid INTO pk_tab_oid FROM pg_catalog.pg_class WHERE relname = pk_table_name;

--    SELECT COUNT(1) INTO par_count from pg_catalog.edb_partition
--    WHERE partrelid = pk_tab_oid AND partname = partition_name;
--    IF (par_count = 0) THEN
--      RAISE EXCEPTION 'The table % has no partition named %', pk_table_name, partition_name
--      USING HINT = 'Please use correct name';
--    END IF;

    SELECT COUNT(1) INTO fk_tab_count FROM pg_catalog.pg_class WHERE relname = fk_table_name;
    IF (fk_tab_count = 0) THEN
      RAISE EXCEPTION 'The database has no table with the name %', fk_table_name
      USING HINT = 'Please use correct name';
    END IF;
    IF (fk_tab_count > 1) THEN
      RAISE EXCEPTION 'The database has more that one tables with the name %', fk_table_name
      USING HINT = 'Please use schema qualified name';
    END IF;

    SELECT oid INTO fk_tab_oid FROM pg_catalog.pg_class WHERE relname = fk_table_name;

    SELECT COUNT(conkey) INTO fk_count FROM pg_constraint c
    WHERE c.conrelid =fk_tab_oid AND c.contype = 'f';
    IF (fk_count = 0) THEN
      RAISE EXCEPTION 'The table % has no foreign key constraint', fk_table_name
      USING HINT = 'Please use REFERENCES clause while creating the table';
    END IF;

    RETURN true;
END; $$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION edb_util.del_referencing_rows(pk_table_name name, partition_name name, fk_table_name name) RETURNS BOOLEAN AS $$
DECLARE
    del_query TEXT;
    pk_tab_oid OID;
    fk_tab_oid OID;
BEGIN
    IF (edb_util.check_tables(pk_table_name, partition_name, fk_table_name) != true) THEN
        RETURN false;
    END IF;

    SELECT oid INTO pk_tab_oid FROM pg_catalog.pg_class WHERE relname = pk_table_name;
    SELECT oid INTO fk_tab_oid FROM pg_catalog.pg_class WHERE relname = fk_table_name;

    SELECT 'DELETE FROM ' || fk_table_name || ' WHERE '
           || edb_util.get_key_name(fk_tab_oid, 'f')
           || ' IN ( SELECT '
           || edb_util.get_key_name(pk_tab_oid, 'p')
           || ' FROM '
           || pk_table_name
           || '_'
           || partition_name
           || ')' INTO del_query;

    EXECUTE del_query;
    RETURN true;
END; $$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION edb_util.null_referencing_rows(pk_table_name name, partition_name name, fk_table_name name) RETURNS BOOLEAN AS $$
DECLARE
    upd_query TEXT;
    pk_tab_oid OID;
    fk_tab_oid OID;
BEGIN
    IF (edb_util.check_tables(pk_table_name, partition_name, fk_table_name) != true) THEN
        RETURN false;
    END IF;

    SELECT oid INTO pk_tab_oid FROM pg_catalog.pg_class WHERE relname = pk_table_name;
    SELECT oid INTO fk_tab_oid FROM pg_catalog.pg_class WHERE relname = fk_table_name;

    SELECT 'UPDATE ' || fk_table_name || ' SET '
           || edb_util.get_key_name(fk_tab_oid, 'f')
           || ' = '
           || edb_util.get_nulls(fk_tab_oid)
           || ' WHERE '
           || edb_util.get_key_name(fk_tab_oid, 'f')
           || ' IN ( SELECT '
           || edb_util.get_key_name(pk_tab_oid, 'p')
           || ' FROM '
           || pk_table_name
           || '_'
           || partition_name
           || ')' INTO upd_query;

    EXECUTE upd_query;
    RETURN true;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION edb_util.restrict_referencing_rows(pk_table_name name, partition_name name, fk_table_name name) RETURNS BOOLEAN AS $$
DECLARE
    upd_query TEXT;
    pk_tab_oid OID;
    fk_tab_oid OID;
    row_count INT;
BEGIN
    IF (edb_util.check_tables(pk_table_name, partition_name, fk_table_name) != true) THEN
        RETURN false;
    END IF;

    SELECT oid INTO pk_tab_oid FROM pg_catalog.pg_class WHERE relname = pk_table_name;
    SELECT oid INTO fk_tab_oid FROM pg_catalog.pg_class WHERE relname = fk_table_name;

    SELECT 'SELECT COUNT(1) FROM ' || fk_table_name
           || ' WHERE '
           || edb_util.get_key_name(fk_tab_oid, 'f')
           || ' IN ( SELECT '
           || edb_util.get_key_name(pk_tab_oid, 'p')
           || ' FROM '
           || pk_table_name
           || '_'
           || partition_name
           || ')' INTO upd_query;

    EXECUTE upd_query INTO row_count;

    IF (row_count > 0) THEN
      RAISE EXCEPTION 'The partition % in table % contains rows referenced by other tables', partition_name, pk_table_name;
    END IF;

    RETURN true;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION edb_util.alter_table_drop_partition(pk_table_name name, partition_name name, fk_table_name name[], cascade TEXT) RETURNS BOOLEAN AS $$
DECLARE
    fk_tab_name name;
    query TEXT;
    ret BOOLEAN;
BEGIN
    FOREACH fk_tab_name IN ARRAY fk_table_name LOOP
        CASE cascade
            WHEN 'cascade' THEN
                SELECT edb_util.del_referencing_rows(pk_table_name, partition_name, fk_tab_name) INTO ret;
            WHEN 'setnull' THEN
                SELECT edb_util.null_referencing_rows(pk_table_name, partition_name, fk_tab_name) INTO ret;
            ELSE
                SELECT edb_util.restrict_referencing_rows(pk_table_name, partition_name, fk_tab_name) INTO ret;
            END CASE;
    END LOOP;

    SELECT 'ALTER TABLE ' || pk_table_name
           || ' DROP PARTITION ' || partition_name
           INTO query;

    EXECUTE query;
    RETURN true;
END; $$ LANGUAGE plpgsql;

