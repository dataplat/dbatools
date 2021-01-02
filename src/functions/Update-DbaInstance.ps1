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
        Target computer with SQL instance or instances.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if update Repository is located on a network folder.

    .PARAMETER Type
        Type of the update: All | ServicePack | CumulativeUpdate.
        Default: All
        Use -Version to limit upgrade to a certain Major version of SQL Server.

    .PARAMETER KB
        Install a specific update or list of updates. Can be a number of a string KBXXXXXXX.

    .PARAMETER Version
        A target version of the installation you want to reach. If not specified, a latest available version would be used by default.
        Can be defined using the following general pattern: <MajorVersion><SPX><CUX>.
        Any part of the pattern can be omitted if needed:
        2008R2SP1 - will update SQL 2008R2 to SP1
        2016CU3 - will update SQL 2016 to CU3 of current Service Pack installed
        SP0CU3 - will update all existing SQL Server versions to RTM CU3 without installing any service packs
        SP1CU7 - will update all existing SQL Server versions to SP1 and then (after restart if -Restart is specified) to SP1CU7
        CU7 - will update all existing SQL Server versions to CU7 of current Service Pack installed

    .PARAMETER Path
        Path to the folder(s) with SQL Server patches downloaded. It will be scanned recursively for available patches.
        Path should be available from both server with SQL Server installation and client that runs the command.
        All file names should match the pattern used by Microsoft: SQLServer####*-KB###-*x##*.exe
        If a file is missing in the repository, the installation will fail.
        Consider setting the following configuration if you want to omit this parameter: `Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates'`

    .PARAMETER Restart
        Restart computer automatically after a successful installation of a patch and wait until it comes back online.
        Using this parameter is the only way to chain-install more than 1 patch on a computer, since every single patch will require a restart of said computer.

    .PARAMETER Continue
        Continues a failed installation attempt when specified. Will abort a previously failed installation otherwise.

    .PARAMETER Authentication
        Chooses an authentication protocol for remote connections.
        If the protocol fails to establish a connection

        Defaults:
        * CredSSP when -Credential is specified - due to the fact that repository Path is usually a network share and credentials need to be passed to the remote host to avoid the double-hop issue.
        * Default when -Credential is not specified. Will likely fail if a network path is specified.

    .PARAMETER InstanceName
        Only updates a specific instance(s).

    .PARAMETER Throttle
        Maximum number of computers updated in parallel. Once reached, the update operations will queue up.
        Default: 50

    .PARAMETER ArgumentList
        A list of extra arguments to pass to the execution file. Accepts one or more strings containing command line parameters.
        Example: ... -ArgumentList "/SkipRules=RebootRequiredCheck", "/Q"

    .PARAMETER Download
        Download missing KBs to the first folder specified in the -Path parameter.
        Files would be first downloaded to the local machine (TEMP folder), and then distributed onto remote machines if needed.
        If the Path is a network Path, the files would be downloaded straight to the network folder and executed from there.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ExtractPath
        Lets you specify a location to extract the update file to on the system requiring the update. e.g. C:\temp

    .LINK
        https://dbatools.io/Update-DbaInstance

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
        Prompts for confirmation before the update.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1, SQL2 -Restart -Path \\network\share -Confirm:$false

        Updates all applicable SQL Server installations on SQL1 and SQL2 with the most recent patch.
        It will install latest ServicePack, restart the computers, install latest Cumulative Update, and finally restart the computer once again.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -Version 2012 -Type ServicePack -Path \\network\share

        Updates SQL Server 2012 on SQL1 with the most recent ServicePack found in your patch repository.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Prompts for confirmation before the update.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -KB 123456 -Restart -Path \\network\share -Confirm:$false

        Installs KB 123456 on SQL1 and restarts the computer.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName Server1 -Version SQL2012SP3, SQL2016SP2CU3 -Path \\network\share -Restart -Confirm:$false

        Updates SQL 2012 to SP3 and SQL 2016 to SP2CU3 on Server1. Each update will be followed by a restart.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName Server1 -Path \\network\share -Restart -Confirm:$false -ExtractPath "C:\temp"

        Updates all applicable SQL Server installations on Server1 with the most recent patch. Each update will be followed by a restart.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Does not prompt for confirmation.
        Extracts the files in local driver on Server1 C:\temp.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName Server1 -Path \\network\share -ArgumentList "/SkipRules=RebootRequiredCheck"

        Updates all applicable SQL Server installations on Server1 with the most recent patch.
        Additional command line parameters would be passed to the executable.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -Version CU3 -Download -Path \\network\share -Confirm:$false

        Downloads an appropriate CU KB to \\network\share and installs it onto SQL1.
        Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Version')]
    Param (
        [parameter(ValueFromPipeline, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [Parameter(ParameterSetName = 'Version')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Version,
        [Parameter(ParameterSetName = 'Version')]
        [ValidateSet('All', 'ServicePack', 'CumulativeUpdate')]
        [string[]]$Type = @('All'),
        [Parameter(Mandatory, ParameterSetName = 'KB')]
        [ValidateNotNullOrEmpty()]
        [string[]]$KB,
        [Alias("Instance")]
        [string]$InstanceName,
        [string[]]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerUpdates'),
        [switch]$Restart,
        [switch]$Continue,
        [ValidateNotNull()]
        [int]$Throttle = 50,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = @('CredSSP', 'Default')[$null -eq $Credential],
        [string]$ExtractPath,
        [string[]]$ArgumentList,
        [switch]$Download,
        [switch]$EnableException

    )
    begin {
        $notifiedCredentials = $false
        $notifiedUnsecure = $false
        #Validating parameters
        if ($PSCmdlet.ParameterSetName -eq 'Version') {
            foreach ($v in $Version) {
                if ($v -notmatch '^((SQL)?\d{4}(R2)?)?\s*(RTM|SP\d+)?\s*(CU\d+)?$') {
                    Stop-Function -Category InvalidArgument -Message "$Version is an incorrect Version value, please refer to Get-Help Update-DbaInstance -Parameter Version"
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
        $actionTemplate = @{ }
        if ($InstanceName) { $actionTemplate.InstanceName = $InstanceName }
        if ($Continue) { $actionTemplate.Continue = $Continue }
        #Putting together list of actions based on current ParameterSet
        if ($PSCmdlet.ParameterSetName -eq 'Version') {
            if ($Type -contains 'All') { $typeList = @('ServicePack', 'CumulativeUpdate') }
            else { $typeList = $Type | Sort-Object -Descending }
            foreach ($ver in $Version) {
                $currentAction = $actionTemplate.Clone()
                if ($ver -and $ver -match '^(SQL)?(\d{4}(R2)?)?\s*(RTM|SP)?(\d+)?(CU)?(\d+)?') {
                    $majorV, $spV, $cuV = $Matches[2, 5, 7]
                    Write-Message -Level Debug -Message "Parsed Version as Major $majorV SP $spV CU $cuV"
                    # Add appropriate fields to the splat
                    # Add version to every field
                    if ($null -ne $majorV) {
                        $currentAction += @{
                            MajorVersion = $majorV
                        }
                        # When version is the only thing that is specified, we want all the types added
                        if ($null -eq $spV -and $null -eq $cuV) {
                            foreach ($currentType in $typeList) {
                                $actions += $currentAction.Clone() + @{ Type = $currentType }
                            }
                        }
                    }
                    #when SP# is specified
                    if ($null -ne $spV) {
                        $currentAction += @{
                            ServicePack = $spV
                        }
                        # ignore SP0 and trigger only when SP is in Type
                        if ($spV -ne '0' -and 'ServicePack' -in $typeList) {
                            $actions += $currentAction.Clone()
                        }
                    }
                    # When CU# is specified, but ignore CU0 and trigger only when CU is in Type
                    if ($null -ne $cuV -and $cuV -ne '0' -and 'CumulativeUpdate' -in $typeList) {
                        $actions += $currentAction.Clone() + @{ CumulativeUpdate = $cuV }
                    }
                } else {
                    Stop-Function -Category InvalidArgument -Message "$ver is an incorrect Version value, please refer to Get-Help Update-DbaInstance -Parameter Version"
                    return
                }
            }
            # If no version specified, simply apply latest $currentType
            if (!$Version) {
                foreach ($currentType in $typeList) {
                    $currentAction = $actionTemplate.Clone() + @{
                        Type = $currentType
                    }
                    $actions += $currentAction
                }
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'KB') {
            foreach ($kbItem in $kbList) {
                $currentAction = $actionTemplate.Clone() + @{
                    KB = $kbItem
                }
                $actions += $currentAction
            }
        }
        # debug message
        foreach ($a in $actions) {
            Write-Message -Level Debug -Message "Added installation action $($a | ConvertTo-Json -Depth 1 -Compress)"
        }
        # defining how to process the final results
        $outputHandler = {
            $_ | Select-DefaultView -Property ComputerName, MajorVersion, TargetLevel, KB, Successful, Restarted, InstanceName, Installer, Notes
            if ($_.Successful -eq $false) {
                Write-Message -Level Warning -Message "Update failed: $($_.Notes -join ' | ')"
            }
        }
        function Join-AdminUnc {
            <#
                .SYNOPSIS
                Internal function. Parses a path to make it an admin UNC.
            #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [DbaInstanceParameter]$ComputerName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Path

            )
            if ($Path.StartsWith("\\")) {
                return $filepath
            }

            $servername = $ComputerName.ComputerName
            $newpath = Join-Path "\\$servername\" $Path.replace(':', '$')
            return $newpath
        }
        function Copy-UncFile {
            <#

                SYNOPSIS
                Internal function. Uses PSDrive to copy file to the remote system.

                #>
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [DbaInstanceParameter]$ComputerName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Path,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Destination,

                [PSCredential]$Credential
            )
            if (([DbaInstanceParameter]$groupItem.ComputerName).IsLocalHost) {
                $remoteFolder = $Destination
            } else {
                $uncFileName = Join-AdminUnc -ComputerName $ComputerName -Path $Destination
                $driveSplat = @{
                    Name       = 'UpdateCopy'
                    Root       = $uncFileName
                    PSProvider = 'FileSystem'
                    Credential = $Credential
                }
                $null = New-PSDrive @driveSplat -ErrorAction Stop
                $remoteFolder = 'UpdateCopy:\'
            }
            try {
                Copy-Item -Path $Path -Destination $remoteFolder -ErrorAction Stop
            } finally {
                if (-Not ([DbaInstanceParameter]$groupItem.ComputerName).IsLocalHost) {
                    $null = Remove-PSDrive -Name UpdateCopy -Force
                }
            }
        }
        function Test-NetworkPath {
            <#

            SYNOPSIS
            Internal function. Tests if a path is a network path

            #>
            param (
                [Parameter(ValueFromPipeline)]
                [string]$Path
            )
            begin { $pathList = @() }
            process { $pathList += $Path -like '\\*' }
            end { return $pathList -contains $true }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        #Resolve all the provided names
        $resolvedComputers = @()
        $pathIsNetwork = $Path | Test-NetworkPath
        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            if (-not $computer.IsLocalHost -and -not $notifiedCredentials -and -not $Credential -and $pathIsNetwork) {
                Write-Message -Level Warning -Message "Explicit -Credential might be required when running agains remote hosts and -Path is a network folder"
                $notifiedCredentials = $true
            }
            if ($resolvedComputer = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential) {
                $resolvedComputers += $resolvedComputer.FullComputerName
            }
        }
        #Leave only unique computer names
        $resolvedComputers = $resolvedComputers | Sort-Object -Unique
        #Process planned actions and gather installation actions
        $installActions = @()
        $downloads = @()
        :computers foreach ($resolvedName in $resolvedComputers) {
            $activity = "Preparing to update SQL Server on $resolvedName"
            ## Find the current version on the computer
            Write-ProgressHelper -ExcludePercent -Activity $activity -StepNumber 0 -Message "Gathering all SQL Server instance versions"
            try {
                $components = Get-SQLInstanceComponent -ComputerName $resolvedName -Credential $Credential
            } catch {
                Stop-Function -Message "Error while looking for SQL Server installations on $resolvedName" -Continue -ErrorRecord $_
            }
            if (!$components) {
                Stop-Function -Message "No SQL Server installations found on $resolvedName" -Continue
            }
            Write-Message -Level Debug -Message "Found $(($components | Measure-Object).Count) existing SQL Server instance components: $(($components | ForEach-Object { "$($_.InstanceName)($($_.InstanceType) $($_.Version.NameLevel))" }) -join ',')"
            # Filter for specific instance name
            if ($InstanceName) {
                $components = $components | Where-Object { $_.InstanceName -eq $InstanceName }
            }
            try {
                $restartNeeded = Test-PendingReboot -ComputerName $resolvedName -Credential $Credential
            } catch {
                Stop-Function -Message "Failed to get reboot status from $resolvedName" -Continue -ErrorRecord $_
            }
            if ($restartNeeded -and (-not $Restart -or ([DbaInstanceParameter]$resolvedName).IsLocalHost)) {
                #Exit the actions loop altogether - nothing can be installed here anyways
                Stop-Function -Message "$resolvedName is pending a reboot. Reboot the computer before proceeding." -Continue
            }
            $upgrades = @()
            :actions foreach ($actionItem in $actions) {
                # Clone action to use as a splat
                $currentAction = $actionItem.Clone()
                # Attempt to configure CredSSP for the remote host when credentials are defined
                if ($Credential -and -not ([DbaInstanceParameter]$resolvedName).IsLocalHost -and $Authentication -eq 'Credssp') {
                    Write-Message -Level Verbose -Message "Attempting to configure CredSSP for remote connections"
                    Initialize-CredSSP -ComputerName $resolvedName -Credential $Credential -EnableException $false
                    # Verify remote connection and confirm using unsecure credentials
                    try {
                        $secureProtocol = Invoke-Command2 -ComputerName $resolvedName -Credential $Credential -Authentication $Authentication -ScriptBlock { $true } -Raw
                    } catch {
                        $secureProtocol = $false
                    }
                    # only ask once about using unsecure protocol
                    if (-not $secureProtocol -and -not $notifiedUnsecure) {
                        if ($PSCmdlet.ShouldProcess($resolvedName, "Primary protocol ($Authentication) failed, sending credentials via potentially unsecure protocol")) {
                            $notifiedUnsecure = $true
                        } else {
                            Stop-Function -Message "Failed to connect to $resolvedName through $Authentication protocol. No actions will be performed on that computer." -Continue -ContinueLabel computers
                        }
                    }
                }
                # Pass only relevant components
                if ($currentAction.MajorVersion) {
                    Write-Message -Level Debug -Message "Limiting components to version $($currentAction.MajorVersion)"
                    $selectedComponents = $components | Where-Object { $_.Version.NameLevel -contains $currentAction.MajorVersion }
                    $currentAction.Remove('MajorVersion')
                } else {
                    $selectedComponents = $components
                }
                Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Looking for a KB file for a chosen version"
                Write-Message -Level Debug -Message "Looking for appropriate KB file on $resolvedName with following params: $($currentAction | ConvertTo-Json -Depth 1 -Compress)"
                # get upgrade details for each component
                $upgradeDetails = Get-SqlInstanceUpdate @currentAction -ComputerName $resolvedName -Credential $Credential -Component $selectedComponents
                if ($upgradeDetails.Successful -contains $false) {
                    #Exit the actions loop altogether - upgrade cannot be performed
                    $upgradeDetails
                    Stop-Function -Message "Update cannot be applied to $resolvedName | $($upgradeDetails.Notes -join ' | ')" -Continue -ContinueLabel computers
                }

                foreach ($detail in $upgradeDetails) {
                    # search for installer for each target upgrade
                    $kbLookupParams = @{
                        ComputerName   = $resolvedName
                        Credential     = $Credential
                        Authentication = $Authentication
                        Architecture   = $detail.Architecture
                        MajorVersion   = $detail.MajorVersion
                        Path           = $Path
                        KB             = $detail.KB
                    }
                    try {
                        $installer = Find-SqlInstanceUpdate @kbLookupParams
                    } catch {
                        Stop-Function -Message "Failed to enumerate files in -Path" -ErrorRecord $_ -Continue
                    }
                    if ($installer) {
                        $detail.Installer = $installer.FullName
                    } elseif ($Download) {
                        $downloads += [PSCustomObject]@{ KB = $detail.KB; Architecture = $detail.Architecture }
                    } else {
                        Stop-Function -Message "Could not find installer for the SQL$($detail.MajorVersion) update KB$($detail.KB)" -Continue
                    }
                    # update components to mirror the updated version - will be used for multi-step upgrades
                    foreach ($component in $components) {
                        if ($component.Version.NameLevel -eq $detail.TargetVersion.NameLevel) {
                            $component.Version = $detail.TargetVersion
                        }
                    }
                    # finally, add the upgrade details to the upgrade list
                    $upgrades += $detail
                }
            }
            if ($upgrades) {
                Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Preparing installation"
                $chosenVersions = ($upgrades | ForEach-Object { "$($_.MajorVersion) to $($_.TargetLevel) (KB$($_.KB))" }) -join ', '
                if ($PSCmdlet.ShouldProcess($resolvedName, "Update $chosenVersions")) {
                    $installActions += [pscustomobject]@{
                        ComputerName = $resolvedName
                        Actions      = $upgrades
                    }
                }
            }
            Write-Progress -Activity $activity -Completed
        }
        # Download and distribute updates if needed
        $downloadedKbs = @()
        $mainPathIsNetwork = $Path[0] | Test-NetworkPath
        foreach ($kbItem in $downloads | Select-Object -Unique -Property KB, Architecture) {
            if ($mainPathIsNetwork) {
                $downloadPath = $Path[0]
            } else {
                $downloadPath = [System.IO.Path]::GetTempPath()
            }
            try {
                $downloadedKbs += [PSCustomObject]@{
                    FileItem     = Save-DbaKbUpdate -Name $kbItem.KB -Path $downloadPath -Architecture $kbItem.Architecture -EnableException
                    KB           = $kbItem.KB
                    Architecture = $kbItem.Architecture
                }
            } catch {
                Stop-Function -Message "Could not download installer for KB$($kbItem.KB)($($kbItem.Architecture)): $_" -Continue
            }
        }
        # if path is not on the network, upload the patch to each remote computer
        if ($downloadedKbs) {
            # find unique KB/Architecture combos without an Installer
            $groupedRequirements = $installActions | ForEach-Object { foreach ($action in $_.Actions | Where-Object { -Not $_.Installer }) { [PSCustomObject]@{ComputerName = $_.ComputerName; KB = $action.KB; Architecture = $action.Architecture } } } | Group-Object -Property KB, Architecture

            # for each such combo, .Installer paths need to be updated and, potentially, files copied
            foreach ($groupKB in $groupedRequirements) {
                $fileItem = ($downloadedKbs | Where-Object { $_.KB -eq $groupKB.Values[0] -and $_.Architecture -eq $groupKB.Values[1] }).FileItem
                $filePath = Join-Path $Path[0] $fileItem.Name
                foreach ($groupItem in $groupKB.Group) {
                    if (-Not $mainPathIsNetwork) {
                        # For each KB, copy the file to the remote (or local) server
                        try {
                            $null = Copy-UncFile -ComputerName $groupItem.ComputerName -Path $fileItem.FullName -Destination $Path[0] -Credential $Credential
                        } catch {
                            Stop-Function -Message "Could not move installer $($fileItem.FullName) to $($Path[0]) on $($groupItem.ComputerName): $_" -Continue
                        }
                    }
                    # Update appropriate action
                    $installAction = $installActions | Where-Object ComputerName -EQ $groupItem.ComputerName
                    $action = $installAction.Actions | Where-Object { $_.KB -eq $groupItem.KB -and $_.Architecture -eq $groupItem.Architecture }
                    $action.Installer = $filePath
                }

            }
            if (-Not $mainPathIsNetwork) {
                # remove temp files
                foreach ($downloadedKb in $downloadedKbs) {
                    $null = Remove-Item $downloadedKb.FileItem.FullName -Force
                }
            }
        }

        # Declare the installation script
        $installScript = {
            $updateSplat = @{
                ComputerName    = $_.ComputerName
                Action          = $_.Actions
                Restart         = $Restart
                Credential      = $Credential
                EnableException = $EnableException
                ExtractPath     = $ExtractPath
                Authentication  = $Authentication
                ArgumentList    = $ArgumentList
            }
            Invoke-DbaAdvancedUpdate @updateSplat
        }
        # check how many computers we are looking at and decide upon parallelism
        if ($installActions.Count -eq 1) {
            $installActions | ForEach-Object -Process $installScript | ForEach-Object -Process $outputHandler
        } elseif ($installActions.Count -ge 2) {
            $installActions | Invoke-Parallel -ImportModules -ImportVariables -ScriptBlock $installScript -Throttle $Throttle | ForEach-Object -Process $outputHandler
        }
    }
}