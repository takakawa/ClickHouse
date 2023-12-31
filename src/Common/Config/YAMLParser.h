#pragma once

#include "config.h"

#include <Common/ErrorCodes.h>
#include <Common/Exception.h>
#include <base/types.h>
#include <Poco/DOM/Document.h>
#include <Poco/DOM/AutoPtr.h>

#if USE_YAML_CPP

namespace DB
{

/// Real YAML parser: loads yaml file into a YAML::Node
class YAMLParserImpl
{
public:
    static Poco::AutoPtr<Poco::XML::Document> parse(const String& path);
};

using YAMLParser = YAMLParserImpl;

}

#else

namespace DB
{

namespace ErrorCodes
{
    extern const int CANNOT_PARSE_YAML;
}

/// Fake YAML parser: throws an exception if we try to parse YAML configs in a build without yaml-cpp
class DummyYAMLParser
{
public:
    static Poco::AutoPtr<Poco::XML::Document> parse(const String& path)
    {
        Poco::AutoPtr<Poco::XML::Document> xml = new Poco::XML::Document;
        throw Exception(ErrorCodes::CANNOT_PARSE_YAML, "Unable to parse YAML configuration file {} without usage of yaml-cpp library", path);
        return xml;
    }
};

using YAMLParser = DummyYAMLParser;

}

#endif
