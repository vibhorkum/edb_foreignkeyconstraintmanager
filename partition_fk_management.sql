CREATE OR REPLACE FUNCTION public.create_fk_constraint(parent_table_name regclass, parent_table_column_names text, child_table_name regclass, child_table_column_names text, cascade boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$

BEGIN
--parent table
EXECUTE 'DROP TRIGGER IF EXISTS fk_constraint on ' || parent_table_name;

EXECUTE 'CREATE TRIGGER fk_constraint BEFORE DELETE OR UPDATE ON ' || parent_table_name || ' FOR EACH ROW
EXECUTE PROCEDURE
check_foreign_key (
  1,  			-- number of tables that foreign keys need to be checked
  ' || cascade || ', 	-- boolean defines that corresponding keys must be deleted.
  ' || quote_ident(parent_table_column_names) || ', 	-- name of primary key column in triggered table (A). 
							-- You may use as many columns as you need.
  ' || child_table_name || ', 	-- name of (first) table with foreign keys.
  ' || quote_ident(child_table_column_names) || ')'; 	-- name of foreign key column in this table. 
							-- You may use as many columns as you need, 
							-- but number of key columns in referenced table (A) 
							-- must be the same.

--child table

EXECUTE 'DROP TRIGGER IF EXISTS fk_constraint on ' || child_table_name;

EXECUTE 'CREATE TRIGGER fk_constraint BEFORE INSERT OR UPDATE ON ' || child_table_name || ' FOR EACH ROW
EXECUTE PROCEDURE
check_primary_key (
  ' || child_table_column_names || ',	-- name of foreign key column in triggered (B) table. You may use as
				-- many columns as you need, but number of key columns in referenced
				-- table must be the same.
  ' || parent_table_name || ', -- referenced table name.
  ' || parent_table_column_names || ')';	-- name of primary key column in referenced table.  

RETURN TRUE;  
END; 
$function$
