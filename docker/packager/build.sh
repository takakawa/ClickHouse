#docker run -v  --network=host --user=0:0 --rm --volume=/var/clickhouse/ClickHouse/docker/packager/my_house:/output --volume=/var/clickhouse/ClickHouse:/build  -e OUTPUT_DIR=/output -e DEB_ARCH=amd64 -e CC=clang-16 -e CXX=clang++-16 -e SANITIZER=address -e BUILD_TYPE=None -e CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_C_COMPILER=clang-16 -DCMAKE_CXX_COMPILER=clang++-16 -DCOMPILER_CACHE=disabled" -e BUILD_TARGET='clickhouse-bundle' -it clickhouse/binary-builder:latest

./packager --output-dir=my_house --package-type binary --compiler=clang-16 --sanitizer=address
