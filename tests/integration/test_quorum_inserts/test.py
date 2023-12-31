import time

import pytest
from helpers.cluster import ClickHouseCluster
from helpers.test_tools import TSV

cluster = ClickHouseCluster(__file__)

zero = cluster.add_instance(
    "zero",
    user_configs=["configs/users.d/settings.xml"],
    main_configs=["configs/config.d/remote_servers.xml"],
    macros={"cluster": "anime", "shard": "0", "replica": "zero"},
    with_zookeeper=True,
)

first = cluster.add_instance(
    "first",
    user_configs=["configs/users.d/settings.xml"],
    main_configs=["configs/config.d/remote_servers.xml"],
    macros={"cluster": "anime", "shard": "0", "replica": "first"},
    with_zookeeper=True,
)

second = cluster.add_instance(
    "second",
    user_configs=["configs/users.d/settings.xml"],
    main_configs=["configs/config.d/remote_servers.xml"],
    macros={"cluster": "anime", "shard": "0", "replica": "second"},
    with_zookeeper=True,
)


@pytest.fixture(scope="module")
def started_cluster():
    global cluster
    try:
        cluster.start()
        yield cluster

    finally:
        cluster.shutdown()


def test_simple_add_replica(started_cluster):
    zero.query("DROP TABLE IF EXISTS test_simple ON CLUSTER cluster")

    create_query = (
        "CREATE TABLE test_simple "
        "(a Int8, d Date) "
        "Engine = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}') "
        "PARTITION BY d ORDER BY a"
    )

    zero.query(create_query)
    first.query(create_query)

    first.query("SYSTEM STOP FETCHES test_simple")

    zero.query(
        "INSERT INTO test_simple VALUES (1, '2011-01-01')",
        settings={"insert_quorum": 1},
    )

    assert "1\t2011-01-01\n" == zero.query("SELECT * from test_simple")
    assert "" == first.query("SELECT * from test_simple")

    first.query("SYSTEM START FETCHES test_simple")

    first.query("SYSTEM SYNC REPLICA test_simple", timeout=20)

    assert "1\t2011-01-01\n" == zero.query("SELECT * from test_simple")
    assert "1\t2011-01-01\n" == first.query("SELECT * from test_simple")

    second.query(create_query)
    second.query("SYSTEM SYNC REPLICA test_simple", timeout=20)

    assert "1\t2011-01-01\n" == zero.query("SELECT * from test_simple")
    assert "1\t2011-01-01\n" == first.query("SELECT * from test_simple")
    assert "1\t2011-01-01\n" == second.query("SELECT * from test_simple")

    zero.query("DROP TABLE IF EXISTS test_simple ON CLUSTER cluster")


def test_drop_replica_and_achieve_quorum(started_cluster):
    zero.query(
        "DROP TABLE IF EXISTS test_drop_replica_and_achieve_quorum ON CLUSTER cluster"
    )

    create_query = (
        "CREATE TABLE test_drop_replica_and_achieve_quorum "
        "(a Int8, d Date) "
        "Engine = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}') "
        "PARTITION BY d ORDER BY a"
    )

    print("Create Replicated table with two replicas")
    zero.query(create_query)
    first.query(create_query)

    print("Stop fetches on one replica. Since that, it will be isolated.")
    first.query("SYSTEM STOP FETCHES test_drop_replica_and_achieve_quorum")

    print("Insert to other replica. This query will fail.")
    quorum_timeout = zero.query_and_get_error(
        "INSERT INTO test_drop_replica_and_achieve_quorum(a,d) VALUES (1, '2011-01-01')",
        settings={"insert_quorum_timeout": 5000},
    )
    assert "Timeout while waiting for quorum" in quorum_timeout, "Query must fail."

    assert TSV("1\t2011-01-01\n") == TSV(
        zero.query(
            "SELECT * FROM test_drop_replica_and_achieve_quorum",
            settings={"select_sequential_consistency": 0},
        )
    )

    assert TSV("") == TSV(
        zero.query(
            "SELECT * FROM test_drop_replica_and_achieve_quorum",
            settings={"select_sequential_consistency": 1},
        )
    )

    # TODO:(Mikhaylov) begin; maybe delete this lines. I want clickhouse to fetch parts and update quorum.
    print("START FETCHES first replica")
    first.query("SYSTEM START FETCHES test_drop_replica_and_achieve_quorum")

    print("SYNC first replica")
    first.query("SYSTEM SYNC REPLICA test_drop_replica_and_achieve_quorum", timeout=20)
    # TODO:(Mikhaylov) end

    print("Add second replica")
    second.query(create_query)

    print("SYNC second replica")
    second.query("SYSTEM SYNC REPLICA test_drop_replica_and_achieve_quorum", timeout=20)

    print("Quorum for previous insert achieved.")
    assert TSV("1\t2011-01-01\n") == TSV(
        second.query(
            "SELECT * FROM test_drop_replica_and_achieve_quorum",
            settings={"select_sequential_consistency": 1},
        )
    )


@pytest.mark.parametrize(("add_new_data"), [False, True])
def test_insert_quorum_with_drop_partition(started_cluster, add_new_data):
    zero.query(
        "DROP TABLE IF EXISTS test_quorum_insert_with_drop_partition ON CLUSTER cluster"
    )

    create_query = (
        "CREATE TABLE test_quorum_insert_with_drop_partition ON CLUSTER cluster "
        "(a Int8, d Date) "
        "Engine = ReplicatedMergeTree "
        "PARTITION BY d ORDER BY a "
    )

    print("Create Replicated table with three replicas")
    zero.query(create_query)

    print("Stop fetches for test_quorum_insert_with_drop_partition at first replica.")
    first.query("SYSTEM STOP FETCHES test_quorum_insert_with_drop_partition")

    print("Insert with quorum. (zero and second)")
    zero.query(
        "INSERT INTO test_quorum_insert_with_drop_partition(a,d) VALUES(1, '2011-01-01')"
    )

    print("Drop partition.")
    zero.query(
        "ALTER TABLE test_quorum_insert_with_drop_partition DROP PARTITION '2011-01-01'"
    )

    if add_new_data:
        print("Insert to deleted partition")
        zero.query(
            "INSERT INTO test_quorum_insert_with_drop_partition(a,d) VALUES(2, '2011-01-01')"
        )

    print("Resume fetches for test_quorum_insert_with_drop_partition at first replica.")
    first.query("SYSTEM START FETCHES test_quorum_insert_with_drop_partition")

    print("Sync first replica with others.")
    first.query("SYSTEM SYNC REPLICA test_quorum_insert_with_drop_partition")

    assert "20110101" not in first.query(
        """
    WITH (SELECT toString(uuid) FROM system.tables WHERE name = 'test_quorum_insert_with_drop_partition') AS uuid,
         '/clickhouse/tables/' || uuid || '/0/quorum/last_part' AS p
    SELECT * FROM system.zookeeper WHERE path = p FORMAT Vertical
    """
    )

    print("Select from updated partition.")
    if add_new_data:
        assert TSV("2\t2011-01-01\n") == TSV(
            zero.query("SELECT * FROM test_quorum_insert_with_drop_partition")
        )
        assert TSV("2\t2011-01-01\n") == TSV(
            second.query("SELECT * FROM test_quorum_insert_with_drop_partition")
        )
    else:
        assert TSV("") == TSV(
            zero.query("SELECT * FROM test_quorum_insert_with_drop_partition")
        )
        assert TSV("") == TSV(
            second.query("SELECT * FROM test_quorum_insert_with_drop_partition")
        )

    zero.query(
        "DROP TABLE IF EXISTS test_quorum_insert_with_drop_partition ON CLUSTER cluster"
    )


@pytest.mark.parametrize(("add_new_data"), [False, True])
def test_insert_quorum_with_move_partition(started_cluster, add_new_data):
    zero.query(
        "DROP TABLE IF EXISTS test_insert_quorum_with_move_partition_source ON CLUSTER cluster"
    )
    zero.query(
        "DROP TABLE IF EXISTS test_insert_quorum_with_move_partition_destination ON CLUSTER cluster"
    )

    create_source = (
        "CREATE TABLE test_insert_quorum_with_move_partition_source ON CLUSTER cluster "
        "(a Int8, d Date) "
        "Engine = ReplicatedMergeTree "
        "PARTITION BY d ORDER BY a "
    )

    create_destination = (
        "CREATE TABLE test_insert_quorum_with_move_partition_destination ON CLUSTER cluster "
        "(a Int8, d Date) "
        "Engine = ReplicatedMergeTree "
        "PARTITION BY d ORDER BY a "
    )

    print("Create source Replicated table with three replicas")
    zero.query(create_source)

    print("Create destination Replicated table with three replicas")
    zero.query(create_destination)

    print(
        "Stop fetches for test_insert_quorum_with_move_partition_source at first replica."
    )
    first.query("SYSTEM STOP FETCHES test_insert_quorum_with_move_partition_source")

    print("Insert with quorum. (zero and second)")
    zero.query(
        "INSERT INTO test_insert_quorum_with_move_partition_source(a,d) VALUES(1, '2011-01-01')"
    )

    print("Drop partition.")
    zero.query(
        "ALTER TABLE test_insert_quorum_with_move_partition_source MOVE PARTITION '2011-01-01' TO TABLE test_insert_quorum_with_move_partition_destination"
    )

    if add_new_data:
        print("Insert to deleted partition")
        zero.query(
            "INSERT INTO test_insert_quorum_with_move_partition_source(a,d) VALUES(2, '2011-01-01')"
        )

    print(
        "Resume fetches for test_insert_quorum_with_move_partition_source at first replica."
    )
    first.query("SYSTEM START FETCHES test_insert_quorum_with_move_partition_source")

    print("Sync first replica with others.")
    first.query("SYSTEM SYNC REPLICA test_insert_quorum_with_move_partition_source")

    assert "20110101" not in first.query(
        """
    WITH (SELECT toString(uuid) FROM system.tables WHERE name = 'test_insert_quorum_with_move_partition_source') AS uuid,
         '/clickhouse/tables/' || uuid || '/0/quorum/last_part' AS p
    SELECT * FROM system.zookeeper WHERE path = p FORMAT Vertical
    """
    )

    print("Select from updated partition.")
    if add_new_data:
        assert TSV("2\t2011-01-01\n") == TSV(
            zero.query("SELECT * FROM test_insert_quorum_with_move_partition_source")
        )
        assert TSV("2\t2011-01-01\n") == TSV(
            second.query("SELECT * FROM test_insert_quorum_with_move_partition_source")
        )
    else:
        assert TSV("") == TSV(
            zero.query("SELECT * FROM test_insert_quorum_with_move_partition_source")
        )
        assert TSV("") == TSV(
            second.query("SELECT * FROM test_insert_quorum_with_move_partition_source")
        )

    zero.query(
        "DROP TABLE IF EXISTS test_insert_quorum_with_move_partition_source ON CLUSTER cluster"
    )
    zero.query(
        "DROP TABLE IF EXISTS test_insert_quorum_with_move_partition_destination ON CLUSTER cluster"
    )


def test_insert_quorum_with_ttl(started_cluster):
    zero.query("DROP TABLE IF EXISTS test_insert_quorum_with_ttl ON CLUSTER cluster")

    create_query = (
        "CREATE TABLE test_insert_quorum_with_ttl "
        "(a Int8, d Date) "
        "Engine = ReplicatedMergeTree('/clickhouse/tables/{table}', '{replica}') "
        "PARTITION BY d ORDER BY a "
        "TTL d + INTERVAL 5 second DELETE WHERE toYear(d) = 2011 "
        "SETTINGS merge_with_ttl_timeout=2 "
    )

    print("Create Replicated table with two replicas")
    zero.query(create_query)
    first.query(create_query)

    print("Stop fetches for test_insert_quorum_with_ttl at first replica.")
    first.query("SYSTEM STOP FETCHES test_insert_quorum_with_ttl")

    print("Insert should fail since it can not reach the quorum.")
    quorum_timeout = zero.query_and_get_error(
        "INSERT INTO test_insert_quorum_with_ttl(a,d) VALUES(1, '2011-01-01')",
        settings={"insert_quorum_timeout": 5000},
    )
    assert "Timeout while waiting for quorum" in quorum_timeout, "Query must fail."

    print(
        "Wait 10 seconds and TTL merge have to be executed. But it won't delete data."
    )
    time.sleep(10)
    assert TSV("1\t2011-01-01\n") == TSV(
        zero.query(
            "SELECT * FROM test_insert_quorum_with_ttl",
            settings={"select_sequential_consistency": 0},
        )
    )

    print("Resume fetches for test_insert_quorum_with_ttl at first replica.")
    first.query("SYSTEM START FETCHES test_insert_quorum_with_ttl")

    print("Sync first replica.")
    first.query("SYSTEM SYNC REPLICA test_insert_quorum_with_ttl")

    zero.query(
        "INSERT INTO test_insert_quorum_with_ttl(a,d) VALUES(1, '2011-01-01')",
        settings={"insert_quorum_timeout": 5000},
    )

    print("Inserts should resume.")
    zero.query("INSERT INTO test_insert_quorum_with_ttl(a, d) VALUES(2, '2012-02-02')")

    first.query("OPTIMIZE TABLE test_insert_quorum_with_ttl")
    first.query("SYSTEM SYNC REPLICA test_insert_quorum_with_ttl")
    zero.query("SYSTEM SYNC REPLICA test_insert_quorum_with_ttl")

    assert TSV("2\t2012-02-02\n") == TSV(
        first.query(
            "SELECT * FROM test_insert_quorum_with_ttl",
            settings={"select_sequential_consistency": 0},
        )
    )
    assert TSV("2\t2012-02-02\n") == TSV(
        first.query(
            "SELECT * FROM test_insert_quorum_with_ttl",
            settings={"select_sequential_consistency": 1},
        )
    )

    zero.query("DROP TABLE IF EXISTS test_insert_quorum_with_ttl ON CLUSTER cluster")
