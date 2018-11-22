function Update-DbaInstance {
    <#
    .SYNOPSIS
        Invokes installation of SQL Server Service Packs and Cumulative Updates.

    .DESCRIPTION
        Starts and automated process of updating SQL Server installation to a specific version defined in the parameters.

    .PARAMETER ComputerName
        Target SQL Server computer.

    .PARAMETER Credential
        Windows Credential with permission to log on to the server running the SQL instance

    .PARAMETER Type
        Type of the update: All | ServicePack | CumulativeUpdate. Only usable with -Latest.
        Default: All

    .PARAMETER SqlServerVersion
        A target version of the installation you want to reach. Can be defined using the following general pattern: <MajorVersion><SPX><CUX>.
        All of the parts of the pattern can be ommitted if needed:
        2008R2SP1 - will update SQL 2008 to SP1
        2016CU3 - will update SQL 2016 to CU of the current Service Pack installed
        SP0CU3 - will update existing SQL Server version to RTM CU3 without installing any service packs
        SP1CU7 - will update existing SQL Server version to SP1 and then (after restart if -Restart is specified) to SP1CU7

    .PARAMETER Latest
        Install latest SP and CU known to the module. More details can be found by running Test-DbaBuild -SqlInstance YourSqlServer

    .PARAMETER RepositoryPath
        Path to the folder with SQL Server patches downloaded. It will be scanned recursively for available patches.

    .PARAMETER Restart
        Restart automatically if required.

    .PARAMETER Online
        Get the patch file from the Microsoft web-site.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Install, Patching, SP, CU
        Author: Kirill Kravtsov (@nvarscar) https://nvarscar.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Local Admin rights on destination computer(s).

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -SP 3

        Updates all applicable SQL Server installations on SQL1 to SP3

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1, SQL2 -Latest

        Updates all applicable SQL Server installations on SQL1 and SQL2 with the most recent patch found in your patch repository.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -Latest -Online

        Downloads the latest patch from Microsoft website and applies it to the existing installation of SQL Server on SQL1.


    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [Parameter(Mandatory, ParameterSetName = 'Version')]
        [ValidateNotNullOrEmpty()]
        [string]$SqlServerVersion,
        [Parameter(ParameterSetName = 'Latest')]
        [string[]]$MajorVersion,
        [Parameter(ParameterSetName = 'Latest')]
        [ValidateSet('All', 'ServicePack', 'CumulativeUpdate')]
        [string]$Type = 'All',
        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [switch]$Latest,
        [string]$RepositoryPath,
        [switch]$Restart,
        #[switch]$Online,
        [switch]$EnableException
    )
    begin {
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
                if ($ver -match '^(SQL)?(\d{4}(R2)?)?\s*SP(\d+)') {
                    $currentAction = @{
                        ServicePack = $Matches[3]
                    }
                    if ($Matches[2]) {
                        $currentAction += @{ MajorVersion = $Matches[2]}
                    }
                    $actions += $currentAction
                }
                if ($ver -match '^(SQL)?(\d{4}(R2)?)?\s*(SP)?(\d+)?CU(\d+)') {
                    $currentAction = @{
                        CumulativeUpdate = $Matches[5]
                    }
                    if ($Matches[2]) {
                        $currentAction += @{ MajorVersion = $Matches[2]}
                    }
                    if ($Matches[4]) {
                        $currentAction += @{ ServicePack = $Matches[4]}
                    }
                    $actions += $currentAction
                }
            }
        }

    }
    process {
        :computers foreach ($computer in $ComputerName) {
            if ($resolvedName = (Resolve-DbaNetworkName -ComputerName $computer.ComputerName).FullComputerName) {
                :actions foreach ($actionParam in $actions) {
                    if (Test-PendingReboot -ComputerName $resolvedName) {
                        #Exit the actions loop altogether - nothing can be installed here anyways
                        Stop-Function -Message "$resolvedName is pending a reboot. Reboot the computer before proceeding." -Continue -ContinueLabel computers
                    }
                    try {
                        Write-Message -Level Verbose -Message "Launching installation on $resolvedName with following params: $($actionParam | ConvertTo-Json -Depth 1 -Compress)"
                        Install-SqlServerUpdate @actionParam -ComputerName $resolvedName -Credential $Credential -Restart $Restart -RepositoryPath $RepositoryPath
                    } catch {
                        #Exit the actions loop altogether - upgrade failed
                        Stop-Function -Message "Update failed to install on $resolvedName" -ErrorRecord $_ -Continue -ContinueLabel computers
                    }
                }
                if (!$computer.IsIsLocalHost) {
                    if ($PSCmdlet.ShouldProcess($resolvedName, "Unregistering any leftover PSSession Configurations")) {
                        try {
                            Unregister-RemoteSessionConfiguration -ComputerName $resolvedName -Credential $Credential -Name "dbatools_Install-SqlServerUpdate"
                        } catch {
                            Stop-Function -Message "Failed to unregister PSSession Configurations on $resolvedName" -Continue -ContinueLabel computers
                        }
                    }
                }
            }
        }
    }
    end {

    }
}