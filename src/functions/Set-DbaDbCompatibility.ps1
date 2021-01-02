function Set-DbaDbCompatibility {
    <#
    .SYNOPSIS
        Sets the compatibility level for SQL Server databases.

    .DESCRIPTION
        Sets the current database compatibility level for all databases on a server or list of databases passed in to the function.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database or databases to process. If unspecified, all databases will be processed.

    .PARAMETER TargetCompatibility
        The target compatibility level version. This is an int and follows Microsoft's versioning:

        9 = SQL Server 2005
        10 = SQL Server 2008
        11 = SQL Server 2012
        12 = SQL Server 2014
        13 = SQL Server 2016
        14 = SQL Server 2017
        15 = SQL Server 2019

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
        Author: Garry Bargsley, http://blog.garrybargsley.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbCompatibility

    .EXAMPLE
        PS C:\> Set-DbaDbCompatibility -SqlInstance localhost\sql2017

        Changes database compatibility level for all user databases on server localhost\sql2017 that have a Compatibility level that do not match

    .EXAMPLE
        PS C:\> Set-DbaDbCompatibility -SqlInstance localhost\sql2017 -TargetCompatibility 12

        Changes database compatibility level for all user databases on server localhost\sql2017 to Version120

    .EXAMPLE
        PS C:\> Set-DbaDbCompatibility -SqlInstance localhost\sql2017 -Database Test -TargetCompatibility 12

        Changes database compatibility level for database Test on server localhost\sql2017 to Version 120
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [ValidateSet(9, 10, 11, 12, 13, 14, 15)]
        [int]$TargetCompatibility,
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

            $ogcompat = $db.CompatibilityLevel
            $dbversion = switch ($ogcompat) {
                "Version100" { 10 } # SQL Server 2008
                "Version110" { 11 } # SQL Server 2012
                "Version120" { 12 } # SQL Server 2014
                "Version130" { 13 } # SQL Server 2016
                "Version140" { 14 } # SQL Server 2017
                "Version150" { 15 } # SQL Server 2019
                default { 9 } # SQL Server 2005
            }

            if (-not $TargetCompatibility) {
                if ($dbversion -lt $ServerVersion) {
                    If ($Pscmdlet.ShouldProcess($server.Name, "Updating $db version from $dbversion to $ServerVersion")) {
                        $comp = $ServerVersion * 10
                        $sql = "ALTER DATABASE $db SET COMPATIBILITY_LEVEL = $comp"
                        try {
                            $db.ExecuteNonQuery($sql)
                            $db.Refresh()
                            Get-DbaDbCompatibility -SqlInstance $server -Database $db.Name
                        } catch {
                            Stop-Function -Message "Failed to change Compatibility Level" -ErrorRecord $_ -Target $instance -Continue
                        }
                    }
                }
            } else {
                if ($Pscmdlet.ShouldProcess($server.Name, "Updating $db version from $dbversion to $TargetCompatibility")) {
                    $comp = $TargetCompatibility * 10
                    $sql = "ALTER DATABASE $db SET COMPATIBILITY_LEVEL = $comp"
                    try {
                        $db.ExecuteNonQuery($sql)
                        $db.Refresh()
                        Get-DbaDbCompatibility -SqlInstance $server -Database $db.Name
                    } catch {
                        Stop-Function -Message "Failed to change Compatibility Level" -ErrorRecord $_ -Target $instance -Continue
                    }
                }
            }
        }
    }
}