function Get-DbaRegisteredServersStore {
    <#
        .SYNOPSIS
            Returns a SQL Server Registered Server Store Object

        .DESCRIPTION
            Returns a SQL Server Registered Server Store object - useful for working with Central Management Store

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            SqlCredential object to connect as. If not specified, current Windows login will be used.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: RegisteredServer,CMS
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaRegisteredServersStore

        .EXAMPLE
            Get-DbaRegisteredServersStore -SqlInstance sqlserver2014a

            Returns a SQL Server Registered Server Store Object from sqlserver2014a

        .EXAMPLE
            Get-DbaRegisteredServersStore -SqlInstance sqlserver2014a -SqlCredential (Get-Credential sqladmin)

            Returns a SQL Server Registered Server Store Object from sqlserver2014a  by logging in with the sqladmin login
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $store = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
            }
            catch {
                Stop-Function -Message "Cannot access Central Management Server on $instance." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name ComputerName -value $server.NetName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

            Select-DefaultView -InputObject $store -ExcludeProperty ServerConnection, DomainInstanceName, DomainName, Urn, Properties, Metadata, Parent, ConnectionContext, PropertyMetadataChanged, PropertyChanged
        }
    }
}