function Set-DbaDbCompatibility {
    <#
    .SYNOPSIS
        Changes database compatibility levels to match SQL Server instance version or specified target level.

    .DESCRIPTION
        Updates database compatibility levels across one or more SQL Server instances. When no specific compatibility level is provided, automatically sets each database to match the SQL Server instance version it resides on. This is particularly useful after SQL Server upgrades when databases retain their original compatibility levels and need updating to take advantage of newer engine features and optimizations. The function processes only databases where the current compatibility level differs from the target level, making it safe to run repeatedly.

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
        Availability values: https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.compatibilitylevel

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
        https://dbatools.io/Set-DbaDbCompatibility

    .EXAMPLE
        PS C:\> Set-DbaDbCompatibility -SqlInstance sql2017a

        Changes database compatibility level for all user databases on server sql2017a that have a Compatibility level that do not match

    .EXAMPLE
        PS C:\> Set-DbaDbCompatibility -SqlInstance sql2019a -Compatibility Version150

        Changes database compatibility level for all user databases on server sql2019a to Version150

    .EXAMPLE
        PS C:\> Set-DbaDbCompatibility -SqlInstance sql2022b -Database Test -Compatibility Version160

        Changes database compatibility level for database Test on server sql2022b to Version160
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]$Compatibility,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -not 'SqlInstance', 'InputObject') {
            Write-Message -Level Warning -Message 'You must specify either a SQL instance or pipe a database collection'
            continue
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $dbLevel = $db.CompatibilityLevel
            Write-Message -Level Verbose -Message "Database $db current Compatibility Level: $dbLevel"

            if (Test-Bound -ParameterName 'Compatibility') {
                $targetCompatibility = $Compatibility
            } else {
                $serverVersion = $server.VersionMajor
                $targetCompatibility = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($serverVersion)0"
                Write-Message -Level Verbose -Message "No Compatibility value provided, setting databases to match the SQL Server Instance version: $targetCompatibility"
            }

            if ($dbLevel -ne $targetCompatibility) {
                if ($PSCmdlet.ShouldProcess($server.Name, "Setting $db Compatibility Level to $targetCompatibility")) {
                    try {
                        $db.CompatibilityLevel = $targetCompatibility
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
                        Stop-Function -Message 'Failed to change Compatibility Level' -ErrorRecord $_ -Target $db -Continue
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Database $db current Compatibility Level matches target level [$targetCompatibility]"
            }
        }
    }
}