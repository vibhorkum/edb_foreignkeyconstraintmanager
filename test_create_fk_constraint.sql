-- create tables

DROP TABLE IF EXISTS sales;

CREATE TABLE sales
(
  order_no    number PRIMARY KEY,
  dept_no     number,
  part_no     varchar2,
  country     varchar2(20),
  date        date,
  amount      number
)
PARTITION BY RANGE(date)
  SUBPARTITION BY LIST(country)
  (
    PARTITION q1_2012 
      VALUES LESS THAN('2012-Apr-01')
      (
        SUBPARTITION q1_europe VALUES ('FRANCE', 'ITALY'),
        SUBPARTITION q1_asia VALUES ('INDIA', 'PAKISTAN'),
        SUBPARTITION q1_americas VALUES ('US', 'CANADA')
       ),
  PARTITION q2_2012 
    VALUES LESS THAN('2012-Jul-01')
      (
        SUBPARTITION q2_europe VALUES ('FRANCE', 'ITALY'),
        SUBPARTITION q2_asia VALUES ('INDIA', 'PAKISTAN'),
        SUBPARTITION q2_americas VALUES ('US', 'CANADA')
       ),
  PARTITION q3_2012 
    VALUES LESS THAN('2012-Oct-01')
      (
        SUBPARTITION q3_europe VALUES ('FRANCE', 'ITALY'),
        SUBPARTITION q3_asia VALUES ('INDIA', 'PAKISTAN'),
        SUBPARTITION q3_americas VALUES ('US', 'CANADA')
       ),
  PARTITION q4_2012 
    VALUES LESS THAN('2013-Jan-01')      
      (
        SUBPARTITION q4_europe VALUES ('FRANCE', 'ITALY'),
        SUBPARTITION q4_asia VALUES ('INDIA', 'PAKISTAN'),
        SUBPARTITION q4_americas VALUES ('US', 'CANADA')
       )
);
-- create function

\i partition_fk_management.sql

\qecho "################ creating constraint on partitioned child ######################"
\qecho "################################################################################"

select create_fk_constraint('sales', '{order_no}', 'sales_q1_2012', '{order_no}', true);
\d+ sales
\d+ sales_q1_2012

\qecho "################# create constrain on non partitioned parent ###################"
\qecho "################################################################################"

select create_fk_constraint('sales_q1_americas', '{order_no}', 'sales', '{order_no}', true);

\d+ sales
\d+ sales_q1_americas

