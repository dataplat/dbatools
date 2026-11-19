function Test-DbaPath {
    <#
    .SYNOPSIS
        Tests if files or directories are accessible to the SQL Server service account.

    .DESCRIPTION
        Verifies file and directory accessibility from SQL Server's perspective. On SQL Server 2017 and later this uses sys.dm_os_file_exists, which works for logins without sysadmin, and falls back to master.dbo.xp_fileexist for a path that sys.dm_os_file_exists cannot check, such as a share on a host that does not exist. On older versions this uses master.dbo.xp_fileexist, which answers only for members of sysadmin and reports every path as not found for other logins. This is essential before backup operations, restore tasks, or any SQL Server process that requires file system access. The function tests from the SQL Server service account's security context, which may differ from your user account's permissions. Returns detailed information about file existence and whether the path is a container (directory).

    .PARAMETER SqlInstance
        The SQL Server you want to run the test on.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the file or directory paths to test for accessibility from the SQL Server service account's perspective. Accepts single paths, arrays of paths, or pipeline input.
        Use this to verify SQL Server can access backup destinations, restore source files, or any location needed for database operations.
        Critical for pre-validating paths before backup, restore, or bulk operations that would otherwise fail with access denied errors.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Path, Directory
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaPath

    .OUTPUTS
        System.Boolean (when testing a single path on a single instance)

        Returns $true if the file or directory is accessible to the SQL Server service account, $false otherwise.

        PSCustomObject (when testing multiple paths, multiple instances, or array input)

        Returns one object per file or directory path tested, with the following properties:
        - SqlInstance: Full instance name (computer\instance format)
        - InstanceName: The SQL Server instance name
        - ComputerName: The computer name hosting the SQL Server instance
        - FilePath: The file or directory path that was tested
        - FileExists: Boolean indicating if the file or directory exists and is accessible
        - IsContainer: Boolean indicating if the path is a directory (container) rather than a file

        Note: FileExists is true if either the file exists OR the path is a container (directory). IsContainer specifically identifies if it's a directory.

    .EXAMPLE
        PS C:\> Test-DbaPath -SqlInstance sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP

        Tests whether the service account running the "sqlcluster" SQL Server instance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using Windows credentials.

    .EXAMPLE
        PS C:\> $credential = Get-Credential
        PS C:\> Test-DbaPath -SqlInstance sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP

        Tests whether the service account running the "sqlcluster" SQL Server instance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using SQL authentication.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [object]$Path,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $counter = [PSCustomObject] @{ Value = 0 }
            $groupSize = 100
            $RawPath = $Path
            $Path = [string[]]$Path
            $groups = $Path | Group-Object -Property { [math]::Floor($counter.Value++ / $groupSize) }
            foreach ($g in $groups) {
                $PathsBatch = $g.Group
                $query = @()
                foreach ($p in $PathsBatch) {
                    # N keeps characters outside the code page of the database, and the doubled quote keeps a path like
                    # O'Brien from breaking the whole batch, which then reported every path of it as not found (#10835)
                    $quotedPath = "N'" + $p.Replace("'", "''") + "'"
                    if ($server.VersionMajor -ge 14) {
                        # xp_fileexist answers "not found" for every path when the login is not sysadmin, while
                        # sys.dm_os_file_exists answers for every login and checks as the service account just the same.
                        # It exists since SQL Server 2017. Where xp_fileexist answers "not found", for example for a share
                        # on a host that does not exist, sys.dm_os_file_exists fails, so that path falls back to
                        # xp_fileexist instead of failing the whole batch (#10835)
                        $query += "BEGIN TRY SELECT file_exists, file_is_a_directory, parent_directory_exists FROM sys.dm_os_file_exists($quotedPath) END TRY BEGIN CATCH EXEC master.dbo.xp_fileexist $quotedPath END CATCH"
                    } else {
                        $query += "EXEC master.dbo.xp_fileexist $quotedPath"
                    }
                }
                $sql = $query -join ";"
                try {
                    $batchresult = $server.ConnectionContext.ExecuteWithResults($sql)
                } catch {
                    if ($EnableException) {
                        Stop-Function -Message "Testing the path(s) failed on $instance." -ErrorRecord $_ -Target $instance
                        return
                    }

                    # Warning, not Verbose: swallowing the real error here made batch-level
                    # failures (permissions, timeouts) indistinguishable from files that
                    # genuinely do not exist (#10512)
                    Write-Message -Level Warning -Message "Testing the path(s) failed on $instance, so existence could not be determined and the path(s) are reported as not found. The SQL Server service account may not have access to the specified path(s). Error: $_"
                    if ($Path.Count -eq 1 -and $SqlInstance.Count -eq 1 -and (-not($RawPath -is [array]))) {
                        return $false
                    } else {
                        foreach ($p in $PathsBatch) {
                            [PSCustomObject]@{
                                SqlInstance  = $server.Name
                                InstanceName = $server.ServiceName
                                ComputerName = $server.ComputerName
                                FilePath     = $p
                                FileExists   = $false
                                IsContainer  = $false
                            }
                        }
                    }
                    continue
                }
                # One row per path. A path that fell back to xp_fileexist leaves the empty result set of the failed
                # sys.dm_os_file_exists in front of the one of xp_fileexist, so the rows count, not the result sets.
                $rows = @($batchresult.Tables | ForEach-Object { $PSItem.Rows })
                if ($Path.Count -eq 1 -and $SqlInstance.Count -eq 1 -and (-not($RawPath -is [array]))) {
                    if ($rows[0][0] -eq $true -or $rows[0][1] -eq $true) {
                        return $true
                    } else {
                        return $false
                    }
                } else {
                    $i = 0
                    foreach ($r in $rows) {
                        $DoesPass = $r[0] -eq $true -or $r[1] -eq $true
                        [PSCustomObject]@{
                            SqlInstance  = $server.Name
                            InstanceName = $server.ServiceName
                            ComputerName = $server.ComputerName
                            FilePath     = $PathsBatch[$i]
                            FileExists   = $DoesPass
                            IsContainer  = $r[1] -eq $true
                        }
                        $i += 1
                    }
                }
            }
        }
    }
}