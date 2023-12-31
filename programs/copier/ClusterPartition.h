#pragma once

#include <base/types.h>
#include <map>

namespace DB
{

/// Contains info about all shards that contain a partition
struct ClusterPartition
{
    double elapsed_time_seconds = 0;
    UInt64 bytes_copied = 0;
    UInt64 rows_copied = 0;
    UInt64 blocks_copied = 0;

    UInt64 total_tries = 0;
};

using ClusterPartitions = std::map<String, ClusterPartition, std::greater<>>;

}
