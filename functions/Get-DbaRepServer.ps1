#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaRepServer {
    <#
    .SYNOPSIS
        Gets a replication server object

    .DESCRIPTION
        Gets a replication server object

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        PS C:\> Get-DbaRepServer -SqlInstance sql2016

        Gets the replication server object for sql2016 using Windows authentication

    .EXAMPLE
        PS C:\> Get-DbaRepServer -SqlInstance sql2016 -SqlCredential repadmin

        Gets the replication server object for sql2016 using SQL authentication

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
                New-Object Microsoft.SqlServer.Replication.ReplicationServer $server.ConnectionContext.SqlConnectionObject
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}