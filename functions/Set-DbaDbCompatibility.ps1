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

    .PARAMETER Compatibility
        The target compatibility level version. Same format as returned by Get-DbaDbCompatibility
        Version90 = SQL Server 2005
        Version100 = SQL Server 2008
        Version110 = SQL Server 2012
        Version120 = SQL Server 2014
        Version130 = SQL Server 2016
        Version140 = SQL Server 2017
        Version150 = SQL Server 2019

    .PARAMETER TargetCompatibility
        Deprecated parameter. Please use Compatibility instead.

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
        [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]$Compatibility,
        [ValidateSet(9, 10, 11, 12, 13, 14, 15)]
        [int]$TargetCompatibility,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if (Test-Bound SqlInstance, InputObject -Not -Min 1 -Max 1) {
            Stop-Function -Message "You must specify either a SQL instance or pipe a database collection"
            return
        }

        if (Test-Bound -ParameterName 'TargetCompatibility') {
            Write-Message -Level Warning -Message "Parameter TargetCompatibility is deprecated, please use Compatibility instead."
            if (Test-Bound -Not -ParameterName 'Compatibility') {
                $Compatibility = switch ($TargetCompatibility) {
                    9 { "Version100" }  # SQL Server 2005
                    10 { "Version100" } # SQL Server 2008
                    11 { "Version110" } # SQL Server 2012
                    12 { "Version120" } # SQL Server 2014
                    13 { "Version130" } # SQL Server 2016
                    14 { "Version140" } # SQL Server 2017
                    15 { "Version150" } # SQL Server 2019
                }
            }
            Write-Message -Level Verbose -Message "TargetCompatibility $TargetCompatibility was converted to Compatibility $Compatibility."
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $serverVersion = $server.VersionMajor
            Write-Message -Level Verbose -Message "SQL Server is using Version: $serverVersion"

            if ($Compatibility) {
                Write-Message -Level Verbose -Message "Setting targetLevel from parameter Compatibility"
                $targetLevel = $Compatibility
            } else {
                Write-Message -Level Verbose -Message "Setting targetLevel from SQL Server version"
                $targetLevel = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($server.VersionMajor)0"
            }
            Write-Message -Level Verbose -Message "targetLevel is $targetLevel"

            $dbLevel = $db.CompatibilityLevel
            Write-Message -Level Verbose -Message "dbLevel is $dbLevel"

            if ($dbLevel -ne $targetLevel) {
                If ($Pscmdlet.ShouldProcess($server.Name, "Changing $db Compatibility Level from $dbLevel to $targetLevel")) {
                    try {
                        $db.CompatibilityLevel = $targetLevel
                        $db.Alter()
                        [PSCustomObject]@{
                            ComputerName          = $server.ComputerName
                            InstanceName          = $server.ServiceName
                            SqlInstance           = $server.DomainInstanceName
                            Database              = $db.Name
                            Compatibility         = $db.CompatibilityLevel
                            PreviousCompatibility = $dbLevel
                        }
                    } catch {
                        Stop-Function -Message "Failed to change Compatibility Level" -ErrorRecord $_ -Target $instance -Continue
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Compatibility Level of $db on $($server.Name) is already at targetLevel $targetLevel"
            }
        }
    }
}