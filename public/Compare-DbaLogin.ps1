function Compare-DbaLogin {
    <#
    .SYNOPSIS
        Compares SQL Server logins between a source and one or more destination instances.

    .DESCRIPTION
        Compares SQL Server logins between a source instance and one or more destination instances to identify which logins exist only on the source, only on the destination, or on both. This is useful for identifying logins that would be lost when using Copy-DbaLogin with -Force, or for auditing login consistency between environments.

        Returns one object per login per destination instance, indicating whether the login exists on the source, destination, or both.

    .PARAMETER Source
        The source SQL Server instance.

    .PARAMETER SourceSqlCredential
        Login to the source instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        The destination SQL Server instance or instances.

    .PARAMETER DestinationSqlCredential
        Login to the destination instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        Specifies one or more logins to include in the comparison. All other logins are excluded.

    .PARAMETER ExcludeLogin
        Specifies one or more logins to exclude from the comparison.

    .PARAMETER ExcludeSystemLogin
        Excludes built-in system logins from the comparison results.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login, Security, Compare
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Compare-DbaLogin

    .OUTPUTS
        PSCustomObject

        Returns one object for each login found on either the source or destination instance.

        Properties:
        - SourceServer: The name of the source SQL Server instance
        - DestinationServer: The name of the destination SQL Server instance
        - LoginName: The name of the login account
        - LoginType: The login type (SqlLogin, WindowsUser, WindowsGroup, etc.)
        - Status: Indicates where the login exists - "SourceOnly", "DestinationOnly", or "Both"

    .EXAMPLE
        PS C:\> Compare-DbaLogin -Source sql1 -Destination sql2

        Compares all logins between sql1 and sql2, returning the status of each login.

    .EXAMPLE
        PS C:\> Compare-DbaLogin -Source sql1 -Destination sql2 | Where-Object Status -eq "DestinationOnly"

        Returns logins that exist on sql2 but not on sql1. These logins would be lost if Copy-DbaLogin -Force were run from sql1 to sql2.

    .EXAMPLE
        PS C:\> Compare-DbaLogin -Source sql1 -Destination sql2 | Where-Object Status -eq "SourceOnly"

        Returns logins that exist on sql1 but not on sql2. These are the logins that Copy-DbaLogin would create.

    .EXAMPLE
        PS C:\> Compare-DbaLogin -Source sql1 -Destination sql2 -ExcludeSystemLogin

        Compares user-created logins between sql1 and sql2, excluding built-in system logins.

    .EXAMPLE
        PS C:\> Compare-DbaLogin -Source sql1 -Destination sql2, sql3 -Login "appuser", "reportuser"

        Compares the specified logins between sql1 and both sql2 and sql3.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Login,
        [string[]]$ExcludeLogin,
        [switch]$ExcludeSystemLogin,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure connecting to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        $splatGetSource = @{
            SqlInstance        = $sourceServer
            ExcludeSystemLogin = $ExcludeSystemLogin
        }
        if ($Login) {
            $splatGetSource["Login"] = $Login
        }
        if ($ExcludeLogin) {
            $splatGetSource["ExcludeLogin"] = $ExcludeLogin
        }
        $sourceLogins = Get-DbaLogin @splatGetSource
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($destInstance in $Destination) {
            $destServer = $null
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure connecting to $destInstance" -Category ConnectionError -ErrorRecord $_ -Target $destInstance -Continue
            }
            if ($null -eq $destServer) { continue }

            $splatGetDest = @{
                SqlInstance        = $destServer
                ExcludeSystemLogin = $ExcludeSystemLogin
            }
            if ($Login) {
                $splatGetDest["Login"] = $Login
            }
            if ($ExcludeLogin) {
                $splatGetDest["ExcludeLogin"] = $ExcludeLogin
            }
            $destLogins = Get-DbaLogin @splatGetDest

            $allLoginNames = New-Object System.Collections.ArrayList
            foreach ($srcLogin in $sourceLogins) {
                if ($srcLogin.Name -notin $allLoginNames) {
                    $null = $allLoginNames.Add($srcLogin.Name)
                }
            }
            foreach ($dstLogin in $destLogins) {
                if ($dstLogin.Name -notin $allLoginNames) {
                    $null = $allLoginNames.Add($dstLogin.Name)
                }
            }

            foreach ($loginName in $allLoginNames) {
                $srcLogin = $sourceLogins | Where-Object Name -eq $loginName
                $dstLogin = $destLogins | Where-Object Name -eq $loginName

                if ($srcLogin -and $dstLogin) {
                    $status = "Both"
                } elseif ($srcLogin) {
                    $status = "SourceOnly"
                } else {
                    $status = "DestinationOnly"
                }

                [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    LoginName         = $loginName
                    LoginType         = if ($srcLogin) { $srcLogin.LoginType } else { $dstLogin.LoginType }
                    Status            = $status
                }
            }
        }
    }
}
