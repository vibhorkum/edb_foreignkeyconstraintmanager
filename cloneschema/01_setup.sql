CREATE SCHEMA edb_util AUTHORIZATION enterprisedb;

CREATE UNLOGGED TABLE edb_util.tracking (
  objname name NOT NULL
, objtype text NOT NULL
, decl text
, create_attempts integer NOT NULL DEFAULT (1)
, errmessage text
, is_created boolean NOT NULL DEFAULT (FALSE)

, CONSTRAINT pk_edb_util_tracking PRIMARY KEY (objname, objtype)
)
;

CREATE OR REPLACE FUNCTION edb_util.object_create_runner(
  object_name name, object_decl text
  , object_type text DEFAULT ''
  , ignore_duplicates boolean DEFAULT FALSE
  , verbose_bool boolean DEFAULT FALSE
)
RETURNS boolean AS $$
BEGIN
  RAISE NOTICE 'CREATING %: %', object_type, object_name;

  EXECUTE object_decl;

  IF EXISTS ( SELECT 1 from edb_util.tracking as t
    WHERE t.objname = objname AND t.objtype = objtype
  ) THEN
    UPDATE edb_util.tracking as t
       SET t.is_created = TRUE
         , t.create_attempts = t.create_attempts + 1
     WHERE t.objname = object_name
       and t.objtype = object_type
    ;
  ELSE
    INSERT INTO edb_util.tracking(objname, objtype, is_created)
    VALUES(object_name, object_type, TRUE)
    ;
  END IF;
  RETURN TRUE;

EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE '%', sqlerrm;

  IF EXISTS ( SELECT 1 from edb_util.tracking as t
    WHERE t.objname = object_name AND t.objtype = object_type
  ) THEN
    UPDATE edb_util.tracking as t
       SET t.errmessage = sqlerrm
         , t.create_attempts = t.create_attempts + 1
     WHERE t.objname = object_name AND t.objtype = object_type
    ;
  ELSE
    INSERT INTO edb_util.tracking(objname, objtype, decl, errmessage)
    VALUES(object_name, object_type, object_decl, sqlerrm)
    ;
  END IF;

  IF ignore_duplicates THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END IF;
WHEN others THEN
  RAISE NOTICE '% %', sqlstate, sqlerrm;

  IF EXISTS ( SELECT 1 from edb_util.tracking as t
    WHERE t.objname = object_name AND t.objtype = object_type
  ) THEN
    UPDATE edb_util.tracking as t
       SET t.errmessage = sqlerrm || ' ' || sqlstate::text
         , t.create_attempts = t.create_attempts + 1
     WHERE t.objname = object_name AND t.objtype = object_type
    ;
  ELSE
    INSERT INTO edb_util.tracking(objname, objtype, decl, errmessage)
    VALUES(object_name, object_type, object_decl
      , sqlerrm || ' ' || sqlstate::text)
    ;
  END IF;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql VOLATILE
;
