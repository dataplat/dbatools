function Test-DbaPath {
    <#
    .SYNOPSIS
        Tests if files or directories are accessible to the SQL Server service account.

    .DESCRIPTION
        Verifies file and directory accessibility from SQL Server's perspective using the master.dbo.xp_fileexist extended stored procedure. This is essential before backup operations, restore tasks, or any SQL Server process that requires file system access. The function tests from the SQL Server service account's security context, which may differ from your user account's permissions. Returns detailed information about file existence and whether the path is a container (directory).

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
                    $query += "EXEC master.dbo.xp_fileexist '$p'"
                }
                $sql = $query -join ';'
                $batchresult = $server.ConnectionContext.ExecuteWithResults($sql)
                if ($Path.Count -eq 1 -and $SqlInstance.Count -eq 1 -and (-not($RawPath -is [array]))) {
                    if ($batchresult.Tables.rows[0] -eq $true -or $batchresult.Tables.rows[1] -eq $true) {
                        return $true
                    } else {
                        return $false
                    }
                } else {
                    $i = 0
                    foreach ($r in $batchresult.tables.rows) {
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