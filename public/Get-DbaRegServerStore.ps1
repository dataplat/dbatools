function Get-DbaRegServerStore {
    <#
    .SYNOPSIS
        Creates a RegisteredServersStore object for managing Central Management Server configurations

    .DESCRIPTION
        Creates a RegisteredServersStore object that serves as the foundation for working with SQL Server Central Management Server (CMS). This object provides access to server groups and registered servers stored in the CMS repository, allowing you to programmatically manage multiple SQL Server instances from a centralized location. When no SqlInstance is specified, it returns the local file store which contains your locally registered servers from SQL Server Management Studio. The returned object can be used with other dbatools CMS commands like Get-DbaRegServer and Get-DbaRegServerGroup to retrieve and manage your registered server configurations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer,CMS
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRegServerStore

    .EXAMPLE
        PS C:\> Get-DbaRegServerStore -SqlInstance sqlserver2014a

        Returns a SQL Server Registered Server Store Object from sqlserver2014a

    .EXAMPLE
        PS C:\> Get-DbaRegServerStore -SqlInstance sqlserver2014a -SqlCredential sqladmin

        Returns a SQL Server Registered Server Store Object from sqlserver2014a  by logging in with the sqladmin login

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $store = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext)
            } catch {
                Stop-Function -Message "Cannot access Central Management Server on $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name ParentServer -value $server
            Select-DefaultView -InputObject $store -ExcludeProperty ServerConnection, DomainInstanceName, DomainName, Urn, Properties, Metadata, Parent, ConnectionContext, PropertyMetadataChanged, PropertyChanged, ParentServer
        }

        # Magic courtesy of Mathias Jessen and David Shifflet
        if (-not $PSBoundParameters.SqlInstance) {
            $file = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]::LocalFileStore.DomainInstanceName
            if ($file) {
                if (-not (Test-Path -Path $file)) {
                    $regfile = Join-DbaPath -Path $script:PSModuleRoot -ChildPath bin, RegSrvr.xml
                    Copy-Item -Path $regfile -Destination $file -Force
                }
                $class = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]
                $initMethod = $class.GetMethod('InitChildObjects', [Reflection.BindingFlags]'Static,NonPublic')
                $initMethod.Invoke($null, @($file))
            }
        }
    }
}