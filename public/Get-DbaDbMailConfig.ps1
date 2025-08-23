function Get-DbaDbMailConfig {
    <#
    .SYNOPSIS
        Retrieves Database Mail configuration settings from SQL Server instances

    .DESCRIPTION
        Retrieves all Database Mail configuration values from SQL Server, including settings like MaxFileSize, ProhibitedExtensions, DatabaseMailExeMinLifeTime, and LoggingLevel.
        This function helps DBAs audit current Database Mail configurations, troubleshoot email delivery issues, and verify compliance with organizational email policies.
        You can retrieve all configuration settings or filter by specific configuration names to focus on particular settings.
        The output includes the configuration name, current value, and description for each setting across your SQL Server environment.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies which Database Mail configuration settings to retrieve by name, such as MaxFileSize, ProhibitedExtensions, or LoggingLevel.
        Use this when you need to check specific configuration values instead of retrieving all Database Mail settings.
        Accepts multiple configuration names and supports aliases Config and ConfigName.

    .PARAMETER InputObject
        Accepts Database Mail objects from Get-DbaDbMail for pipeline processing.
        Use this when chaining multiple Database Mail functions together or when you already have Database Mail objects loaded.
        Allows you to retrieve configurations from multiple SQL Server instances efficiently through the pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Mail, DbMail, Email
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMailConfig

    .EXAMPLE
        PS C:\> Get-DbaDbMailConfig -SqlInstance sql01\sharepoint

        Returns DBMail configs on sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMailConfig -SqlInstance sql01\sharepoint -Name ProhibitedExtensions

        Returns the ProhibitedExtensions configuration on sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMailConfig -SqlInstance sql01\sharepoint | Select-Object *

        Returns the DBMail configs on sql01\sharepoint then return a bunch more columns

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaDbMail | Get-DbaDbMailConfig

        Returns the DBMail configs for "sql2014","sql2016" and "sqlcluster\sharepoint"

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Config", "ConfigName")]
        [string[]]$Name,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Mail.SqlMail[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDbMail -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }

        if (-not $InputObject) {
            Stop-Function -Message "No servers to process"
            return
        }

        foreach ($mailserver in $InputObject) {
            try {
                $configs = $mailserver.ConfigurationValues

                if ($Name) {
                    $configs = $configs | Where-Object Name -in $Name
                }

                $configs | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $mailserver.ComputerName
                $configs | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $mailserver.InstanceName
                $configs | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $mailserver.SqlInstance
                $configs | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Name, Value, Description
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}