#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Export-DbaRepServerSetting {
    <#
        .SYNOPSIS
            Exports replication server settings to file.

        .DESCRIPTION
            Exports replication server settings to file. By default, these settings include:

            Articles
            PublisherSideSubscriptions
            CreateSnapshotAgent
            Go
            EnableReplicationDB
            IncludePublicationAccesses
            IncludeCreateLogreaderAgent
            IncludeCreateQueuereaderAgent
            IncludeSubscriberSideSubscriptions

        .PARAMETER SqlInstance
            The target SQL Server instance or instances

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Path
            Specifies the path to a file which will contain the output.

        .PARAMETER ScriptOption
            Not real sure how to use this yet

        .PARAMETER InputObject
            Allows piping from Get-DbaRepServer

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Replication
            Website: https://dbatools.io
            Author: Chrissy LeMaire (@cl), netnerds.net
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            Export-DbaSpConfigure -SqlInstance sql2017 -Path C:\temp\replication.sql

            Exports the SPConfigure settings on sql2017 to the file C:\temp\replication.sql

        .EXAMPLE
            Get-DbaRepServer -SqlInstance sql2017 | Export-DbaRepServerSettings -Path C:\temp\replication.sql

            Exports the replication settings on sql2017 to the file C:\temp\replication.sql
    #>
    [CmdletBinding()]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Path,
        [object[]]$ScriptOption,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Replication.ReplicationServer[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRepServer -SqlInstance $instance -SqlCredential $sqlcredential
        }

        foreach ($repserver in $InputObject) {
            $server = $repserver.SqlServerName
            if (-not (Test-Bound -ParameterName Path)) {
                $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                $mydocs = [Environment]::GetFolderPath('MyDocuments')
                $path = "$mydocs\$($server.replace('\', '$'))-$timenow-replication.sql"
            }

            if (-not $ScriptOption) {
                $repserver.Script([Microsoft.SqlServer.Replication.ScriptOptions]::Creation `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeArticles `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::IncludePublisherSideSubscriptions `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeCreateSnapshotAgent `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeGo `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::EnableReplicationDB `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::IncludePublicationAccesses `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeCreateLogreaderAgent `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeCreateQueuereaderAgent `
            -bor  [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeSubscriberSideSubscriptions)
            }
            else {
                $repserver.Script($scriptOption)
            }
        }
    }
}