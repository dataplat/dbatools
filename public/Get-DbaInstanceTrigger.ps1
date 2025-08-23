function Get-DbaInstanceTrigger {
    <#
    .SYNOPSIS
        Retrieves server-level DDL triggers from SQL Server instances for auditing and documentation

    .DESCRIPTION
        Returns server-level DDL triggers that monitor and respond to instance-wide events like CREATE, ALTER, and DROP statements. Server triggers are commonly used for security auditing, change tracking, and preventing unauthorized schema modifications across all databases on an instance. This function helps identify what automated responses are configured at the server level, which is essential for troubleshooting unexpected DDL blocking and documenting compliance controls.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Trigger, General
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstanceTrigger

    .EXAMPLE
        PS C:\> Get-DbaInstanceTrigger -SqlInstance sql2017

        Returns all server triggers on sql2017

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($trigger in $server.Triggers) {
                try {
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Select-DefaultView -InputObject $trigger -Property ComputerName, InstanceName, SqlInstance, ID, Name, AnsiNullsStatus, AssemblyName, BodyStartIndex, ClassName, CreateDate, DateLastModified, DdlTriggerEvents, ExecutionContext, ExecutionContextLogin, ImplementationType, IsDesignMode, IsEnabled, IsEncrypted, IsSystemObject, MethodName, QuotedIdentifierStatus, State, TextHeader, TextMode
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}