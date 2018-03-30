function Get-DbaXEStore {
    <#
        .SYNOPSIS
            Get a Extended Events store

        .DESCRIPTION
            Get a Extended Events store

       .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaXEStore

        .EXAMPLE
            Get-DbaXEStore -SqlInstance ServerA\sql987

            Returns an XEvent Store.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $SqlConn = $server.ConnectionContext.SqlConnectionObject
            $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
            $store = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection

            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name ComputerName -Value $server.NetName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
            Select-DefaultView -InputObject $store -Property ComputerName, InstanceName, SqlInstance, ServerName, Sessions, Packages, RunningSessionCount
        }
    }
}