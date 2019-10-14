function Get-DbaDump {
    <#
    .SYNOPSIS
        Locate a SQL Server that has generated any memory dump files.

    .DESCRIPTION
        The type of dump included in the search include minidump, all-thread dump, or a full dump.  The files have an extendion of .mdmp.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Engine, Corruption
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDump

    .EXAMPLE
        PS C:\> Get-DbaDump -SqlInstance sql2016

        Shows the detailed information for memory dump(s) located on sql2016 instance

    .EXAMPLE
        PS C:\> Get-DbaDump -SqlInstance sql2016 -SqlCredential sqladmin

        Shows the detailed information for memory dump(s) located on sql2016 instance. Logs into the SQL Server using the SQL login 'sqladmin'

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        $sql = "SELECT filename,  creation_time,  size_in_bytes FROM sys.dm_server_memory_dumps"
    }

    process {
        foreach ($instance in $SqlInstance) {
            $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential

            if ($server.versionMajor -lt 11 -and (-not ($server.versionMajor -eq 10 -and $server.versionMinor -eq 50))) {
                Stop-Function -Message "This function does not support versions lower than SQL Server 2008 R2 (v10.50). Skipping server '$instance'" -Continue
            }

            try {
                foreach ($result in $server.Query($sql)) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        FileName     = $result.filename
                        CreationTime = $result.creation_time
                        Size         = [dbasize]$result.size_in_bytes
                    }
                }
            } catch {
                Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_ -Continue
            }
        }
    }
}