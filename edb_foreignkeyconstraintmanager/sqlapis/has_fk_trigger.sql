/* function to verify if table has named trigger or not */

CREATE OR REPLACE FUNCTION edb_util.has_fk_trigger(trigger_name TEXT,table_name REGCLASS) 
RETURNS boolean
LANGUAGE sql
AS
$function$
  SELECT CASE WHEN COUNT(1) > 0 THEN TRUE ELSE FALSE END 
  FROM pg_trigger t WHERE NOT t.tgisinternal and t.tgrelid = table_name::OID and tgname = trigger_name 
$function$;



