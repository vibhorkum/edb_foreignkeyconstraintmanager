\i inialize_test.sql

\qecho "################ alow multiple keys on a partitioned parent ####################"
\qecho "#### https://github.com/EnterpriseDB/kronos_api/issues/21 ######################"
\qecho "################################################################################"

select edb_util.create_fk_constraint('sales', '{order_no}', 'sales_np', '{order_no}', true);
\d+ sales_americas

select edb_util.create_fk_constraint('sales', '{order_no}', 'sales2_np', '{order_no}', true);
\d+ sales_americas
