function Set-DbaDbFileGrowth {
    <#
    .SYNOPSIS
        Sets databases to a non-default growth and growth type. 64MB by default.

        To get the file growth, use Get-DbaDbFile.

    .DESCRIPTION
        Sets databases to a non-default growth and growth type. 64MB by default.

        To get the file growth, use Get-DbaDbFile.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The name of the target databases

    .PARAMETER GrowthType
        The growth type, MB by default - valid values are MB, KB, GB or TB. MB by default

    .PARAMETER Growth
        The growth value. 64 by default.

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbFileGrowth

    .EXAMPLE
        PS C:\> Set-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012

        Sets all non-default sized database files on sql2017, sql2016, sql2012 to 64MB.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database test | Set-DbaDbFileGrowth -GrowthType GB -Growth 1

        Sets the test database on sql2016 to a growth of 1GB

    .EXAMPLE
        PS C:\> Set-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012 -Database test -WhatIf

        Shows what would happen if the command were executed
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PsCredential]$SqlCredential,
        [string[]]$Database,
        [ValidateSet("KB", "MB", "GB", "TB")]
        [string]$GrowthType = "MB",
        [int]$Growth = 64,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not Database, InputObject) {
            Stop-Function -Message "You must specify InputObject or Database"
            return
        }

        if ((Test-Bound Database) -and -not (Test-Bound SqlInstance)) {
            Stop-Function -Message "You must specify SqlInstance when specifying Database"
            return
        }

        if ($SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database | Where-Object IsAccessible
        }

        foreach ($db in $InputObject) {
            $allfiles = @($db.FileGroups.Files, $db.LogFiles)
            foreach ($file in $allfiles) {
                if ($PSCmdlet.ShouldProcess($db.Parent.Name, "Setting filegrowth for $($file.Name) in $($db.name) to $($Growth)$($GrowthType)")) {
                    # SMO gave me some weird errors so I'm just gonna go with T-SQL
                    try {
                        $sql = "ALTER DATABASE $db MODIFY FILE ( NAME = N'$($file.Name)', FILEGROWTH = $($Growth)$($GrowthType) )"
                        Write-Message -Level Verbose -Message $sql
                        $db.Query($sql)
                        $db.Refresh()
                        $db.Parent.Refresh()
                        # this is a bit repetitive but had to be done to accomodate WhatIf
                        $db | Get-DbaDbFileGrowth | Where File -eq $file.Name
                    } catch {
                        Stop-Function -Message "Could not modify $db on $($db.Parent.Name)" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}