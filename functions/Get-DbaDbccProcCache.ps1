function Get-DbaDbccProcCache {
    <#
    .SYNOPSIS
        Execution of Database Console Command DBCC PROCCACHE

    .DESCRIPTION
        Returns the results of DBCC PROCCACHE

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-proccache-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbccProcCache

    .EXAMPLE
        PS C:\> Get-DbaDbccProcCache -SqlInstance Server1

        Get results of DBCC PROCCACHE for Instance Server1

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbccProcCache

        Get results of DBCC PROCCACHE for Instances Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaDbccProcCache -SqlInstance Server1 -SqlCredential $cred

        Connects using sqladmin credential and gets results of DBCC PROCCACHE for Instance Server1

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {

        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC PROCCACHE WITH NO_INFOMSGS")
    }
    process {
        $query = $StringBuilder.ToString()
        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                Write-Message -Message "Query to run: $query" -Level Verbose
                $results = $server.Query($query)
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
            }
            foreach ($row in $results) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Count        = $row[0]
                    Used         = $row[1]
                    Active       = $row[2]
                    CacheSize    = $row[3]
                    CacheUsed    = $row[4]
                    CacheActive  = $row[5]
                }
            }
        }
    }
}