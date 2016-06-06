/* function to list all partitioned table list */
CREATE OR REPLACE FUNCTION edb_util.get_partition_list(tablename REGCLASS)
RETURNS SETOF OID
LANGUAGE sql
AS
$function$
  SELECT p.partrelid FROM pg_catalog.edb_partition p, pg_catalog.edb_partdef d 
                       WHERE (p.partpdefid = d.oid) AND d.pdefrel=tablename::OID
$function$;


