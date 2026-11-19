using System.Management.Automation;

namespace Dataplat.Dbatools.Utility
{
    public static partial class SqlConfigurationDefaults
    {
        private static void AddRemainingOptions(PSObject defaults, int version)
        {
            Add(defaults, version, 9, 16, "Replication XPs", 0);
            Add(defaults, version, 8, 16, "scan for startup procs", 0);
            Add(defaults, version, 9, 16, "server trigger recursion", 1);
            Add(defaults, version, 8, 16, "set working set size", 0);
            Add(defaults, version, 8, 16, "show advanced options", version == 16 ? 1 : 0);
            Add(defaults, version, 9, 16, "SMO and DMO XPs", 1);
            Add(defaults, version, 9, 10, "SQL Mail XPs", 0);
            Add(defaults, version, 16, 16, "suppress recovery model errors", 0);
            Add(defaults, version, 15, 16, "tempdb metadata memory-optimized", 0);
            Add(defaults, version, 9, 16, "transform noise words", 0);
            Add(defaults, version, 8, 16, "two digit year cutoff", 2049);
            Add(defaults, version, 8, 16, "user connections", 0);
            Add(defaults, version, 9, 14, "User Instance Timeout", 60);
            Add(defaults, version, 9, 14, "user instances enabled", 0);
            Add(defaults, version, 8, 16, "user options", 0);
            Add(defaults, version, 9, 9, "Web Assistant Procedures", 0);
            Add(defaults, version, 16, 16, "version high part of SQL Server", 1048576);
            Add(defaults, version, 16, 16, "version low part of SQL Server", 65536006);
            Add(defaults, version, 9, 16, "xp_cmdshell", 0); // style-ok: sql-xp-cmdshell Pinned configuration key only; never executed.
        }
    }
}
