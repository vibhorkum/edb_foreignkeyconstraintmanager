CREATE OR REPLACE FUNCTION clean_schema( tgt_fdw_server TEXT,
                                         tgt_user   TEXT,
                                        schemaname TEXT)
RETURNS boolean
LANGUAGE plpgsql
AS
$function$
DECLARE
  tgt_db_connection_sql TEXT := 'SELECT array_to_string (srvoptions,'' '' ) AS CONNECTION,
                                     (string_to_array(umoptions[1],''='' ))[2] AS USER,
                                     (string_to_array (umoptions[2],''=''))[2] AS PASSWORD
                              FROM pg_foreign_server s JOIN pg_user_mappings u ON 
                                   (s.srvname = u.srvname AND s.srvowner = u.umuser)
                              WHERE s.srvname = '||quote_literal(tgt_fdw_server)||' AND u.usename ='|| quote_literal(tgt_user) ;

  rec RECORD;
  tgt_conn_info TEXT;
  tgt_user_name TEXT;
  tgt_passwd TEXT;
  name_tag       TEXT;
BEGIN

   
   set edb_redwood_raw_names to on;
   EXECUTE tgt_db_connection_sql INTO rec;
   tgt_conn_info := rec.CONNECTION;
   tgt_user_name := rec.USER;
   tgt_passwd    := rec.PASSWORD;
   name_tag := to_char(now(),'YYYYDDMMHH24MISS');
   PERFORM dblink_connect( name_tag, tgt_conn_info ||' user='|| tgt_user_name||' password='|| tgt_passwd);
   
   -- drop all triggers
   FOR rec IN select DISTINCT trigger_name,schema_name||'.'||table_name as table_name FROM all_triggers WHERE schema_name=schemaname
   LOOP
      RAISE NOTICE '%','DROP TRIGGER IF EXISTS '||rec.trigger_name||' ON '||rec.table_name||' CASCADE;';
      PERFORM dblink_exec(name_tag,'DROP TRIGGER IF EXISTS '||rec.trigger_name||' ON '||rec.table_name||' CASCADE;');
   END LOOP;
   
   -- drop all constraints
   FOR rec IN SELECT DISTINCT constraint_name, schema_name||'.'||table_name as table_name FROM all_constraints WHERE schema_name=schemaname
   LOOP
      RAISE NOTICE '%','ALTER TABLE '||rec.table_name||' DROP CONSTRAINT IF EXISTS '||rec.constraint_name||' CASCADE;';
      PERFORM  dblink_exec(name_tag,'ALTER TABLE '||rec.table_name||' DROP CONSTRAINT IF EXISTS '||rec.constraint_name||' CASCADE;');
   END LOOP;

   -- DROP ALL procedures and packages and Functions 

  FOR rec IN SELECT DISTINCT type,name  from all_source WHERE schema_name = schemaname AND TYPE != 'TRIGGER' AND TYPE IN ('PROCEDURE','PACKAGE','PACKAGE BODY')
  LOOP
   IF rec.TYPE = 'PROCEDURE' THEN
    RAISE NOTICE '%', 'DROP '||rec.type||' '||schemaname||'.'||rec.name||';';
    PERFORM dblink_exec(name_tag, 'DROP '||rec.type||' '||schemaname||'.'||rec.name||';');
   ELSE
     RAISE NOTICE '%', 'DROP '||rec.type||' '||schemaname||'.'||rec.name||' CASCADE;';
     PERFORM dblink_exec(name_tag, 'DROP '||rec.type||' '||schemaname||'.'||rec.name||' CASCADE;');
   END IF;
  END LOOP;

 -- DROP all functions 
  FOR rec IN SELECT schemaname||'.'||proname||'('||edb_get_function_arguments(oid)||')' AS function_name from pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname=schemaname AND nspparent=0)
  LOOP
    RAISE NOTICE '%',  'DROP FUNCTION IF EXISTS '||rec.function_name||' CASCADE;';
    PERFORM dblink_exec(name_tag, 'DROP FUNCTION IF EXISTS '||rec.function_name||' CASCADE;');
  END LOOP;
  
   -- drop all indexes
    
   FOR rec IN SELECT DISTINCT schema_name ||'.'|| index_name as index_name FROM all_indexes WHERE schema_name=schemaname
   LOOP
     RAISE NOTICE '%','DROP INDEX IF EXISTS '||rec.index_name||' CASCADE;';

     PERFORM dblink_exec(name_tag,'DROP INDEX IF EXISTS '||rec.index_name||' CASCADE;');
   END LOOP;

      -- drop all views
    
   FOR rec IN SELECT DISTINCT schema_name ||'.'|| view_name as view_name FROM all_views WHERE schema_name=schemaname
   LOOP
     RAISE NOTICE '%','DROP VIEW IF EXISTS '||rec.view_name||' CASCADE;';

     PERFORM dblink_exec(name_tag,'DROP VIEW IF EXISTS '||rec.view_name||' CASCADE;');
   END LOOP;


   -- drop all tables
    
   FOR rec IN SELECT DISTINCT schema_name ||'.'|| table_name as table_name FROM all_tables WHERE schema_name=schemaname
   LOOP
     RAISE NOTICE '%', 'DROP TABLE IF EXISTS '||rec.table_name||' CASCADE;';
     PERFORM dblink_exec(name_tag,'DROP TABLE IF EXISTS '||rec.table_name||' CASCADE;');
   END LOOP;
   
   -- drop all sequences
    
   FOR rec IN SELECT DISTINCT schemaname||'.'||relname as sequence_name FROM pg_class WHERE relkind='S' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = schemaname)
   LOOP
     RAISE NOTICE '%','DROP SEQUENCE IF EXISTS '||rec.sequence_name||' CASCADE;';
     PERFORM dblink_exec(name_tag, 'DROP SEQUENCE IF EXISTS '||rec.sequence_name||' CASCADE;');
   END LOOP;
  
  -- drop all types 
  FOR rec IN SELECT DISTINCT type,name  from all_source WHERE schema_name = schemaname AND TYPE = 'TYPE'
  LOOP
   RAISE NOTICE '%', 'DROP '||rec.type||' '||schemaname||'.'||rec.name||';';
   PERFORM dblink_exec(name_tag, 'DROP '||rec.type||' '||schemaname||'.'||rec.name||' CASCADE;');
  END LOOP;

  RAISE NOTICE '%','DROP SCHEMA '||schemaname||' CASCADE;';
  PERFORM dblink_exec(name_tag, 'DROP SCHEMA '||schemaname||' CASCADE;');
  PERFORM dblink_disconnect( name_tag);
  RETURN true;
--   EXCEPTION 
--     WHEN OTHERS THEN
--           RAISE NOTICE 'Failed to clean schema';
--           PERFORM dblink_disconnect( name_tag);
--           RETURN false;
END;
$function$;
