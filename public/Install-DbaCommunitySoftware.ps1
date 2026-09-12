function Install-DbaCommunitySoftware {
    <#
    .SYNOPSIS
        Installs community-maintained SQL Server tooling through a single command

    .DESCRIPTION
        Installs one or more of the community stored procedure kits that dbatools ships installers for, without needing to remember six separate command names. This is the install-side counterpart to Save-DbaCommunitySoftware, which already unifies the download step behind one -Software parameter.

        Each tool is handed off to its dedicated installer, and the objects that installer emits are passed straight back to you:

        - MaintenanceSolution: Install-DbaMaintenanceSolution (Ola Hallengren), SQL Server 2017 and later only
        - FirstResponderKit: Install-DbaFirstResponderKit (Brent Ozar Unlimited)
        - DarlingData: Install-DbaDarlingData (Erik Darling)
        - SQLWATCH: Install-DbaSqlWatch (Marcin Gminski)
        - WhoIsActive: Install-DbaWhoIsActive (Adam Machanic)
        - DbaMultiTool: Install-DbaMultiTool (John McCall)

        Three behaviors deliberately differ from calling an installer yourself:

        - SQLWATCH is skipped with a warning on PowerShell Core, and the rest of the batch still runs. Install-DbaSqlWatch supports Windows PowerShell only, and left to itself it downloads its payload before reaching that check, so selecting All from PowerShell Core would fetch a file it can never use.

        - WhoIsActive is given master when you do not pass Database. Called directly with no database, Install-DbaWhoIsActive opens an interactive picker, which would stall an unattended run.
        - A failure against one tool does not end the batch. The remaining tools still run, and the failure surfaces as a warning naming the tool. With EnableException the first failure throws, as it would anywhere else in dbatools.

        Each installer is called once with the whole instance list rather than once per instance, because they all download their payload before touching the first instance. Passing ten instances therefore fetches each archive once, not ten times.

        A single script that fails partway through is reported rather than thrown. FirstResponderKit, DarlingData and DbaMultiTool catch a failed script themselves, warn, and hand back that row with a Status of Error, so EnableException does not make it terminating here any more than it does when you call those installers directly. Check Status on the returned objects to find them.

        Everything else, including each installer version floor and its own confirmation prompts, is exactly what you get from the installer directly. An instance below a tool version floor is skipped by that installer with a warning while the rest of the batch continues.

        Only the parameters common to most of the installers are surfaced here. When you need tool-specific options such as the Ola Hallengren job scheduling switches, the First Responder Kit script selection, or the SqlWatch pre-release feed, call that installer directly.

        AzSqlTips is deliberately absent. Save-DbaCommunitySoftware downloads it, but it is consumed by Invoke-DbaDbAzSqlTip as a query rather than installed as stored procedures.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Software
        Specifies which community tools to install. Accepts multiple values, or All to install every tool in one pass.

        The names match Save-DbaCommunitySoftware so the download and install steps read the same way.

    .PARAMETER Database
        Specifies the database to install the tools into. When you leave this off, each installer keeps its own default, which means master for most tools and SQLWATCH for SqlWatch.

        Set this when you want every selected tool in one specific database, such as a dedicated DBA utility database.

    .PARAMETER Branch
        Specifies the source branch to download from. Only First Responder Kit, DarlingData and DbaMultiTool support branch selection, and their accepted values differ, so a value valid for one may be rejected by another.

        A warning names any selected tool that has no branch to switch.

    .PARAMETER LocalFile
        Specifies a zip archive or SQL script to install from instead of downloading. Use this on servers with no internet access.

        Get the archive from the project release page on a machine that does have access and copy it across. Save-DbaCommunitySoftware does not produce a file for this: it consumes LocalFile the same way, to refresh the local cache. The release page for each tool is listed in the Save-DbaCommunitySoftware help.

        Because an archive belongs to exactly one tool, this can only be combined with a single Software value.

    .PARAMETER Force
        If this switch is enabled, the local cached copy of each tool is refreshed before installing and confirmation prompts are suppressed.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Objects are passed through from each installer unchanged, so the property set follows the tool rather than this command. Selecting several tools returns a mix of the shapes below, in the order the tools were requested. All three shapes share ComputerName, InstanceName and SqlInstance, so a mixed batch still groups and formats on those.

        FirstResponderKit, DarlingData, DbaMultiTool and WhoIsActive return one object per script the installer ran:

        - ComputerName (String): The name of the computer where the SQL Server instance resides
        - InstanceName (String): The name of the SQL Server instance
        - SqlInstance (String): The full SQL Server instance name (computer\instance)
        - Database (String): The name of the database the script was installed into
        - Name (String): The script base name, such as sp_Blitz or sp_BlitzCache. DarlingData installs from one combined script and so returns a single row named DarlingData; WhoIsActive returns a single row named sp_WhoisActive
        - Status (String): Installed when the object was created, Updated when it already existed, Skipped when the script does not apply to that instance version, Error when that script failed. DbaMultiTool never reports Skipped, and WhoIsActive reports only Installed or Updated
        - Version (String): WhoIsActive only. The sp_WhoisActive version read out of the installed script, or an empty string when the script carries no version header

        MaintenanceSolution returns one object per instance, not per script, and has no Database, Name or Status:

        - ComputerName (String): The name of the computer where the SQL Server instance resides
        - InstanceName (String): The name of the SQL Server instance
        - SqlInstance (String): The full SQL Server instance name (computer\instance)
        - Results (String): Success or Failed, covering the whole solution install on that instance

        SQLWATCH returns one object per instance and has no Name:

        - ComputerName (String): The name of the computer where the SQL Server instance resides
        - InstanceName (String): The name of the SQL Server instance
        - SqlInstance (String): The full SQL Server instance name (computer\instance)
        - Database (String): The name of the database SqlWatch was published to, SQLWATCH unless you pass Database
        - Status (System.Text.RegularExpressions.Match): The last parenthesized fragment of the DACPAC publish result, which renders as its matched text
        - DashboardPath (String): The full local file system path to the SqlWatch Dashboard directory

        Note: an instance a tool refuses, such as MaintenanceSolution against anything below SQL Server 2017, produces a warning from that installer and no object, while the rest of the batch continues.

    .NOTES
        Tags: Community, Install, MaintenanceSolution, FirstResponderKit, DarlingData, SqlWatch, WhoIsActive, DbaMultiTool
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaCommunitySoftware

    .EXAMPLE
        PS C:\> Install-DbaCommunitySoftware -SqlInstance sql2017 -Software All

        Installs every supported community tool on sql2017. Each tool lands in its own default database, so SqlWatch goes to SQLWATCH and the rest go to master.

    .EXAMPLE
        PS C:\> Install-DbaCommunitySoftware -SqlInstance sql2017 -Software FirstResponderKit, WhoIsActive -Database DBAtools

        Installs the First Responder Kit and sp_WhoIsActive into the DBAtools database on sql2017.

    .EXAMPLE
        PS C:\> Install-DbaCommunitySoftware -SqlInstance sql2017, sql2019 -Software MaintenanceSolution, DarlingData -Force

        Refreshes the local cached copies and installs the Ola Hallengren Maintenance Solution and DarlingData on both instances, without prompting for confirmation. Both instances are SQL Server 2017 or later, which the Maintenance Solution requires.

    .EXAMPLE
        PS C:\> Install-DbaCommunitySoftware -SqlInstance sql2017 -Software WhoIsActive -LocalFile C:\temp\sp_whoisactive.zip

        Installs sp_WhoIsActive on sql2017 from an already downloaded file, for a server with no internet access. LocalFile takes exactly one tool at a time.

    .EXAMPLE
        PS C:\> Get-Content C:\servers.txt | Install-DbaCommunitySoftware -Software FirstResponderKit -WhatIf

        Shows what the First Responder Kit install would do on every instance listed in servers.txt, without changing anything.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateSet("MaintenanceSolution", "FirstResponderKit", "DarlingData", "SQLWATCH", "WhoIsActive", "DbaMultiTool", "All")]
        [string[]]$Software,
        [ValidateNotNullOrEmpty()]
        [string]$Database,
        [string]$Branch,
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        $commandMap = @{
            MaintenanceSolution = "Install-DbaMaintenanceSolution"
            FirstResponderKit   = "Install-DbaFirstResponderKit"
            DarlingData         = "Install-DbaDarlingData"
            SQLWATCH            = "Install-DbaSqlWatch"
            WhoIsActive         = "Install-DbaWhoIsActive"
            DbaMultiTool        = "Install-DbaMultiTool"
        }

        $canonicalSoftware = @("MaintenanceSolution", "FirstResponderKit", "DarlingData", "SQLWATCH", "WhoIsActive", "DbaMultiTool")

        if ($Software -contains "All") {
            $resolvedSoftware = $canonicalSoftware
        } else {
            # ValidateSet accepts any casing but Select-Object -Unique compares case-sensitively on
            # both editions, so "WhoIsActive, whoisactive" would survive as two entries and install
            # twice. Fold each name onto its supported spelling and drop repeats, keeping the
            # requested order so the messages below read the way the caller typed the command.
            $resolvedSoftware = @()
            foreach ($requested in $Software) {
                $matchedSoftware = $canonicalSoftware | Where-Object { $PSItem -eq $requested }
                if ($resolvedSoftware -notcontains $matchedSoftware) {
                    $resolvedSoftware += $matchedSoftware
                }
            }
        }

        $requestedSoftware = $resolvedSoftware

        # Install-DbaSqlWatch refuses to run on PowerShell Core, but its own check sits in process
        # while the download it needs happens in begin, so calling it there refreshes the cache over
        # the network and only then fails. Drop it up front rather than pay for that on every run.
        if ($PSEdition -eq "Core" -and $resolvedSoftware -contains "SQLWATCH") {
            Write-Message -Level Warning -Message "Install-DbaSqlWatch does not support PowerShell Core, so SQLWATCH was skipped. Run it from Windows PowerShell instead."
            $resolvedSoftware = @($resolvedSoftware | Where-Object { $PSItem -ne "SQLWATCH" })

            if ($resolvedSoftware.Count -eq 0) {
                Stop-Function -Message "SQLWATCH was the only tool selected and it needs Windows PowerShell, so there is nothing left to install."
                return
            }
        }

        # Counted against what the caller asked for rather than what survived the Core filter
        # above. The archive belongs to one named tool, so two names are ambiguous however many
        # of them can run on this edition, and dropping SQLWATCH must never leave WhoIsActive
        # holding a SqlWatch zip.
        if ((Test-Bound -ParameterName LocalFile) -and $requestedSoftware.Count -gt 1) {
            $softwareList = $requestedSoftware -join ", "
            Stop-Function -Message "LocalFile points at a file for one tool, so it cannot be combined with $($requestedSoftware.Count) values ($softwareList). Run the command once per tool, or leave LocalFile off to download each one."
            return
        }

        # A whitespace name is never a real database, and letting it through would hand WhoIsActive
        # the master default below, quietly writing to a database the caller never asked for.
        if ((Test-Bound -ParameterName Database) -and [string]::IsNullOrWhiteSpace($Database)) {
            Stop-Function -Message "Database is only whitespace, which is not a database name. Pass the name you want, or leave Database off to let each installer use its own default."
            return
        }

        if ($Force) { $ConfirmPreference = "none" }

        $splatForward = @{
            SqlCredential   = $SqlCredential
            Database        = $Database
            Branch          = $Branch
            LocalFile       = $LocalFile
            Force           = $Force
            EnableException = $EnableException
        }

        foreach ($key in @($splatForward.Keys)) {
            if (-not $PSBoundParameters.ContainsKey($key)) {
                $null = $splatForward.Remove($key)
            }
        }

        # Cache each installer parameter list once so the per-instance loop can drop what a
        # tool does not accept - Branch in particular exists on only three of the six.
        $parameterMap = @{ }
        foreach ($tool in $resolvedSoftware) {
            $installer = Get-Command -Name $commandMap[$tool] -ErrorAction SilentlyContinue
            if (-not $installer) {
                Stop-Function -Message "$($commandMap[$tool]) is not available in this session, so $tool cannot be installed. Reimport dbatools and try again."
                return
            }
            $parameterMap[$tool] = @($installer.Parameters.Keys)
        }

        $targetInstances = @()
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # Collect rather than install. Every installer downloads its payload in begin and loops
        # instances in process, so one call per instance would fetch the same archive once per
        # target - and with Force, redownload it every time.
        foreach ($instance in $SqlInstance) {
            $targetInstances += $instance
        }
    }

    end {
        if (Test-FunctionInterrupt) { return }

        $instanceList = $targetInstances -join ", "

        foreach ($tool in $resolvedSoftware) {
            $commandName = $commandMap[$tool]

            $splatInstall = @{
                SqlInstance = $targetInstances
            }

            foreach ($key in $splatForward.Keys) {
                if ($parameterMap[$tool] -contains $key) {
                    $splatInstall[$key] = $splatForward[$key]
                }
            }

            if ($splatForward.ContainsKey("Branch") -and $parameterMap[$tool] -notcontains "Branch") {
                Write-Message -Level Warning -Message "$commandName installs from a single source, so Branch was ignored for $tool."
            }

            # Install-DbaWhoIsActive has no Database default: left unbound its own "-not $Database"
            # test opens an interactive Show-DbaDbList picker that would stall an unattended batch.
            if ($tool -eq "WhoIsActive" -and -not $splatInstall.ContainsKey("Database")) {
                $splatInstall["Database"] = "master"
            }

            Write-Message -Level Verbose -Message "Installing $tool on $instanceList with $commandName"

            try {
                & $commandName @splatInstall
            } catch {
                $splatInstallFailure = @{
                    Message     = "Failed to install $tool"
                    ErrorRecord = $PSItem
                    Target      = $targetInstances
                    Continue    = $true
                }
                Stop-Function @splatInstallFailure
            }
        }
    }
}