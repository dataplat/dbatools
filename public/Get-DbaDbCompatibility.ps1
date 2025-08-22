function Get-DbaDbCompatibility {
    <#
    .SYNOPSIS
        Retrieves database compatibility levels from SQL Server instances for upgrade planning and compliance auditing.

    .DESCRIPTION
        Returns the current compatibility level setting for each database, which determines what SQL Server language features and behaviors are available to that database. This is essential when planning SQL Server upgrades, as databases often retain older compatibility levels even after the instance is upgraded. The function helps identify which databases may need compatibility level updates to take advantage of newer SQL Server features or to maintain vendor application support requirements.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database or databases to process. If unspecified, all databases will be processed.

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase)

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Update database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Compatibility, Database
        Author: Garry Bargsley, blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbCompatibility

    .EXAMPLE
        PS C:\> Get-DbaDbCompatibility -SqlInstance localhost\sql2017

        Displays database compatibility level for all user databases on server localhost\sql2017

    .EXAMPLE
        PS C:\> Get-DbaDbCompatibility -SqlInstance localhost\sql2017 -Database Test

        Displays database compatibility level for database Test on server localhost\sql2017

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -not 'SqlInstance', 'InputObject') {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or pipe a database collection"
            continue
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $ServerVersion = $server.VersionMajor
            Write-Message -Level Verbose -Message "SQL Server is using Version: $ServerVersion"

            [PSCustomObject]@{
                ComputerName  = $server.ComputerName
                InstanceName  = $server.ServiceName
                SqlInstance   = $server.DomainInstanceName
                Database      = $db.Name
                DatabaseId    = $db.Id
                Compatibility = $db.CompatibilityLevel
            }
        }
    }
}