if (TARGET ch_contrib::hivemetastore)
    clickhouse_add_executable (comma_separated_streams comma_separated_streams.cpp)
    target_link_libraries (comma_separated_streams PRIVATE dbms)
endif()
