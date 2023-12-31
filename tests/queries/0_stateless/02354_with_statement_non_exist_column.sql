DROP TEMPORARY TABLE IF EXISTS t1;
DROP TEMPORARY TABLE IF EXISTS t2;

CREATE TEMPORARY TABLE t1 (a Int64);
CREATE TEMPORARY TABLE t2 (a Int64, b Int64);

WITH b AS bb SELECT bb FROM t2 WHERE a IN (SELECT a FROM t1);
