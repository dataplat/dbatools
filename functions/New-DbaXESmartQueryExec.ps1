function New-DbaXESmartQueryExec {
    <#
    .SYNOPSIS
        This response type executes a T-SQL command against a target database whenever an event is recorded.

    .DESCRIPTION
        This response type executes a T-SQL command against a target database whenever an event is recorded.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the name of the database that contains the target table.

    .PARAMETER Query
        The T-SQL command to execute. This string can contain placeholders for properties taken from the events.

        Placeholders are in the form {PropertyName}, where PropertyName is one of the fields or actions available in the Event object.

    .PARAMETER Event
        Each Response can be limited to processing specific events, while ignoring all the other ones. When this attribute is omitted, all events are processed.

    .PARAMETER Filter
        You can specify a filter expression by using this attribute. The filter expression is in the same form that you would use in a SQL query. For example, a valid example looks like this: duration > 10000 AND cpu_time > 10000

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent, SmartTarget
        Author: Chrissy LeMaire (@cl) | SmartTarget by Gianluca Sartori (@spaghettidba)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaXESmartQueryExec

    .EXAMPLE
        PS C:\> $response = New-DbaXESmartQueryExec -SqlInstance sql2017 -Database dbadb -Query "update table set whatever = 1"
        PS C:\> Start-DbaXESmartTarget -SqlInstance sql2017 -Session deadlock_tracker -Responder $response

        Executes a T-SQL command against dbadb on sql2017 whenever a deadlock event is recorded.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [string]$Query,
        [switch]$EnableException,
        [string[]]$Event,
        [string]$Filter
    )
    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\bin\libraries\third-party\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Pscmdlet.ShouldProcess($instance, "Creating new XESmartQueryExec")) {
                $execute = New-Object -TypeName XESmartTarget.Core.Responses.ExecuteTSQLResponse
                $execute.ServerName = $server.Name
                $execute.DatabaseName = $Database
                $execute.TSQL = $Query

                if ($SqlCredential) {
                    $execute.UserName = $SqlCredential.UserName
                    $execute.Password = $SqlCredential.GetNetworkCredential().Password
                }

                if (Test-Bound -ParameterName "Event") {
                    $execute.Events = $Event
                }
                if (Test-Bound -ParameterName "Filter") {
                    $execute.Filter = $Filter
                }

                $execute
            }
        }
    }
}