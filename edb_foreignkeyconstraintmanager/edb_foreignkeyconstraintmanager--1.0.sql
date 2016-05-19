/* EnterpriseDB edb_foreignkeyconstraintmanager extension
 *
 * "Copyright © 2016. EnterpriseDB Corporation and/or its subsidiaries or
 * affiliates. All Rights Reserved."
 */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
--\echo Use "CREATE EXTENSION edb_foreignkeyconstraintmanager" to load this file. \quit

CREATE OR REPLACE FUNCTION edb_util.create_fk_constraint(parent_table_name regclass, parent_table_column_names text[], child_table_name regclass, child_table_column_names text[], cascade boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$

DECLARE
	tbl_name TEXT;
BEGIN
-- test for PPAS table part view
IF NOT EXISTS ( select 1 from information_schema.views where table_name = 'all_part_tables') THEN
  RAISE EXCEPTION 'PPAS specific view not found'
      USING HINT = 'PPAS in oracle compatiblity mode is required for this extension';
END IF;  

--  Parent is not partition
IF NOT EXISTS (select 1 from ALL_PART_TABLES where ALL_PART_TABLES.table_name = quote_ident_redwood(parent_table_name::TEXT)) THEN
  
  -- parent is not partitioned and child is partitioned, then alter table on each partition table
  IF EXISTS (select 1 from ALL_PART_TABLES where ALL_PART_TABLES.table_name = quote_ident_redwood(child_table_name::TEXT)) THEN

    FOR tbl_name in select partition_name from ALL_TAB_PARTITIONS where table_name = quote_ident_redwood(child_table_name::TEXT) LOOP
    tbl_name = lower(tbl_name);

      EXECUTE 'ALTER TABLE '|| child_table_name || '_' || tbl_name || ' ADD  FOREIGN KEY(' || array_to_string(child_table_column_names, ',') || ') 
      REFERENCES '|| parent_table_name || '('|| array_to_string(parent_table_column_names, ',') || ')';
    END LOOP;
  
  -- parent is not partition and child is not partitioned
  ELSE
    EXECUTE 'ALTER TABLE '|| child_table_name || ' ADD  FOREIGN KEY(' || array_to_string(child_table_column_names, ',') || ') 
  REFERENCES '|| parent_table_name || '('|| array_to_string(parent_table_column_names, ',') || ')';
  END IF;

ELSE
  -- parent is partitioned
  -- add trigger for each partitioned table of parent  
  FOR tbl_name in select partition_name from ALL_TAB_PARTITIONS where table_name = quote_ident_redwood(parent_table_name::TEXT) LOOP
    tbl_name = lower(tbl_name);
    IF NOT EXISTS (select 1 from pg_trigger where not tgisinternal and tgrelid = (parent_table_name || '_' || tbl_name)::regclass and tgname = 'fk_constraint_' || parent_table_name || '_' || tbl_name) THEN
      RAISE NOTICE 'no trigger on % named %.  creating', parent_table_name || '_' || tbl_name, 'fk_constraint_' || parent_table_name || '_' || tbl_name;
 
       EXECUTE 'CREATE TRIGGER fk_constraint_' || parent_table_name || '_' || tbl_name || ' BEFORE DELETE OR UPDATE ON ' || parent_table_name || '_' || tbl_name || ' FOR EACH ROW
       EXECUTE PROCEDURE
       check_foreign_key (
       1,  			-- number of tables that foreign keys need to be checked
       ' || cascade || ', 	-- boolean defines that corresponding keys must be deleted.
       ' || array_to_string(child_table_column_names, ',') || ', 	-- name of primary key column in triggered table (A). 
 							-- You may use as many columns as you need.
       ' || child_table_name || ', 	-- name of (first) table with foreign keys.
       ' || array_to_string(parent_table_column_names, ',') || ')';
    END IF;
  END LOOP;

  -- check_primary_key on child table  
  IF EXISTS (select 1 from pg_trigger where not tgisinternal and tgrelid = child_table_name::regclass and tgname = 'fk_constraint_' ||child_table_name) THEN
    RAISE unique_violation USING MESSAGE = 'a trigger named fk_constraint_' || child_table_name || ' already exists';
  END IF;

  EXECUTE 'CREATE TRIGGER fk_constraint_' || child_table_name || ' BEFORE INSERT OR UPDATE ON ' || child_table_name || ' FOR EACH ROW
  EXECUTE PROCEDURE
  check_primary_key (
    ' || array_to_string(child_table_column_names, ',') || ',	-- name of foreign key column in triggered (B) table. You may use as
  				-- many columns as you need, but number of key columns in referenced
				-- table must be the same.
    ' || parent_table_name || ', -- referenced table name.
    ' || array_to_string(parent_table_column_names, ',') || ')';	
END IF;

RETURN TRUE;  
END; 
$function$
