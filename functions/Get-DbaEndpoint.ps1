#ValidationTags#Messaging,FlowControl,CodeStyle#
function Get-DbaEndpoint {
    <#
        .SYNOPSIS
            Gets SQL Endpoint(s) information for each instance(s) of SQL Server.

        .DESCRIPTION
            The Get-DbaEndpoint command gets SQL Endpoint(s) information for each instance(s) of SQL Server.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Endpoint
            Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaEndpoint

        .EXAMPLE
            Get-DbaEndpoint -SqlInstance localhost

            Returns all Endpoint(s) on the local default SQL Server instance

        .EXAMPLE
            Get-DbaEndpoint -SqlInstance localhost, sql2016

            Returns all Endpoint(s) for the local and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($endpoint in $server.Endpoints) {
                Add-Member -Force -InputObject $endpoint -MemberType NoteProperty -Name ComputerName -value $endpoint.Parent.NetName
                Add-Member -Force -InputObject $endpoint -MemberType NoteProperty -Name InstanceName -value $endpoint.Parent.ServiceName
                Add-Member -Force -InputObject $endpoint -MemberType NoteProperty -Name SqlInstance -value $endpoint.Parent.DomainInstanceName

                Select-DefaultView -InputObject $endpoint -Property ComputerName, InstanceName, SqlInstance, ID, Name, EndpointType, Owner, IsAdminEndpoint, IsSystemObject
            }
        }
    }
}
