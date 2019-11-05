function Get-DbaDbState {
    <#
    .SYNOPSIS
        Gets various options for databases, hereby called "states"

    .DESCRIPTION
        Gets some common "states" on databases:
        - "RW" options : READ_ONLY or READ_WRITE
        - "Status" options : ONLINE, OFFLINE, EMERGENCY, RESTORING
        - "Access" options : SINGLE_USER, RESTRICTED_USER, MULTI_USER

        Returns an object with SqlInstance, Database, RW, Status, Access

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbState

    .EXAMPLE
        PS C:\> Get-DbaDbState -SqlInstance sqlserver2014a

        Gets options for all databases of the sqlserver2014a instance

    .EXAMPLE
        PS C:\> Get-DbaDbState -SqlInstance sqlserver2014a -Database HR, Accounting

        Gets options for both HR and Accounting database of the sqlserver2014a instance

    .EXAMPLE
        PS C:\> Get-DbaDbState -SqlInstance sqlserver2014a -Exclude HR

        Gets options for all databases of the sqlserver2014a instance except HR

    .EXAMPLE
        PS C:\> 'sqlserver2014a', 'sqlserver2014b' | Get-DbaDbState

        Gets options for all databases of sqlserver2014a and sqlserver2014b instances

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseLiteralInitializerForHashtable", "")]
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    begin {

        $DbStatesQuery = @'
SELECT
Name   = name,
Access = user_access_desc,
Status = state_desc,
RW     = CASE WHEN is_read_only = 0 THEN 'READ_WRITE' ELSE 'READ_ONLY' END
FROM sys.databases
'@

    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $dbStates = $server.Query($DbStatesQuery)
            $dbs = $dbStates | Where-Object { @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name }
            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }
            # "normal" hashtable doesn't account for case sensitivity
            $dbStatesHash = New-Object -TypeName System.Collections.Hashtable
            foreach ($db in $dbStates) {
                $dbStatesHash.Add($db.Name, [pscustomobject]@{
                        Access = $db.Access
                        Status = $db.Status
                        RW     = $db.RW
                    })
            }
            foreach ($db in $dbs) {
                $db_status = $dbStatesHash[$db.Name]
                [PSCustomObject]@{
                    SqlInstance  = $server.Name
                    InstanceName = $server.ServiceName
                    ComputerName = $server.ComputerName
                    DatabaseName = $db.Name
                    RW           = $db_status.RW
                    Status       = $db_status.Status
                    Access       = $db_status.Access
                    Database     = $server.Databases[$db.Name]
                } | Select-DefaultView -ExcludeProperty Database
            }
        }
    }
}