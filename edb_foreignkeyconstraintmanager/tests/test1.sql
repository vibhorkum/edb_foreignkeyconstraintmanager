\i inialize_test.sql

\qecho "################ non partitioned parent, partitioned child #####################"
\qecho "################################################################################"

select edb_util.create_fk_constraint('sales_np', '{order_no}', 'sales', '{order_no}', 'cascade');
\d+ sales
\d+ sales_europe
\d+ sales_asia
\d+ sales_americas

\qecho "################ adding partition to child #####################################"
\qecho "################################################################################"

ALTER TABLE sales ADD PARTITION east_asia VALUES ('CHINA', 'KOREA');

\qecho "################ new partition before running create_fk_constraint #############"
\qecho "################################################################################"
\d+ sales_east_asia

select edb_util.create_fk_constraint('sales_np', '{order_no}', 'sales', '{order_no}', 'cascade');
\qecho "################ new partition before running create_fk_constraint #############"
\qecho "################################################################################"

\d+ sales_east_asia
\d+ sales_americas

