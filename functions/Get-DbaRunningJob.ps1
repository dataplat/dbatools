function Get-DbaRunningJob {
    <#
    .SYNOPSIS
        Returns all non-idle Agent jobs running on the server

    .DESCRIPTION
        This function returns agent jobs that active on the SQL Server instance when calling the command

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAgentJob

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRunningJob

    .EXAMPLE
        PS C:\> Get-DbaRunningJob -SqlInstance sql2017

        Returns any active jobs on sql2017

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2017, sql2019 | Get-DbaRunningJob

        Returns all active jobs on multiple instances piped into the function.

    .EXAMPLE
        PS C:\> $servers | Get-DbaRunningJob

        Returns all active jobs on multiple instances piped into the function.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            Get-DbaAgentJob -SqlInstance $SqlInstance -SqlCredential $SqlCredential | Where-Object CurrentRunStatus -ne 'Idle'
        }

        $InputObject | Where-Object CurrentRunStatus -ne 'Idle'
    }
}