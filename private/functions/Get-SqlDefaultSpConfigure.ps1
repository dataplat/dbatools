function Get-SqlDefaultSpConfigure {
    <#
        .SYNOPSIS
        Internal function. Returns the default sp_configure options for a given version of SQL Server.

        .NOTES
        Server Configuration Options BOL (links subject to change):
        SQL Server 2019 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.150).aspx
        SQL Server 2017 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.140).aspx
        SQL Server 2016 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.130).aspx
        SQL Server 2014 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.120).aspx
        SQL Server 2012 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.110).aspx
        SQL Server 2008 R2 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.105).aspx
        SQL Server 2008 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.100).aspx
        SQL Server 2005 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.90).aspx
        SQL Server 2000 - http://technet.microsoft.com/en-us/library/aa196706(v=sql.80).aspx (requires PDF download)

        .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns a PSCustomObject containing default sp_configure values for the specified SQL Server version.
        Each sp_configure option name is returned as a property with its default value.

        The number and names of properties vary by SQL Server version:
        - SQL 2000 (v8): ~33 configuration options
        - SQL 2005 (v9): ~61 configuration options
        - SQL 2008/R2 (v10): ~69 configuration options
        - SQL 2012+ (v11+): 71+ configuration options (additional options added in newer versions)

        Common properties across all versions include:
        - "cost threshold for parallelism"
        - "max degree of parallelism"
        - "max server memory (MB)"
        - "min server memory (MB)"
        - "show advanced options"

        .EXAMPLE
        Get-SqlDefaultSpConfigure -SqlVersion 11
        Returns a list of sp_configure (sys.configurations) items for SQL 2012.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("Version")]
        [object]$SqlVersion
    )

    switch ($SqlVersion) {

        #region SQL2000
        8 {
            [pscustomobject]@{
                "affinity mask"                  = 0
                "allow updates"                  = 0
                "awe enabled"                    = 0
                "c2 audit mode"                  = 0
                "cost threshold for parallelism" = 5
                "Cross DB Ownership Chaining"    = 0
                "cursor threshold"               = -1
                "default full-text language"     = 1033
                "default language"               = 0
                "fill factor (%)"                = 0
                "index create memory (KB)"       = 0
                "lightweight pooling"            = 0
                "locks"                          = 0
                "max degree of parallelism"      = 0
                "max server memory (MB)"         = 2147483647
                "max text repl size (B)"         = 65536
                "max worker threads"             = 255
                "media retention"                = 0
                "min memory per query (KB)"      = 1024
                "min server memory (MB)"         = 0
                "nested triggers"                = 1
                "network packet size (B)"        = 4096
                "open objects"                   = 0
                "priority boost"                 = 0
                "query governor cost limit"      = 0
                "query wait (s)"                 = -1
                "recovery interval (min)"        = 0
                "remote access"                  = 1
                "remote login timeout (s)"       = 20
                "remote proc trans"              = 0
                "remote query timeout (s)"       = 600
                "scan for startup procs"         = 0
                "set working set size"           = 0
                "show advanced options"          = 0
                "two digit year cutoff"          = 2049
                "user connections"               = 0
                "user options"                   = 0
            }
        }
        #endregion SQL2000

        #region SQL2005
        9 {
            [pscustomobject]@{
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "awe enabled"                        = 0
                "blocked process threshold"          = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 8
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 20
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "SQL Mail XPs"                       = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "Web Assistant Procedures"           = 0
                "xp_cmdshell"                        = 0
            }
        }

        #endregion SQL2005

        #region SQL2008&2008R2
        10 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "awe enabled"                        = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 20
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "SQL Mail XPs"                       = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2008&2008R2

        #region SQL2012
        11 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2012

        #region SQL2014
        12 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2014

        #region SQL2016
        13 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2016

        #region SQL2017
        14 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity mask"                      = 0
                "affinity64 I/O mask"                = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "clr strict security"                = 1
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0

            }
        }
        #endregion SQL2017

        #region SQL2019
        15 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "ADR cleaner retry timeout (min)"    = 0
                "ADR Preallocation Factor"           = 0
                "affinity I/O mask"                  = 0
                "affinity mask"                      = 0
                "affinity64 I/O mask"                = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow filesystem enumeration"       = 1
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "clr strict security"                = 0
                "column encryption enclave type"     = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = 0
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 0
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase enabled"                   = 0
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "tempdb metadata memory-optimized"   = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2019

        #region SQL2022
        16 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "ADR cleaner retry timeout (min)"    = 15
                "ADR Cleaner Thread Count"           = 1
                "ADR Preallocation Factor"           = 4
                "affinity I/O mask"                  = 0
                "affinity mask"                      = 0
                "affinity64 I/O mask"                = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow filesystem enumeration"       = 1
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression algorithm"       = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "clr strict security"                = 1
                "column encryption enclave type"     = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Data processed daily limit in TB"   = 2147483647
                "Data processed monthly limit in TB" = 2147483647
                "Data processed weekly limit in TB"  = 2147483647
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "hardware offload config"            = 0
                "hardware offload enabled"           = 0
                "hardware offload mode"              = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 4
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "openrowset auto_create_statistics"  = 1
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase enabled"                   = 0
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 1
                "SMO and DMO XPs"                    = 1
                "suppress recovery model errors"     = 0
                "tempdb metadata memory-optimized"   = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "user options"                       = 0
                "version high part of SQL Server"    = 1048576
                "version low part of SQL Server"     = 65536006
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2022
    }
}