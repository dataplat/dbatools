#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Test-DbaSqlPath {
    <#
        .SYNOPSIS
            Tests if file or directory exists from the perspective of the SQL Server service account.

        .DESCRIPTION
            Uses master.dbo.xp_fileexist to determine if a file or directory exists.

        .PARAMETER SqlInstance
            The SQL Server you want to run the test on.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Path
            The Path to test. This can be a file or directory

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.


        .NOTES
            Tags: Path, ServiceAccount
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires: Admin access to server (not SQL Services),
            Remoting must be enabled and accessible if $SqlInstance is not local

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Test-DbaSqlPath

        .EXAMPLE
            Test-DbaSqlPath -SqlInstance sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP

            Tests whether the service account running the "sqlcluster" SQL Server instance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using Windows credentials.

        .EXAMPLE
            $credential = Get-Credential
            Test-DbaSqlPath -SqlInstance sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP

            Tests whether the service account running the "sqlcluster" SQL Server instance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using SQL authentication.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [object]$Path,
        [Alias('Silent')]
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance." -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
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
                    }
                    else {
                        return $false
                    }
                }
                else {
                    $i = 0
                    foreach ($r in $batchresult.tables.rows) {
                        $DoesPass = $r[0] -eq $true -or $r[1] -eq $true
                        [pscustomobject]@{
                            SqlInstance  = $server.Name
                            InstanceName = $server.ServiceName
                            ComputerName = $server.NetName
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
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Test-SqlPath
    }
}
