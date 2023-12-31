-- Tags: distributed, no-parallel

CREATE DATABASE IF NOT EXISTS shard_0;
CREATE DATABASE IF NOT EXISTS shard_1;
CREATE DATABASE IF NOT EXISTS main_01487;
CREATE DATABASE IF NOT EXISTS test_01487;

USE main_01487;

DROP TABLE IF EXISTS shard_0.l;
DROP TABLE IF EXISTS shard_1.l;
DROP TABLE IF EXISTS d;
DROP TABLE IF EXISTS t;

CREATE TABLE shard_0.l (value UInt8) ENGINE = MergeTree ORDER BY value;
CREATE TABLE shard_1.l (value UInt8) ENGINE = MergeTree ORDER BY value;
CREATE TABLE t (value UInt8) ENGINE = Memory;

INSERT INTO shard_0.l VALUES (0);
INSERT INTO shard_1.l VALUES (1);
INSERT INTO t VALUES (0), (1), (2);

CREATE TABLE d AS t ENGINE = Distributed(test_cluster_two_shards_different_databases, currentDatabase(), t);

USE test_01487;
DROP DATABASE test_01487;

-- After the default database is dropped QueryAnalysisPass cannot process the following SELECT query.
-- That query is invalid on the initiator node.
set allow_experimental_analyzer = 0;

SELECT * FROM main_01487.d WHERE value IN (SELECT l.value FROM l) ORDER BY value;

USE main_01487;

DROP TABLE IF EXISTS shard_0.l;
DROP TABLE IF EXISTS shard_1.l;
DROP TABLE IF EXISTS d;
DROP TABLE IF EXISTS t;

DROP DATABASE shard_0;
DROP DATABASE shard_1;
DROP DATABASE main_01487;
