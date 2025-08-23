function Get-DbaInstanceAuditSpecification {
    <#
    .SYNOPSIS
        Retrieves server-level audit specifications from SQL Server instances for compliance and security monitoring

    .DESCRIPTION
        Returns all server-level audit specifications configured on SQL Server instances, including their enabled status, associated audit names, and configuration details. This helps DBAs inventory audit configurations for compliance reporting, security assessments, and ensuring proper event monitoring is in place. Server audit specifications define which events are captured by SQL Server Audit at the instance level, such as login attempts, permission changes, and database access patterns.

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
        Tags: Audit, Security, SqlAudit
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstanceAuditSpecification

    .EXAMPLE
        PS C:\> Get-DbaInstanceAuditSpecification -SqlInstance localhost

        Returns all Security Audit Specifications on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaInstanceAuditSpecification -SqlInstance localhost, sql2016

        Returns all Security Audit Specifications for the local and sql2016 SQL Server instances

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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($auditSpecification in $server.ServerAuditSpecifications) {
                Add-Member -Force -InputObject $auditSpecification -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $auditSpecification -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $auditSpecification -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                Select-DefaultView -InputObject $auditSpecification -Property ComputerName, InstanceName, SqlInstance, ID, Name, AuditName, Enabled, CreateDate, DateLastModified, Guid
            }
        }
    }
}