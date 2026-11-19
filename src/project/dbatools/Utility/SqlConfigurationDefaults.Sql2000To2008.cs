using System.Management.Automation;

namespace Dataplat.Dbatools.Utility
{
    public static partial class SqlConfigurationDefaults
    {
        private static void AddOptionsThroughFullText(PSObject defaults, int version)
        {
            Add(defaults, version, 10, 16, "access check cache bucket count", 0);
            Add(defaults, version, 10, 16, "access check cache quota", 0);
            Add(defaults, version, 9, 16, "Ad Hoc Distributed Queries", 0);
            Add(defaults, version, 15, 16, "ADR cleaner retry timeout (min)", version == 16 ? 15 : 0);
            Add(defaults, version, 16, 16, "ADR Cleaner Thread Count", 1);
            Add(defaults, version, 15, 16, "ADR Preallocation Factor", version == 16 ? 4 : 0);
            Add(defaults, version, 9, 16, "affinity I/O mask", 0);
            // The pinned tables move this property after affinity mask starting with version 14.
            Add(defaults, version, 9, 13, "affinity64 I/O mask", 0);
            Add(defaults, version, 8, 16, "affinity mask", 0);
            Add(defaults, version, 14, 16, "affinity64 I/O mask", 0);
            Add(defaults, version, 9, 16, "affinity64 mask", 0);
            Add(defaults, version, 9, 16, "Agent XPs", 0);
            Add(defaults, version, 15, 16, "allow filesystem enumeration", 1);
            Add(defaults, version, 13, 16, "allow polybase export", 0);
            Add(defaults, version, 8, 16, "allow updates", 0);
            Add(defaults, version, 8, 10, "awe enabled", 0);
            Add(defaults, version, 9, 9, "blocked process threshold", 0);
            Add(defaults, version, 13, 16, "automatic soft-NUMA disabled", 0);
            Add(defaults, version, 12, 16, "backup checksum default", 0);
            Add(defaults, version, 16, 16, "backup compression algorithm", 0);
            Add(defaults, version, 10, 16, "backup compression default", 0);
            Add(defaults, version, 10, 16, "blocked process threshold (s)", 0);
            Add(defaults, version, 8, 16, "c2 audit mode", 0);
            Add(defaults, version, 9, 16, "clr enabled", 0);
            Add(defaults, version, 14, 16, "clr strict security", version == 15 ? 0 : 1);
            Add(defaults, version, 15, 16, "column encryption enclave type", 0);
            Add(defaults, version, 9, 16, "common criteria compliance enabled", 0);
            Add(defaults, version, 11, 16, "contained database authentication", 0);
            Add(defaults, version, 8, 16, "cost threshold for parallelism", 5);
            Add(defaults, version, 8, 8, "Cross DB Ownership Chaining", 0);
            Add(defaults, version, 9, 16, "cross db ownership chaining", 0);
            Add(defaults, version, 8, 16, "cursor threshold", version == 15 ? 0 : -1);
            Add(defaults, version, 16, 16, "Data processed daily limit in TB", 2147483647);
            Add(defaults, version, 16, 16, "Data processed monthly limit in TB", 2147483647);
            Add(defaults, version, 16, 16, "Data processed weekly limit in TB", 2147483647);
            Add(defaults, version, 9, 16, "Database Mail XPs", 0);
            Add(defaults, version, 8, 16, "default full-text language", 1033);
            Add(defaults, version, 8, 16, "default language", 0);
            Add(defaults, version, 9, 16, "default trace enabled", version == 15 ? 0 : 1);
            Add(defaults, version, 9, 16, "disallow results from triggers", 0);
            Add(defaults, version, 10, 16, "EKM provider enabled", 0);
            Add(defaults, version, 13, 16, "external scripts enabled", 0);
            Add(defaults, version, 10, 16, "filestream access level", 0);
            Add(defaults, version, 8, 16, "fill factor (%)", 0);
            Add(defaults, version, 9, 16, "ft crawl bandwidth (max)", 100);
            Add(defaults, version, 9, 16, "ft crawl bandwidth (min)", 0);
            Add(defaults, version, 9, 16, "ft notify bandwidth (max)", 100);
            Add(defaults, version, 9, 16, "ft notify bandwidth (min)", 0);
        }
    }
}
