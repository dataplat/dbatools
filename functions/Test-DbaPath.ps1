function Test-DbaPath {
    <#
    .SYNOPSIS
        Tests if file or directory exists from the perspective of the SQL Server service account.

    .DESCRIPTION
        Uses master.dbo.xp_fileexist to determine if a file or directory exists.

    .PARAMETER SqlInstance
        The SQL Server you want to run the test on.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        The Path to test. This can be a file or directory

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Path, ServiceAccount
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaPath

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $counter = [pscustomobject] @{ Value = 0 }
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
                        [pscustomobject]@{
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