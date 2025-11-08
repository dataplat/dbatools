function Update-DbaInstance {
    <#
    .SYNOPSIS
        Installs SQL Server Service Packs and Cumulative Updates across local and remote instances automatically.

    .DESCRIPTION
        Automates the complete process of applying SQL Server patches to eliminate the manual effort of updating multiple instances. This function handles the entire patching workflow from detection through installation, replacing the tedious process of manually downloading, transferring, and applying updates across your SQL Server environment.

        The patching process includes:
        * Discovering all SQL Server instances on target computers via registry scanning
        * Validating current versions against target update requirements
        * Locating appropriate KB installers in your patch repository
        * Establishing secure remote connections using CredSSP or other protocols
        * Extracting and executing patches from temporary directories
        * Managing restarts and chaining multiple updates when needed
        * Cleaning up temporary files after installation
        * Processing multiple computers in parallel for faster deployment

        This replaces the manual process of RDP'ing to each server, copying patch files, running installers, and tracking which systems need which updates. Perfect for monthly patching cycles, emergency security updates, or bringing development environments up to production patch levels.

        The impact of this function is set to High. Use -Confirm:$false to suppress interactive prompts for automated deployments.

        For CredSSP authentication, the function automatically configures PowerShell remoting when credentials are provided. This can be disabled by setting dbatools configuration 'commands.initialize-credssp.bypass' to $true. CredSSP configuration requires running from an elevated PowerShell session.

        Always backup databases and configurations before applying any SQL Server updates.

    .PARAMETER ComputerName
        Target computer with SQL instance or instances.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if update Repository is located on a network folder.

        Authentication will default to CredSSP if -Credential is used.
        For CredSSP see also additional information in DESCRIPTION.

    .PARAMETER Type
        Specifies which types of SQL Server updates to install: All, ServicePack, or CumulativeUpdate.
        Use this when you want to apply only specific update types, such as installing only Service Packs during maintenance windows.
        Defaults to All, which installs both Service Packs and Cumulative Updates in proper sequence.

    .PARAMETER KB
        Installs a specific Knowledge Base update or list of updates by KB number.
        Use this when you need to apply a particular security patch or bug fix identified by Microsoft.
        Accepts formats like 123456 or KB123456, and supports multiple KB numbers for batch installations.

    .PARAMETER Version
        Defines the target SQL Server version level to reach using pattern <MajorVersion><SPX><CUX>.
        Use this to standardize SQL Server instances to a specific patch level across your environment.
        Examples: 2008R2SP1 (SQL 2008R2 to SP1), 2016CU3 (SQL 2016 to CU3), SP1CU7 (all versions to SP1 then CU7).
        When omitted, installs the latest available patches for each detected SQL Server version.

    .PARAMETER Path
        Specifies the folder path containing SQL Server update files for installation.
        Use this to point to your centralized patch repository where you store downloaded SQL Server updates.
        Files must follow Microsoft's naming pattern (SQLServer####*-KB###-*x##*.exe) and path must be accessible from both client and target servers.
        Configure a default path with Set-DbatoolsConfig -Name Path.SQLServerUpdates to avoid specifying this repeatedly.

    .PARAMETER Restart
        Automatically restarts the server after successful patch installation and waits for it to come back online.
        Required for chaining multiple updates since SQL Server patches mandate a restart between installations.
        Use this during planned maintenance windows when you can afford server downtime for complete patch sequences.

    .PARAMETER Continue
        Resumes a previously failed SQL Server update installation from where it left off.
        Use this when a patch installation was interrupted due to network issues, timeouts, or other temporary failures.
        Without this switch, the function will abort and clean up any failed installation attempts.

    .PARAMETER Authentication
        Specifies the PowerShell remoting authentication method for connecting to remote SQL Server hosts.
        Defaults to CredSSP when using -Credential to avoid double-hop authentication issues with network patch repositories.
        Use CredSSP when your patch files are stored on network shares that require credential delegation to remote servers.

    .PARAMETER UseSSL
        Enables SSL encryption for PowerShell remoting connections to target servers.
        Use this when remote servers are configured to only accept encrypted WinRM connections (typically on port 5986).
        Defaults to the value configured in PSRemoting.PsSession.UseSSL configuration setting (false if not configured).
        Explicitly specifying this parameter overrides the configuration default.

    .PARAMETER Port
        Specifies the WinRM port to use for PowerShell remoting connections.
        Common values: 5985 (standard HTTP), 5986 (HTTPS/SSL).
        Use this when remote servers have WinRM configured on non-standard ports or when using SSL.
        Defaults to the value configured in PSRemoting.PsSession.Port configuration setting (standard ports if not configured).
        Explicitly specifying this parameter overrides the configuration default.

    .PARAMETER InstanceName
        Limits patching to a specific named SQL Server instance on the target computer.
        Use this when you have multiple SQL instances and need to patch only one, such as updating a development instance while leaving production untouched.
        Omit this parameter to update all SQL Server instances found on the target computers.

    .PARAMETER Throttle
        Controls the maximum number of servers that can be updated simultaneously during parallel operations.
        Use a lower value (5-10) for large production environments to limit network load and system resource usage.
        Defaults to 50, but consider your network bandwidth and the number of concurrent patch installations your infrastructure can handle.

    .PARAMETER ArgumentList
        Passes additional command-line parameters to the SQL Server patch installer executable.
        Use this to customize installation behavior such as skipping specific validation rules or running in quiet mode.
        Common examples include /SkipRules=RebootRequiredCheck to bypass reboot checks, or /Q for silent installation.

    .PARAMETER Download
        Automatically downloads missing SQL Server update files from Microsoft when they're not found in your patch repository.
        Use this to ensure patches are available during installation without manually downloading them beforehand.
        Files download to your local temp folder first, then get distributed to target servers or directly to network paths.

    .PARAMETER NoPendingRenameCheck
        Bypasses the check for pending file rename operations that typically require a reboot before patching.
        Use this in environments where you're confident no pending renames exist or when system monitoring tools show false positives.
        Exercise caution as installing patches with pending renames can lead to installation failures.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ExtractPath
        Specifies the directory on target servers where SQL Server patch files will be extracted before installation.
        Use this to control where temporary installation files are placed, especially on servers with limited C: drive space.
        Defaults to system temporary directory if not specified, but consider using a dedicated drive with sufficient space.

    .LINK
        https://dbatools.io/Update-DbaInstance

    .NOTES
        Tags: Deployment, Install, Patching, Update
        Author: Kirill Kravtsov (@nvarscar), nvarscar.wordpress.com

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

        Updates all applicable SQL Server installations on SQL1 and SQL2 with the most recent patch (that has at least a "CU" flag).
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

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName "db01.internal.local" -Credential $cred -UseSSL -Port 5986 -Path "\\fs01.internal.local\SQL2022_Patch\CU13"

        Updates SQL Server on db01.internal.local using SSL-encrypted WinRM connection on port 5986.
        Requires the remote server to be configured for HTTPS WinRM (typically port 5986).
        Credentials are provided to access both the remote server and the network share containing patch files.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Version')]
    Param (
        [parameter(ValueFromPipeline, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
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
        [string]$Authentication = @('Credssp', 'Default')[$null -eq $Credential],
        [switch]$UseSSL = (Get-DbatoolsConfigValue -FullName "PSRemoting.PsSession.UseSSL" -Fallback $false),
        [nullable[int]]$Port = (Get-DbatoolsConfigValue -FullName "PSRemoting.PsSession.Port" -Fallback $null),
        [string]$ExtractPath,
        [string[]]$ArgumentList,
        [switch]$Download,
        [switch]$NoPendingRenameCheck = (Get-DbatoolsConfigValue -Name 'OS.PendingRename' -Fallback $false),
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
        if ($Path) {
            $Path = $Path.TrimEnd("/\")
        }
        #Resolve all the provided names
        $resolvedComputers = @()
        $pathIsNetwork = $Path | Test-NetworkPath
        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            if (-not $computer.IsLocalHost -and -not $notifiedCredentials -and -not $Credential -and $pathIsNetwork) {
                Write-Message -Level Warning -Message "Explicit -Credential might be required when running against remote hosts and -Path is a network folder"
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
                $splatPendingReboot = @{
                    ComputerName    = $resolvedName
                    Credential      = $Credential
                    NoPendingRename = $NoPendingRenameCheck
                }
                $restartNeeded = Test-PendingReboot @splatPendingReboot
            } catch {
                Stop-Function -Message "Failed to get reboot status from $resolvedName" -Continue -ErrorRecord $_
            }
            if ($restartNeeded -and (-not $Restart -or ([DbaInstanceParameter]$resolvedName).IsLocalHost)) {
                #Exit the actions loop altogether - nothing can be installed here anyways
                Stop-Function -Message "$resolvedName is pending a reboot. Reboot the computer before proceeding." -Continue
            }
            # test connection
            if ($Credential -and -not ([DbaInstanceParameter]$resolvedName).IsLocalHost) {
                $totalSteps += 1
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Testing $Authentication protocol"
                Write-Message -Level Verbose -Message "Attempting to test $Authentication protocol for remote connections"
                try {
                    $splatRemoteTest = @{
                        ComputerName   = $resolvedName
                        Credential     = $Credential
                        Authentication = $Authentication
                        ScriptBlock    = { $true }
                        Raw            = $true
                        UseSSL         = $UseSSL
                    }
                    if (($null -ne $Port) -and ($Port -gt 0)) {
                        $splatRemoteTest.Port = $Port
                    }
                    $connectSuccess = Invoke-Command2 @splatRemoteTest
                } catch {
                    $connectSuccess = $false
                }
                # if we use CredSSP, we might be able to configure it
                if (-not $connectSuccess -and $Authentication -eq 'Credssp') {
                    $totalSteps += 1
                    Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Configuring CredSSP protocol"
                    Write-Message -Level Verbose -Message "Attempting to configure CredSSP for remote connections"
                    try {
                        Initialize-CredSSP -ComputerName $resolvedName -Credential $Credential -EnableException $true
                        $splatRemoteTestCredSSP = @{
                            ComputerName   = $resolvedName
                            Credential     = $Credential
                            Authentication = $Authentication
                            ScriptBlock    = { $true }
                            Raw            = $true
                            UseSSL         = $UseSSL
                        }
                        if (($null -ne $Port) -and ($Port -gt 0)) {
                            $splatRemoteTestCredSSP.Port = $Port
                        }
                        $connectSuccess = Invoke-Command2 @splatRemoteTestCredSSP
                    } catch {
                        $connectSuccess = $false
                        # tell the user why we could not configure CredSSP
                        Write-Message -Level Warning -Message $_
                    }
                }
                # in case we are still not successful, ask the user to use unsecure protocol once
                if (-not $connectSuccess -and -not $notifiedUnsecure) {
                    if ($PSCmdlet.ShouldProcess($resolvedName, "Primary protocol ($Authentication) failed, sending credentials via potentially unsecure protocol")) {
                        $notifiedUnsecure = $true
                    } else {
                        Stop-Function -Message "Failed to connect to $resolvedName through $Authentication protocol. No actions will be performed on that computer." -Continue -ContinueLabel computers
                    }
                }
            }
            $upgrades = @()
            :actions foreach ($actionItem in $actions) {
                # Clone action to use as a splat
                $currentAction = $actionItem.Clone()
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

                        # Check for SQL 2016-2019 ML Services CAB files
                        # SQL 2022+ changed architecture - runtimes installed separately
                        if ($detail.MajorVersion -in "2016", "2017", "2019") {
                            $hasMLServices = Test-DbaMLServicesInstalled -Component $selectedComponents
                            if ($hasMLServices) {
                                Write-Message -Level Verbose -Message "SQL Server $($detail.MajorVersion) with ML Services detected, searching for CAB files"
                                $installerDir = Split-Path $installer.FullName
                                $splatCabSearch = @{
                                    Path           = $installerDir
                                    ComputerName   = $resolvedName
                                    Credential     = $Credential
                                    Authentication = $Authentication
                                }
                                try {
                                    $cabFiles = Find-DbaMLServicesCabFile @splatCabSearch
                                    if ($cabFiles) {
                                        $detail | Add-Member -NotePropertyName "MLServicesCabFiles" -NotePropertyValue $cabFiles -Force
                                        Write-Message -Level Verbose -Message "Found $($cabFiles.Count) ML Services CAB file(s) for KB$($detail.KB)"
                                    } else {
                                        $detail.Notes += "ML Services detected but no CAB files found. If you do not have internet access, the update may fail. Place R/Python CAB files (SRO_*.cab, SRS_*.cab, SPO_*.cab, SPS_*.cab) in the same directory as the KB installer."
                                        Write-Message -Level Warning -Message "ML Services CAB files not found for SQL Server $($detail.MajorVersion) KB$($detail.KB). The installer may download them automatically if internet access is available, or the update may fail."
                                    }
                                } catch {
                                    Write-Message -Level Warning -Message "Failed to search for ML Services CAB files: $_"
                                    $detail.Notes += "Could not search for ML Services CAB files. The update may fail if R/Python components need updating and internet access is not available."
                                }
                            }
                        }
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
                    $installActions += [PSCustomObject]@{
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
                ComputerName         = $_.ComputerName
                Action               = $_.Actions
                Restart              = $Restart
                Credential           = $Credential
                EnableException      = $EnableException
                ExtractPath          = $ExtractPath
                Authentication       = $Authentication
                ArgumentList         = $ArgumentList
                NoPendingRenameCheck = $NoPendingRenameCheck
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