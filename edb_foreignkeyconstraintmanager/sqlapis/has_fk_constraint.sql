/* function to check if table has foreign key or not */
CREATE OR REPLACE FUNCTION edb_util.has_fk_constraint(child REGCLASS,child_col_list TEXT,parent REGCLASS, parent_col_list TEXT) 
RETURNS boolean
LANGUAGE sql
AS
$function$
  SELECT CASE WHEN COUNT(1) > 0 THEN TRUE ELSE FALSE END 
  FROM pg_constraint c WHERE c.conrelid=child::OID AND c.contype = 'f' AND 
        pg_get_constraintdef(c.oid) = format('FOREIGN KEY (%s) REFERENCES %I(%s)',child_col_list,parent::TEXT,parent_col_list)
$function$;

