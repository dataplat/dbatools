function Get-DbaDump {
    <#
        .SYNOPSIS
            Locate a SQL Server that has generated any memory dump files.

        .DESCRIPTION
            The type of dump included in the search include minidump, all-thread dump, or a full dump.  The files have an extendion of .mdmp.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Engine, Corruption
            Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaDump

        .EXAMPLE
            Get-DbaDump -SqlInstance sql2016

            Shows the detailed information for memory dump(s) located on sql2016 instance


        .EXAMPLE
            Get-DbaDump -SqlInstance sql2016 -SqlCredential (Get-Credential sqladmin)

            Shows the detailed information for memory dump(s) located on sql2016 instance. Logs into the SQL Server using the SQL login 'sqladmin'

    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
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
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        FileName     = $result.filename
                        CreationTime = $result.creation_time
                        Size         = [dbasize]$result.size_in_bytes
                    }
                }
            }
            catch {
                Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_ -Continue
            }
        }
    }
}