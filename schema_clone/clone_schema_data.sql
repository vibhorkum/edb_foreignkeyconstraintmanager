CREATE OR REPLACE FUNCTION remote_table_copy_data(src_fdw_server TEXT, 
                                              remote_user TEXT,   
                                              tgt_fdw_server TEXT,
                                              tgt_user   TEXT,
                                              db_snapshot_id TEXT, 
                                              pg_home TEXT,
                                              src_table_name TEXT, 
                                              tgt_table_name TEXT)
RETURNS boolean
LANGUAGE plpgsql
AS
$function$
DECLARE
   src_db_connection_sql TEXT := 'SELECT array_to_string (srvoptions,'' '' ) AS CONNECTION,
                                     (string_to_array(umoptions[1],''='' ))[2] AS USER,
                                     (string_to_array (umoptions[2],''=''))[2] AS PASSWORD
                              FROM pg_foreign_server s JOIN pg_user_mappings u ON 
                                   (s.srvname = u.srvname AND s.srvowner = u.umuser)
                              WHERE s.srvname = '||quote_literal(src_fdw_server)||' AND u.usename ='|| quote_literal(remote_user) ;
   tgt_db_connection_sql TEXT := 'SELECT array_to_string (srvoptions,'' '' ) AS CONNECTION,
                                     (string_to_array(umoptions[1],''='' ))[2] AS USER,
                                     (string_to_array (umoptions[2],''=''))[2] AS PASSWORD
                              FROM pg_foreign_server s JOIN pg_user_mappings u ON 
                                   (s.srvname = u.srvname AND s.srvowner = u.umuser)
                              WHERE s.srvname = '||quote_literal(tgt_fdw_server)||' AND u.usename ='|| quote_literal(tgt_user) ;

   src_conn_info TEXT;
   src_user_name TEXT;
   src_passwd TEXT;
   tgt_conn_info TEXT;
   tgt_user_name TEXT;
   tgt_passwd TEXT;
   pg_dump_command TEXT := pg_home||'/bin/pg_dump';
   psql_command    TEXT := pg_home||'/bin/psql';
   copy_command TEXT;
   rec          RECORD;
   copy_src_sql TEXT;
   copy_tgt_sql TEXT;
   psql_sql_src TEXT;
   psql_sql_tgt TEXT;
   snapshot_sql TEXT;
BEGIN
   CREATE TEMP TABLE copy_log_table(log TEXT);
   EXECUTE src_db_connection_sql INTO rec;
   src_conn_info := rec.CONNECTION;
   src_user_name := rec.USER;
   src_passwd    := rec.PASSWORD;


   EXECUTE tgt_db_connection_sql INTO rec;
   tgt_conn_info := rec.CONNECTION;
   tgt_user_name := rec.USER;
   tgt_passwd    := rec.PASSWORD;

   snapshot_sql  := format('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ; SET TRANSACTION SNAPSHOT %L;',db_snapshot_id);
   copy_src_sql  := format('COPY %s TO STDOUT',src_table_name);
   copy_tgt_sql  := format('COPY %s FROM STDIN',tgt_table_name);
   psql_sql_src  := format('PGUSER=%s PGPASSWORD=%s %s "%s" -c ',src_user_name,src_passwd,psql_command,src_conn_info);
   psql_sql_tgt  := format('PGUSER=%s PGPASSWORD=%s %s "%s" -c ',tgt_user_name,tgt_passwd,psql_command,tgt_conn_info);

 
   copy_command  := 'COPY copy_log_table FROM program '||quote_literal(psql_sql_src||'"'||snapshot_sql||copy_src_sql||'"|'||psql_sql_tgt||'"'||copy_tgt_sql||'"');
   RAISE NOTICE 'copying table: %', tgt_table_name;
   EXECUTE copy_command;
   DROP TABLE copy_log_table;
   RETURN TRUE;
   EXCEPTION 
       WHEN OTHERS THEN
         RAISE EXCEPTION '%', 'failed to load to data in schema '||tgt_schema|| ' please check server log file for more information';
         DROP TABLE copy_log_table;
         RETURN false;
END;
$function$;

