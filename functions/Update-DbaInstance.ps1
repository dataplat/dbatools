function Update-DbaInstance {
    <#
    .SYNOPSIS
        Invokes installation of SQL Server Service Packs and Cumulative Updates.

    .DESCRIPTION
        Starts and automated process of updating SQL Server installation to a specific version defined in the parameters.
        The command will:
        * Search for SQL Server installations in a remote registry
        * Check if current settings are applicable to the current SQL Server versions
        * Search for a KB executable in a folder specified in -RepositoryPath
        * Establish a PSRemote connection to the target machine if necessary
        * Extract KB to a temporary folder in a current user's profile
        * Run the installation from the temporary folder updating all instances on the computer at once
        * Remove temporary files
        * Restart the computer (if -Restart is specified)
        * Repeat for each consequent KB and computer

        The impact of this function is set to High, if you don't want to receive interactive prompts, set -Confirm to $false.
        Credentials are a required parameter for remote machines. Without specifying -Credential, the installation will fail due to lack of permissions.

    .PARAMETER ComputerName
        Target SQL Server computer.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server. Must be specified for any remote connection.

    .PARAMETER Type
        Type of the update: All | ServicePack | CumulativeUpdate. Only usable with -Latest.
        Default: All

    .PARAMETER KB
        Install a specific update or list of updates.

    .PARAMETER SqlServerVersion
        A target version of the installation you want to reach. Can be defined using the following general pattern: <MajorVersion><SPX><CUX>.
        Any part of the pattern can be ommitted if needed:
        2008R2SP1 - will update SQL 2008R2 to SP1
        2016CU3 - will update SQL 2016 to CU3 of current Service Pack installed
        SP0CU3 - will update all existing SQL Server versions to RTM CU3 without installing any service packs
        SP1CU7 - will update all existing SQL Server versions to SP1 and then (after restart if -Restart is specified) to SP1CU7
        CU7 - will update all existing SQL Server versions to CU7 of current Service Pack installed

    .PARAMETER MajorVersion
        Designed to work in conjunction with -Latest to only update specific version(s) of SQL Server. Syntax: SQL20XX or simply 20XX.

    .PARAMETER Latest
        Install latest SP and CU known to the module. More details can be found by running Test-DbaBuild -SqlInstance YourSqlServer

        Note: `-Latest -Type CumulativeUpdate` will try to install CU from the latest SP available. Make sure to upgrate servers to proper SP beforehand.

    .PARAMETER RepositoryPath
        Path to the folder(s) with SQL Server patches downloaded. It will be scanned recursively for available patches.
        Path should be available from both server with SQL Server installation and client that runs the command.
        All file names should match the pattern used by Microsoft: SQLServer####*-KB###-*x##*.exe
        If a file is missing in the repository, the installation will fail.
        Consider setting the following configuration if you want to omit this parameter: `Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates'`

    .PARAMETER Restart
        Restart automatically if required.

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
        PS C:\> Update-DbaInstance -ComputerName SQL1 -SqlServerVersion SP3 -RepositoryPath \\network\share

        Updates all applicable SQL Server installations on SQL1 to SP3.
        SP3 binary files will be

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1, SQL2 -Latest -Restart

        Updates all applicable SQL Server installations on SQL1 and SQL2 with the most recent patch.
        It will install latest ServicePack, restart the computers, install latest Cumulative Update, and finally restart the computer once again.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -Latest -MajorVersion 2012 -Type ServicePack

        Updates SQL Server 2012 on SQL1 with the most recent ServicePack found in your patch repository.


    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [Parameter(Mandatory, ParameterSetName = 'Version')]
        [ValidateNotNullOrEmpty()]
        [string[]]$SqlServerVersion,
        [Parameter(ParameterSetName = 'Latest')]
        [string[]]$MajorVersion,
        [Parameter(ParameterSetName = 'Latest')]
        [ValidateSet('All', 'ServicePack', 'CumulativeUpdate')]
        [string]$Type = 'All',
        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [switch]$Latest,
        [string[]]$RepositoryPath,
        [switch]$Restart,
        [switch]$EnableException
    )
    begin {

    }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Version') {
            if ($SqlServerVersion -notmatch '^((SQL)?\d{4}(R2)?)?\s*(SP\d+)?\s*(CU\d+)?$') {
                Stop-Function -Message "$SqlServerVersion is an incorrect SqlServerVersion value, please refer to Get-Help Update-DbaInstance -Parameter SqlServerVersion"
                return
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'Latest') {
            $majorVersions = @()
            foreach ($mv in $MajorVersion) {
                if ($mv -match '^(SQL)?(\d{4}(R2)?)$') {
                    $majorVersions += $Matches[2]
                } else {
                    Stop-Function -Message "$mv is an incorrect MajorVersion value, please refer to Get-Help Update-DbaInstance -Parameter MajorVersion"
                    return
                }
            }
        }
        $actions = @()
        if ($Latest) {
            if ($Type -in 'All', 'ServicePack') {
                $actions += @{
                    Type         = 'ServicePack'
                    Latest       = $true
                    MajorVersion = $majorVersions
                }
            }
            if ($Type -in 'All', 'CumulativeUpdate') {
                $actions += @{
                    Type         = 'CumulativeUpdate'
                    Latest       = $true
                    MajorVersion = $majorVersions
                }
            }
        } else {
            foreach ($ver in $SqlServerVersion) {
                $currentAction = @{}
                if ($ver -and $ver -match '^(SQL)?(\d{4}(R2)?)?\s*(SP)?(\d+)?(CU)?(\d+)?') {
                    Write-Message -Level Debug "Parsed SqlServerVersion as $($Matches[2,5,7] | ConvertTo-Json -Depth 1 -Compress)"
                    if (-not ($Matches[5] -or $Matches[7])) {
                        Stop-Function -Message "Either SP or CU should be specified in $ver, please refer to Get-Help Update-DbaInstance -Parameter SqlServerVersion"
                        return
                    }
                    if ($Matches[2]) {
                        $currentAction += @{ MajorVersion = $Matches[2]}
                    }
                    if ($Matches[5]) {
                        $currentAction += @{ ServicePack = $Matches[5]}
                        $actions += $currentAction
                    }
                    if ($Matches[7]) {
                        $actions += $currentAction.Clone() + @{ CumulativeUpdate = $Matches[7] }
                    }
                } else {
                    Stop-Function -Message "$ver is an incorrect SqlServerVersion value, please refer to Get-Help Update-DbaInstance -Parameter SqlServerVersion"
                    return
                }
            }
        }
        #Resolve all the provided names
        $resolvedComputers = @()
        foreach ($computer in $ComputerName) {
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
                try {
                    Write-Message -Level Verbose -Message "Launching installation on $resolvedName with following params: $($actionParam | ConvertTo-Json -Depth 1 -Compress)"
                    $install = Install-SqlServerUpdate @actionParam -ComputerName $resolvedName -Credential $Credential -Restart $Restart -RepositoryPath $RepositoryPath
                } catch {
                    #Exit the actions loop altogether - upgrade failed
                    Stop-Function -Message "Update failed to install on $resolvedName" -ErrorRecord $_ -Continue -ContinueLabel computers
                }
                if ($install) {
                    $install
                    if ($install.Restarted -contains $false) {
                        Stop-Function -Message "Please restart $($install.ComputerName) to complete the installation of SQL$($install.MajorVersion)$($install.TargetLevel). No further updates will be installed on this computer." -EnableException $false -Continue -ContinueLabel computers
                    }
                }
            }
        }
        # Unregister PSRemote configurations possibly created by Install-SqlServerUpdate
        foreach ($computer in $resolvedComputers) {
            if (-not ([DbaInstanceParameter]$computer).IsLocalHost) {
                Write-Message -Level Verbose -Message "Unregistering any leftover PSSession Configurations on $computer"
                try {
                    $unreg = Unregister-RemoteSessionConfiguration -ComputerName $computer -Credential $Credential -Name dbatoolsInvokeProgram
                    if (!$unreg.Successful) {
                        throw $unreg.Status
                    }
                } catch {
                    Stop-Function -Message "Failed to unregister PSSession Configurations on $computer" -ErrorRecord $_
                }
            }
        }
    }
    end {

    }
}