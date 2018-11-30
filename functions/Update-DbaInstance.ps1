function Update-DbaInstance {
    <#
    .SYNOPSIS
        Invokes installation of SQL Server Service Packs and Cumulative Updates on local and remote servers.

    .DESCRIPTION
        Starts and automated process of updating SQL Server installation to a specific version defined in the parameters.
        The command will:

        * Search for SQL Server installations in a remote registry
        * Check if current settings are applicable to the current SQL Server versions
        * Search for a KB executable in a folder specified in -Path
        * Establish a PSRemote connection to the target machine if necessary
        * Extract KB to a temporary folder in a current user's profile
        * Run the installation from the temporary folder updating all instances on the computer at once
        * Remove temporary files
        * Restart the computer (if -Restart is specified)
        * Repeat for each consequent KB and computer

        The impact of this function is set to High, if you don't want to receive interactive prompts, set -Confirm to $false.
        Credentials are a required parameter for remote machines. Without specifying -Credential, the installation will fail due to lack of permissions.

        CredSSP is a recommended transport for running the updates remotely. Update-DbaInstance will attempt to reconfigure
        local and remote hosts to support CredSSP, which is why it is desirable to run this command in an elevated console at all times.
        CVE-2018-0886 security update is required for both local and remote hosts. If CredSSP connections are failing, make sure to
        apply recent security updates prior to doing anything else.

        Always backup databases and configurations prior to upgrade.

    .PARAMETER ComputerName
        Target computer with SQL instance or instsances.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server. Must be specified for any remote connection.

    .PARAMETER Type
        Type of the update: All | ServicePack | CumulativeUpdate. Mutually exclusive with -Version.
        Default: All

    .PARAMETER KB
        Install a specific update or list of updates. Can be a number of a string KBXXXXXXX.

    .PARAMETER Version
        A target version of the installation you want to reach. If not specified, a latest available version would be used by default.
        Can be defined using the following general pattern: <MajorVersion><SPX><CUX>.
        Any part of the pattern can be ommitted if needed:
        2008R2SP1 - will update SQL 2008R2 to SP1
        2016CU3 - will update SQL 2016 to CU3 of current Service Pack installed
        SP0CU3 - will update all existing SQL Server versions to RTM CU3 without installing any service packs
        SP1CU7 - will update all existing SQL Server versions to SP1 and then (after restart if -Restart is specified) to SP1CU7
        CU7 - will update all existing SQL Server versions to CU7 of current Service Pack installed

    .PARAMETER MajorVersion
        When -Version is not specified, it allows user to only update specific version(s) of SQL Server. Syntax: SQL20XX or simply 20XX.

    .PARAMETER Path
        Path to the folder(s) with SQL Server patches downloaded. It will be scanned recursively for available patches.
        Path should be available from both server with SQL Server installation and client that runs the command.
        All file names should match the pattern used by Microsoft: SQLServer####*-KB###-*x##*.exe
        If a file is missing in the repository, the installation will fail.
        Consider setting the following configuration if you want to omit this parameter: `Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates'`

    .PARAMETER Restart
        Restart computer automatically after a successful installation of a patch and wait until it comes back online.
        Using this parameter is the only way to chain-install more than 1 patch on a computer, since every single patch will require a restart of said computer.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Install, Patching, SP, CU, Instance
        Author: Kirill Kravtsov (@nvarscar) https://nvarscar.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Local Admin rights on destination computer(s).

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -Version SP3 -Path \\network\share

        Updates all applicable SQL Server installations on SQL1 to SP3.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1, SQL2 -Restart -Path \\network\share

        Updates all applicable SQL Server installations on SQL1 and SQL2 with the most recent patch.
        It will install latest ServicePack, restart the computers, install latest Cumulative Update, and finally restart the computer once again.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -MajorVersion 2012 -Type ServicePack -Path \\network\share

        Updates SQL Server 2012 on SQL1 with the most recent ServicePack found in your patch repository.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -KB 123456 -Restart -Path \\network\share

        Installs KB 123456 on SQL1 and restarts the computer.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "")]
    # Shouldprocess is handled by internal function Install-SqlServerUpdate
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Latest')]
    Param (
        [parameter(ValueFromPipeline, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [Parameter(Mandatory, ParameterSetName = 'Version')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Version,
        [Parameter(ParameterSetName = 'Latest')]
        [string[]]$MajorVersion,
        [Parameter(ParameterSetName = 'Latest')]
        [ValidateSet('All', 'ServicePack', 'CumulativeUpdate')]
        [string]$Type = 'All',
        [Parameter(Mandatory, ParameterSetName = 'KB')]
        [ValidateNotNullOrEmpty()]
        [string[]]$KB,
        [string[]]$Path,
        [switch]$Restart,
        [switch]$EnableException
    )
    begin {
        #Validating parameters
        if ($PSCmdlet.ParameterSetName -eq 'Version') {
            if ($Version -notmatch '^((SQL)?\d{4}(R2)?)?\s*(RTM|SP\d+)?\s*(CU\d+)?$') {
                Stop-Function -Category InvalidArgument -Message "$Version is an incorrect Version value, please refer to Get-Help Update-DbaInstance -Parameter Version"
                return
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'Latest') {
            $majorVersions = @()
            foreach ($mv in $MajorVersion) {
                if ($mv -match '^(SQL)?(\d{4}(R2)?)$') {
                    $majorVersions += $Matches[2]
                } else {
                    Stop-Function -Category InvalidArgument -Message "$mv is an incorrect MajorVersion value, please refer to Get-Help Update-DbaInstance -Parameter MajorVersion"
                    return
                }
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'KB') {
            $kbList = @()
            foreach ($kbItem in $KB) {
                if ($kbItem -match '^(KB)?(\d+)$') {
                    $kbList += $Matches[2]
                } else {
                    Stop-Function -Category InvalidArgument -Message "$kbItem is an incorrect KB value, please refer to Get-Help Update-DbaInstance -Parameter KB"
                    return
                }
            }
        }
        $actions = @()
        #Putting together list of actions based on current ParameterSet
        if ($PSCmdlet.ParameterSetName -eq 'Latest') {
            if ($Type -in 'All', 'ServicePack') {
                $actions += @{
                    Type         = 'ServicePack'
                    MajorVersion = $majorVersions
                }
            }
            if ($Type -in 'All', 'CumulativeUpdate') {
                $actions += @{
                    Type         = 'CumulativeUpdate'
                    MajorVersion = $majorVersions
                }
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'Version') {
            foreach ($ver in $Version) {
                $currentAction = @{
                }
                if ($ver -and $ver -match '^(SQL)?(\d{4}(R2)?)?\s*(RTM|SP)?(\d+)?(CU)?(\d+)?') {
                    Write-Message -Level Debug "Parsed Version as $($Matches[2, 5, 7] | ConvertTo-Json -Depth 1 -Compress)"
                    if (-not ($Matches[5] -or $Matches[7])) {
                        Stop-Function -Category InvalidArgument -Message "Either SP or CU should be specified in $ver, please refer to Get-Help Update-DbaInstance -Parameter Version"
                        return
                    }
                    if ($null -ne $Matches[2]) {
                        $currentAction += @{
                            MajorVersion = $Matches[2]
                        }
                    }
                    if ($null -ne $Matches[5]) {
                        $currentAction += @{
                            ServicePack = $Matches[5]
                        }
                        if ($Matches[5] -ne '0') {
                            $actions += $currentAction
                        }
                    }
                    if ($null -ne $Matches[7]) {
                        $actions += $currentAction.Clone() + @{
                            CumulativeUpdate = $Matches[7]
                        }
                    }
                } else {
                    Stop-Function -Category InvalidArgument -Message "$ver is an incorrect Version value, please refer to Get-Help Update-DbaInstance -Parameter Version"
                    return
                }
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'KB') {
            foreach ($kbItem in $kbList) {
                $actions += @{
                    KB = $kbItem
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        #Resolve all the provided names
        $resolvedComputers = @()
        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            if ($resolvedComputer = Resolve-DbaNetworkName -ComputerName $computer.ComputerName) {
                $resolvedComputers += $resolvedComputer.FullComputerName
            }
        }
        #Initialize installations for each computer
        :computers foreach ($resolvedName in $resolvedComputers) {
            :actions foreach ($actionParam in $actions) {
                if (Test-PendingReboot -ComputerName $resolvedName) {
                    #Exit the actions loop altogether - nothing can be installed here anyways
                    Stop-Function -Message "$resolvedName is pending a reboot. Reboot the computer before proceeding." -Continue -ContinueLabel computers
                }
                Write-Message -Level Verbose -Message "Launching installation on $resolvedName with following params: $($actionParam | ConvertTo-Json -Depth 1 -Compress)"
                $install = Install-SqlServerUpdate @actionParam -ComputerName $resolvedName -Credential $Credential -Restart $Restart -Path $Path
                if ($install) {
                    $install
                    if ($install.Successful -contains $false) {
                        #Exit the actions loop altogether - upgrade failed
                        Stop-Function -Message "Update failed to install on $resolvedName" -Continue -ContinueLabel computers
                    }
                    if ($install.Restarted -contains $false) {
                        Stop-Function -Message "Please restart $($install.ComputerName) to complete the installation of SQL$($install.MajorVersion)$($install.TargetLevel). No further updates will be installed on this computer." -EnableException $false -Continue -ContinueLabel computers
                    }
                }
            }
        }
    }
}