function Set-DbaDbFileGrowth {
    <#
    .SYNOPSIS
        Modifies auto-growth settings for database data and log files to use fixed-size increments instead of percentage-based growth.

    .DESCRIPTION
        Configures database file auto-growth settings using ALTER DATABASE statements to replace default percentage-based growth with fixed-size increments. This prevents unpredictable growth patterns that can cause performance issues and storage fragmentation as databases grow larger. Defaults to 64MB growth increments, which provides better control over file expansion and reduces the risk of exponential growth that can quickly consume available disk space. You can target specific file types (data files, log files, or both) and specify custom growth values in KB, MB, GB, or TB units.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to modify file growth settings for. Accepts an array of database names.
        Use this when you need to target specific databases rather than all databases on an instance.

    .PARAMETER GrowthType
        Specifies the unit of measurement for the growth increment. Valid values are KB, MB, GB, or TB.
        Choose the appropriate unit based on your database size and expected growth patterns - MB for smaller databases, GB for larger ones.

    .PARAMETER Growth
        Sets the numeric value for the fixed growth increment. Defaults to 64 when combined with the default MB unit.
        Use smaller values (16-64MB) for smaller databases or larger values (256MB-1GB) for high-growth production databases to balance performance and storage efficiency.

    .PARAMETER FileType
        Controls which file types to modify - Data files only, Log files only, or All files (both data and log).
        Use 'Data' when you need different growth settings for data vs log files, or 'All' to standardize growth across all database files.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline operations.
        Use this when you need to filter databases first or when working with database objects from other dbatools functions.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, Log, File, Growth
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbFileGrowth

    .OUTPUTS
        PSCustomObject

        Returns one object per database file that was modified. The output represents the updated file growth configuration after the changes have been applied.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Name of the database containing the file
        - MaxSize: Maximum size the file can grow to; displays as dbasize object (KB, MB, GB, TB)
        - GrowthType: How the file grows - either "Percent" or "kb"
        - Growth: The growth increment value (percentage if GrowthType is Percent, kilobytes if kb)
        - File: Logical name of the file within SQL Server
        - FileName: Operating system file path
        - State: Current state of the file (ONLINE, OFFLINE, etc.)

    .EXAMPLE
        PS C:\> Set-DbaDbFileGrowth -SqlInstance sql2016 -Database test  -GrowthType GB -Growth 1

        Sets the test database on sql2016 to a growth of 1GB

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database test | Set-DbaDbFileGrowth -GrowthType GB -Growth 1

        Sets the test database on sql2016 to a growth of 1GB

    .EXAMPLE
        PS C:\> Get-DbaDatabase | Set-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012

        Sets all database files on sql2017, sql2016, sql2012 to 64MB.

    .EXAMPLE
        PS C:\> Set-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012 -Database test -WhatIf

        Shows what would happen if the command were executed

    .EXAMPLE
        PS C:\> Set-DbaDbFileGrowth -SqlInstance sql2017 -Database test -GrowthType GB -Growth 1 -FileType Data

        Sets growth to 1GB for only data files for database test

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [ValidateSet("KB", "MB", "GB", "TB")]
        [string]$GrowthType = "MB",
        [int]$Growth = 64,
        [ValidateSet('All', 'Data', 'Log')]
        [string]$FileType = "All",
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

            $allfiles = @()
            if ($FileType -in ('Log', 'All')) {
                $allfiles += $db.LogFiles
            }
            if ($FileType -in ('Data', 'All')) {
                $allfiles += $db.FileGroups.Files
            }

            foreach ($file in $allfiles) {
                if ($PSCmdlet.ShouldProcess($db.Parent.Name, "Setting filegrowth for $($file.Name) in $($db.name) to $($Growth)$($GrowthType)")) {
                    # SMO gave me some weird errors so I'm just gonna go with T-SQL
                    try {
                        $sql = "ALTER DATABASE $db MODIFY FILE ( NAME = N'$($file.Name)', FILEGROWTH = $($Growth)$($GrowthType) )"
                        Write-Message -Level Verbose -Message $sql
                        $db.Query($sql)
                        $db.Refresh()
                        $db.Parent.Refresh()
                        # this executes Get-DbaDbFileGrowth a bunch of times because it's in a loop, but it's needed to keep the output results in the WhatIf
                        $db | Get-DbaDbFileGrowth | Where-Object File -eq $file.Name
                    } catch {
                        Stop-Function -Message "Could not modify $db on $($db.Parent.Name)" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}