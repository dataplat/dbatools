function Install-DbaCommunitySoftware {
    <#
    .SYNOPSIS
        Installs community-maintained SQL Server tooling through a single command

    .DESCRIPTION
        Installs one or more of the community stored procedure kits that dbatools ships installers for, without needing to remember six separate command names. This is the install-side counterpart to Save-DbaCommunitySoftware, which already unifies the download step behind one -Software parameter.

        Each tool is handed off to its dedicated installer, so behavior, prompts and output objects are exactly what you get from calling that command directly:

        - MaintenanceSolution: Install-DbaMaintenanceSolution (Ola Hallengren)
        - FirstResponderKit: Install-DbaFirstResponderKit (Brent Ozar Unlimited)
        - DarlingData: Install-DbaDarlingData (Erik Darling)
        - SQLWATCH: Install-DbaSqlWatch (Marcin Gminski)
        - WhoIsActive: Install-DbaWhoIsActive (Adam Machanic)
        - DbaMultiTool: Install-DbaMultiTool (John McCall)

        A failure against one tool does not stop the batch. The remaining tools and instances still run, and the failure is reported as a warning unless you use EnableException.

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
        Specifies a previously downloaded zip or script file to install from instead of downloading. Use this on servers with no internet access, after fetching the file with Save-DbaCommunitySoftware.

        Because a downloaded file belongs to exactly one tool, this can only be combined with a single Software value.

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

        Returns the objects emitted by each installer unchanged, so the shape follows the tool rather than this command. Most tools return one object per installed script with the following properties:

        - ComputerName: The name of the computer where the SQL Server instance resides
        - InstanceName: The name of the SQL Server instance
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database the tool was installed into
        - Name: The name of the installed script or stored procedure
        - Status: The result of the installation, such as Installed, Updated, Error or Skipped

        Two tools differ. Install-DbaMaintenanceSolution returns ComputerName, InstanceName, SqlInstance and Results, where Results is the outcome of the whole solution install rather than a per-script row. Install-DbaSqlWatch returns ComputerName, InstanceName, SqlInstance, Database, Status and DashboardPath, and has no Name property.

        Note: Tools that fail are reported through error handling and produce no output objects.

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
        PS C:\> Install-DbaCommunitySoftware -SqlInstance sql2016, sql2017 -Software MaintenanceSolution, DarlingData -Force

        Refreshes the local cached copies and installs the Ola Hallengren Maintenance Solution and DarlingData on both instances, without prompting for confirmation.

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

        if ($Software -contains "All") {
            $resolvedSoftware = @("MaintenanceSolution", "FirstResponderKit", "DarlingData", "SQLWATCH", "WhoIsActive", "DbaMultiTool")
        } else {
            $resolvedSoftware = @($Software | Select-Object -Unique)
        }

        if ((Test-Bound -ParameterName LocalFile) -and $resolvedSoftware.Count -gt 1) {
            $softwareList = $resolvedSoftware -join ", "
            Stop-Function -Message "LocalFile points at a file for one tool, so it cannot be combined with $($resolvedSoftware.Count) values ($softwareList). Run the command once per tool, or leave LocalFile off to download each one."
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
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            foreach ($tool in $resolvedSoftware) {
                $commandName = $commandMap[$tool]

                $splatInstall = @{
                    SqlInstance = $instance
                }

                foreach ($key in $splatForward.Keys) {
                    if ($parameterMap[$tool] -contains $key) {
                        $splatInstall[$key] = $splatForward[$key]
                    }
                }

                if ($splatForward.ContainsKey("Branch") -and $parameterMap[$tool] -notcontains "Branch") {
                    Write-Message -Level Warning -Message "$commandName installs from a single source, so Branch was ignored for $tool on $instance."
                }

                # Install-DbaWhoIsActive has no Database default: left unbound it opens an
                # interactive Show-DbaDbList picker that would stall an unattended batch.
                if ($tool -eq "WhoIsActive" -and -not $splatInstall.ContainsKey("Database")) {
                    $splatInstall["Database"] = "master"
                }

                Write-Message -Level Verbose -Message "Installing $tool on $instance with $commandName"

                try {
                    & $commandName @splatInstall
                } catch {
                    Stop-Function -Message "Failed to install $tool on $instance" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}