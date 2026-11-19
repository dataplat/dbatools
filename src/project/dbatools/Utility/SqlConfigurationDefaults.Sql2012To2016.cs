using System.Management.Automation;

namespace Dataplat.Dbatools.Utility
{
    public static partial class SqlConfigurationDefaults
    {
        private static void AddOptionsThroughRemoteQuery(PSObject defaults, int version)
        {
            Add(defaults, version, 13, 16, "hadoop connectivity", 0);
            Add(defaults, version, 16, 16, "hardware offload config", 0);
            Add(defaults, version, 16, 16, "hardware offload enabled", 0);
            Add(defaults, version, 16, 16, "hardware offload mode", 0);
            Add(defaults, version, 8, 16, "index create memory (KB)", 0);
            Add(defaults, version, 9, 16, "in-doubt xact resolution", 0);
            Add(defaults, version, 8, 16, "lightweight pooling", 0);
            Add(defaults, version, 8, 16, "locks", 0);
            Add(defaults, version, 8, 16, "max degree of parallelism", version == 16 ? 4 : 0);
            Add(defaults, version, 9, 16, "max full-text crawl range", 4);
            Add(defaults, version, 8, 16, "max server memory (MB)", 2147483647);
            Add(defaults, version, 8, 16, "max text repl size (B)", 65536);
            Add(defaults, version, 8, 16, "max worker threads", version == 8 ? 255 : 0);
            Add(defaults, version, 8, 16, "media retention", 0);
            Add(defaults, version, 8, 16, "min memory per query (KB)", 1024);
            Add(defaults, version, 8, 16, "min server memory (MB)", version == 9 ? 8 : 0);
            Add(defaults, version, 8, 16, "nested triggers", 1);
            Add(defaults, version, 8, 16, "network packet size (B)", 4096);
            Add(defaults, version, 9, 16, "Ole Automation Procedures", 0);
            Add(defaults, version, 8, 16, "open objects", 0);
            Add(defaults, version, 16, 16, "openrowset auto_create_statistics", 1);
            Add(defaults, version, 10, 16, "optimize for ad hoc workloads", 0);
            Add(defaults, version, 9, 16, "PH timeout (s)", 60);
            Add(defaults, version, 15, 16, "polybase enabled", 0);
            Add(defaults, version, 13, 16, "polybase network encryption", 1);
            Add(defaults, version, 9, 16, "precompute rank", 0);
            Add(defaults, version, 8, 16, "priority boost", 0);
            Add(defaults, version, 8, 16, "query governor cost limit", 0);
            Add(defaults, version, 8, 16, "query wait (s)", -1);
            Add(defaults, version, 8, 16, "recovery interval (min)", 0);
            Add(defaults, version, 8, 16, "remote access", 1);
            Add(defaults, version, 9, 16, "remote admin connections", 0);
            Add(defaults, version, 13, 16, "remote data archive", 0);
            Add(defaults, version, 8, 16, "remote login timeout (s)", version <= 10 ? 20 : 10);
            Add(defaults, version, 8, 16, "remote proc trans", 0);
            Add(defaults, version, 8, 16, "remote query timeout (s)", 600);
        }
    }
}
