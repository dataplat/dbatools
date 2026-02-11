function Get-DbaAgHadr {
    <#
    .SYNOPSIS
        Retrieves the High Availability Disaster Recovery (HADR) service status for SQL Server instances.

    .DESCRIPTION
        Checks whether Availability Groups are enabled at the service level on SQL Server instances. This is a prerequisite for creating and managing Availability Groups, as HADR must be enabled before you can configure any AG functionality. Returns the computer name, instance name, and the current HADR enabled status (true/false) for each specified instance, making it useful for environment audits and troubleshooting AG setup issues.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Server

        Returns one SMO Server object per SQL Server instance queried, filtered to show HADR status.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name (e.g., MSSQLSERVER or named instance)
        - SqlInstance: The full SQL Server instance identifier in the format ComputerName\InstanceName or instance name for default
        - IsHadrEnabled: Boolean value indicating whether HADR is enabled ($true) or disabled ($false) on the instance

        All properties from the SMO Server object are accessible via Select-Object * even though only the default properties are displayed without explicit column selection.

    .NOTES
        Tags: AG, HA
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgHadr

    .EXAMPLE
        PS C:\> Get-DbaAgHadr -SqlInstance sql2016

        Returns a status of the Hadr setting for sql2016 SQL Server instance.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
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

            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

            Select-DefaultView -InputObject $server -Property 'ComputerName', 'InstanceName', 'SqlInstance', 'IsHadrEnabled'
        }
    }
}