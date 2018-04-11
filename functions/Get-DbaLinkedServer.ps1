function Get-DbaLinkedServer {
    <#
        .SYNOPSIS
            Gets all linked servers and summary of information from the sql servers listed

        .DESCRIPTION
            Retrieves information about each linked server on the instance

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER LinkedServer
            The linked server(s) to process - this list is auto-populated from the server. If unspecified, all linked servers will be processed.

        .PARAMETER ExcludeLinkedServer
            The linked server(s) to exclude - this list is auto-populated from the server

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Stephen Bennett ( https://sqlnotesfromtheunderground.wordpress.com/ )

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaLinkedServer

        .EXAMPLE
            Get-DbaLinkedServer -SqlInstance DEV01

            Returns all Linked Servers for the SQL Server instance DEV01
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$LinkedServer,
        [object[]]$ExcludeLinkedServer,
        [Alias('Silent')]
        [switch]$EnableException
    )
    foreach ($Instance in $SqlInstance) {
        try {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }

        $lservers = $server.LinkedServers

        if ($LinkedServer) {
            $lservers = $lservers | Where-Object { $_.Name -in $LinkedServer }
        }
        if ($ExcludeLinkedServer) {
            $lservers = $lservers | Where-Object { $_.Name -notin $ExcludeLinkedServer }
        }

        foreach ($ls in $lservers) {
            Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name ComputerName -value $server.NetName
            Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name Impersonate -value $ls.LinkedServerLogins.Impersonate
            Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name RemoteUser -value $ls.LinkedServerLogins.RemoteUser

            Select-DefaultView -InputObject $ls -Property ComputerName, InstanceName, SqlInstance, Name, 'DataSource as RemoteServer', ProductName, Impersonate, RemoteUser, 'DistPublisher as Publisher', Distributor, DateLastModified
        }
    }
}