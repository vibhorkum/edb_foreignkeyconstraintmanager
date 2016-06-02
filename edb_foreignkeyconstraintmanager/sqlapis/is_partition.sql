/* function to verify if table is partition or not */

CREATE OR REPLACE FUNCTION edb_util.is_partition(tablename REGCLASS) 
RETURNS boolean
LANGUAGE sql
AS
$function$
     SELECT CASE 
               WHEN count(1) = 1 THEN 
                 true 
               ELSE false END 
     FROM pg_catalog.edb_partdef p WHERE p.pdefrel = tablename::regclass::oid;
$function$;
