#pragma once

#include <IO/BufferWithOwnMemory.h>
#include <IO/SeekableReadBuffer.h>
#include <IO/WithFileName.h>
#include <Interpreters/Context_fwd.h>
#include <base/time.h>

#include <functional>
#include <utility>
#include <string>

#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>

#ifndef O_DIRECT
#define O_DIRECT 00040000
#endif


namespace DB
{

class ReadBufferFromFileBase : public BufferWithOwnMemory<SeekableReadBuffer>, public WithFileName, public WithFileSize
{
public:
    ReadBufferFromFileBase();
    ReadBufferFromFileBase(
        size_t buf_size,
        char * existing_memory,
        size_t alignment,
        std::optional<size_t> file_size_ = std::nullopt);
    ~ReadBufferFromFileBase() override;

    /// It is possible to get information about the time of each reading.
    struct ProfileInfo
    {
        size_t bytes_requested;
        size_t bytes_read;
        size_t nanoseconds;
    };

    using ProfileCallback = std::function<void(ProfileInfo)>;

    /// CLOCK_MONOTONIC_COARSE is more than enough to track long reads - for example, hanging for a second.
    void setProfileCallback(const ProfileCallback & profile_callback_, clockid_t clock_type_ = CLOCK_MONOTONIC_COARSE)
    {
        profile_callback = profile_callback_;
        clock_type = clock_type_;
    }

    size_t getFileSize() override;

    void setProgressCallback(ContextPtr context);

protected:
    std::optional<size_t> file_size;
    ProfileCallback profile_callback;
    clockid_t clock_type{};
};

}
