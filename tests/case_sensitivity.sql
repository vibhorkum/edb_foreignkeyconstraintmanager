\i inialize_test.sql

\qecho "################ support case sensitive table names ####### ####################"
\qecho "#### https://github.com/EnterpriseDB/kronos_api/issues/22 ######################"
\qecho "################################################################################"

\qecho "select edb_util.create_fk_constraint('sales', '{order_no}', '"SalesNP"', '{order_no}', true);"
select edb_util.create_fk_constraint('sales', '{order_no}', '"SalesNP"', '{order_no}', true);


\qecho "select edb_util.create_fk_constraint('"SalesNP"', '{order_no}', 'sales', '{order_no}', true);"
select edb_util.create_fk_constraint('"SalesNP"', '{order_no}', 'sales', '{order_no}', true);

