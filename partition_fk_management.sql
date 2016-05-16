-- this requires the refint extension
CREATE EXTENSION IF NOT EXISTS REFINT;

CREATE OR REPLACE FUNCTION public.create_fk_constraint(parent_table_name regclass, parent_table_column_names text[], child_table_name regclass, child_table_column_names text[], cascade boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$

DECLARE
	tbl_name TEXT;
BEGIN

--  If Parent is non-partition and child is partitioned, then use ALTER TABLE add constraint.
IF NOT EXISTS (select 1 from ALL_PART_TABLES where ALL_PART_TABLES.table_name = upper(parent_table_name::TEXT)) THEN

  -- alter table ALTER TABLE PARENT ADD  FOREIGN KEY(T) REFERENCES CHILD(T);
  EXECUTE 'ALTER TABLE '|| parent_table_name || ' ADD  FOREIGN KEY(' || array_to_string(parent_table_column_names, ',') || ') 
  REFERENCES '|| child_table_name || '('|| array_to_string(child_table_column_names, ',') || ')';

ELSE

  --parent table
  IF EXISTS (select 1 from pg_trigger where not tgisinternal and tgrelid = parent_table_name::regclass and tgname = 'fk_constraint_' ||parent_table_name) THEN
    RAISE unique_violation USING MESSAGE = 'a trigger named fk_constraint_' || parent_table_name || ' already exists';
  END IF;
  EXECUTE 'CREATE TRIGGER fk_constraint_' || parent_table_name || ' BEFORE DELETE OR UPDATE ON ' || parent_table_name || ' FOR EACH ROW
  EXECUTE PROCEDURE
  check_foreign_key (
    1,  			-- number of tables that foreign keys need to be checked
    ' || cascade || ', 	-- boolean defines that corresponding keys must be deleted.
    ' || array_to_string(parent_table_column_names, ',') || ', 	-- name of primary key column in triggered table (A). 
 							-- You may use as many columns as you need.
    ' || child_table_name || ', 	-- name of (first) table with foreign keys.
    ' || array_to_string(child_table_column_names, ',') || ')'; 	-- name of foreign key column in this table. 
							-- You may use as many columns as you need, 
							-- but number of key columns in referenced table (A) 
							-- must be the same.
END IF;

--child table

-- if child is partitioned, check all part tables
IF EXISTS (select 1 from ALL_PART_TABLES where ALL_PART_TABLES.table_name = upper(child_table_name::TEXT)) THEN
  -- check all partitions
  FOR tbl_name in select partition_name from ALL_TAB_PARTITIONS where table_name = upper(child_table_name::TEXT) LOOP
  tbl_name = lower(tbl_name);

    -- if the trigger does not exists, create it
    IF NOT EXISTS (select 1 from pg_trigger where not tgisinternal and tgrelid = (child_table_name || '_' || tbl_name)::regclass and tgname = 'fk_constraint_' || child_table_name || '_' || tbl_name) THEN
 
    RAISE NOTICE 'no trigger on % named %.  creating', child_table_name || '_' || tbl_name, 'fk_constraint_' || child_table_name || '_' || tbl_name;
      EXECUTE 'CREATE TRIGGER fk_constraint_' || child_table_name || '_' || tbl_name || ' BEFORE INSERT OR UPDATE ON ' || child_table_name || '_' || tbl_name || ' FOR EACH ROW
      EXECUTE PROCEDURE
      check_primary_key (
       ' || array_to_string(child_table_column_names, ',') || ',	-- name of foreign key column in triggered (B) table. You may use as
   				-- many columns as you need, but number of key columns in referenced
				-- table must be the same.
       ' || parent_table_name || ', -- referenced table name.
       ' || array_to_string(parent_table_column_names, ',') || ')';	-- name of primary key column in referenced table. 
      END IF; 
  END LOOP;
END IF;

-- if trigger does not exist on child, create it
IF NOT EXISTS (select 1 from pg_trigger where not tgisinternal and tgrelid = child_table_name::regclass and tgname = 'fk_constraint_' || child_table_name) THEN
  EXECUTE 'CREATE TRIGGER fk_constraint_' || child_table_name || ' BEFORE INSERT OR UPDATE ON ' || child_table_name || ' FOR EACH ROW
  EXECUTE PROCEDURE
  check_primary_key (
    ' || array_to_string(child_table_column_names, ',') || ',	-- name of foreign key column in triggered (B) table. You may use as
  				-- many columns as you need, but number of key columns in referenced
				-- table must be the same.
    ' || parent_table_name || ', -- referenced table name.
    ' || array_to_string(parent_table_column_names, ',') || ')';	-- name of primary key column in referenced table.  

ELSE
  -- if it is not a partition table, throw error 
  IF NOT EXISTS (select 1 from ALL_PART_TABLES where ALL_PART_TABLES.table_name = upper(child_table_name::TEXT)) THEN
    RAISE unique_violation USING MESSAGE = 'a trigger named fk_constraint_' || child_table_name || ' already exists';
  END IF;

END IF;


RETURN TRUE;  
END; 
$function$
