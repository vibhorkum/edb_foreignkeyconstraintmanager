-- this requires the refint extension
CREATE EXTENSION IF NOT EXISTS REFINT;

CREATE OR REPLACE FUNCTION public.create_fk_constraint(parent_table_name regclass, parent_table_column_names text[], child_table_name regclass, child_table_column_names text[], cascade boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$

BEGIN

--  If Parent is non-partition and child is partitioned, then use ALTER TABLE add constraint.
IF EXISTS (select 1 from ALL_PART_TABLES where ALL_PART_TABLES.table_name = upper(parent_table_name::TEXT)) THEN

  -- alter table ALTER TABLE PARENT ADD  FOREIGN KEY(T) REFERENCES CHILD(T);
  EXECUTE 'ALTER TABLE PARENT ADD  FOREIGN KEY(' || array_to_string(parent_table_column_names, '.') || ') 
  REFERENCES '|| child_table_name || '('|| array_to_string(child_table_column_names, ',') || ')';
ELSE
  --parent table
  EXECUTE 'DROP TRIGGER IF EXISTS fk_constraint on ' || parent_table_name;

  EXECUTE 'CREATE TRIGGER fk_constraint BEFORE DELETE OR UPDATE ON ' || parent_table_name || ' FOR EACH ROW
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

EXECUTE 'DROP TRIGGER IF EXISTS fk_constraint on ' || child_table_name;

EXECUTE 'CREATE TRIGGER fk_constraint BEFORE INSERT OR UPDATE ON ' || child_table_name || ' FOR EACH ROW
EXECUTE PROCEDURE
check_primary_key (
  ' || array_to_string(child_table_column_names, ',') || ',	-- name of foreign key column in triggered (B) table. You may use as
				-- many columns as you need, but number of key columns in referenced
				-- table must be the same.
  ' || parent_table_name || ', -- referenced table name.
  ' || array_to_string(parent_table_column_names, ',') || ')';	-- name of primary key column in referenced table.  

RETURN TRUE;  
END; 
$function$
