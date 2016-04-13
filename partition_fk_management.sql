CREATE OR REPLACE FUNCTION public.create_fk_constraint(parent_table_name text, parent_table_column_names text, child_table_name text, child_table_column_names text, cascade boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN

--parent table
DROP TRIGGER IF EXISTS AT on create_fk_constraint.parent_table_name;

CREATE TRIGGER AT BEFORE DELETE OR UPDATE ON parent_table_name FOR EACH ROW
EXECUTE PROCEDURE
check_foreign_key (2, cascade, parent_table_column_names, child_table_name, child_table_column_names);

/*
2	- means that check must be performed for foreign keys of 2 tables.
cascade	- defines that corresponding keys must be deleted.
ID	- name of primary key column in triggered table (A). You may
	  use as many columns as you need.
B	- name of (first) table with foreign keys.
REFB	- name of foreign key column in this table. You may use as many
	  columns as you need, but number of key columns in referenced
	  table (A) must be the same.
C	- name of second table with foreign keys.
REFC	- name of foreign key column in this table.
*/

--child table
/*
CREATE TRIGGER BT BEFORE INSERT OR UPDATE ON B FOR EACH ROW
EXECUTE PROCEDURE
check_primary_key (REFB, A, ID);
*/
/*
REFB	- name of foreign key column in triggered (B) table. You may use as
	  many columns as you need, but number of key columns in referenced
	  table must be the same.
A	- referenced table name.
ID	- name of primary key column in referenced table.
:
*/
--Trigger for table C:
/*
CREATE TRIGGER CT BEFORE INSERT OR UPDATE ON C FOR EACH ROW
EXECUTE PROCEDURE
check_primary_key (REFC, A, ID);
*/
RETURN TRUE;  
END; 
$function$
