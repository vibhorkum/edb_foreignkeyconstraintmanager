\i inialize_test.sql

\qecho "################ alow multiple keys on a partitioned parent ####################"
\qecho "#### https://github.com/EnterpriseDB/kronos_api/issues/22 ######################"
\qecho "################################################################################"

select edb_util.create_fk_constraint('sales', '{order_no}', "SalesNP", '{order_no}', true);

