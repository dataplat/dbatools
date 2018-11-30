function Install-SqlServerUpdate {
    <#
    Originally based on https://github.com/adbertram/PSSqlUpdater
    Internal function. Invokes installation of a single SQL Server KB based on provided parameters.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Latest')]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$ComputerName,
        [pscredential]$Credential,
        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [ValidateSet('ServicePack', 'CumulativeUpdate')]
        [string]$Type,
        [string[]]$MajorVersion,
        [Parameter(ParameterSetName = 'Number')]
        [int]$ServicePack,
        [Parameter(ParameterSetName = 'Number')]
        [int]$CumulativeUpdate,
        [Parameter(Mandatory, ParameterSetName = 'KB')]
        [ValidateNotNullOrEmpty()]
        [string]$KB,
        [bool]$Restart,
        [string[]]$Path,
        [bool]$EnableException = $EnableException
    )
    process {
        # check if any type of the update was specified
        if ($PSCmdlet.ParameterSetName -eq 'Number' -and -not ((Test-Bound ServicePack) -or (Test-Bound CumulativeUpdate))) {
            Stop-Function -Message "No update was specified, provide at least one value for either SP/CU"
            return
        }
        $computer = $ComputerName.ComputerName
        $activity = "Updating SQL instance builds on $computer"

        ## Find the current version on the computer
        Write-ProgressHelper -ExcludePercent -Activity $activity -StepNumber 0 -Message "Gathering all SQL Server instance versions"
        $currentVersions = Get-SQLServerVersion -ComputerName $computer
        if (!$currentVersions) {
            Stop-Function -Message "No SQL Server installations found on $computer"
            return
        }
        # Group by version and select the earliest version installed
        $currentVersionGroups = $currentVersions | Group-Object -Property NameLevel | ForEach-Object {
            $_.Group | Sort-Object -Property Build | Select-Object -First 1
        }
        $verCount = ($currentVersionGroups | Measure-Object).Count
        $verDesc = ($currentVersionGroups | Foreach-Object { "$($_.NameLevel) ($($_.Build))" }) -join ', '
        Write-Message -Level Debug -Message "Found $verCount existing SQL Server version(s): $verDesc"
        #Check if more than one version is found
        if (($currentVersionGroups | Measure-Object ).Count -gt 1 -and ($CumulativeUpdate -or $ServicePack) -and !$MajorVersion) {
            Stop-Function -Message "Updating multiple different versions of SQL Server to a specific SP/CU is not supported. Please specify a version of SQL Server on $computer that you want to update."
            return
        }
        if ($MajorVersion) {
            $currentVersionGroups = $currentVersionGroups | Where-Object { $_.NameLevel -in $MajorVersion }
        }
        $verCount = ($currentVersionGroups | Measure-Object).Count
        $verDesc = ($currentVersionGroups | Foreach-Object { "$($_.NameLevel) ($($_.Build))" }) -join ', '
        Write-Message -Level Verbose -Message "Found $verCount applicable SQL Server version(s): $verDesc"
        ## Find the architecture of the computer
        if ($arch = (Get-DbaCmObject -ComputerName $computer -ClassName 'Win32_ComputerSystem').SystemType) {
            if ($arch -eq 'x64-based PC') {
                $arch = 'x64'
            } else {
                $arch = 'x86'
            }
        } else {
            Write-Message -Level Warning -Message "Failed to determine the arch of $computer, using x64 by default"
            $arch = 'x64'
        }
        $targetLevel = ''
        # Launch a setup sequence for each version found
        foreach ($currentVersion in $currentVersionGroups) {
            $stepCounter = 0
            $currentMajorVersion = "SQL" + $currentVersion.NameLevel

            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Parsing versions"
            # create a parameter set for Find-SqlServerUpdate
            $kbLookupParams = @{
                Architecture = $arch
                MajorVersion = $currentVersion.NameLevel
                Path         = $Path
            }
            # Find target KB number based on provided SP/CU levels or KB numbers
            if ($CumulativeUpdate -gt 0) {
                #Cumulative update is present - installing CU
                if (Test-Bound -Parameter ServicePack) {
                    #Service pack is present - using it as a reference
                    $targetKB = Get-DbaBuildReference -MajorVersion $currentVersion.NameLevel -ServicePack $ServicePack -CumulativeUpdate $CumulativeUpdate
                } else {
                    #Service pack not present - using current SP level
                    $targetSP = $currentVersion.SPLevel | Where-Object { $_ -ne 'LATEST' } | Select-Object -First 1
                    $targetKB = Get-DbaBuildReference -MajorVersion $currentVersion.NameLevel -ServicePack $targetSP -CumulativeUpdate $CumulativeUpdate
                }
            } elseif ($ServicePack -gt 0) {
                #Service pack number was passed without CU - installing service pack
                $targetKB = Get-DbaBuildReference -MajorVersion $currentVersion.NameLevel -ServicePack $ServicePack
            } elseif ($KB) {
                $targetKB = Get-DbaBuildReference -KB $KB
                if ($targetKB -and $currentVersion.NameLevel -ne $targetKB.NameLevel) {
                    Write-Message -Level Debug -Message "$($targetKB.NameLevel) is not a target Major version $($currentVersion.NameLevel), skipping"
                    continue
                }
            } else {
                #No parameters = latest patch. Find latest SQL Server build and corresponding SP and CU KBs
                $latestCU = Test-DbaBuild -Build $currentVersion.Build -MaxBehind '0CU'
                if (!$latestCU.Compliant) {
                    #more recent build is found, get KB number depending on what is the current upgrade $Type
                    $targetKB = Get-DbaBuildReference -Build $latestCU.BuildTarget
                    $targetSP = $targetKB.SPLevel | Where-Object { $_ -ne 'LATEST' } | Select-Object -First 1
                    if ($Type -eq 'CumulativeUpdate') {
                        if ($currentVersion.SPLevel -notcontains 'LATEST') {
                            $currentSP = $currentVersion.SPLevel | Where-Object { $_ -ne 'LATEST' } | Select-Object -First 1
                            Stop-Function -Message "Current SP version $currentMajorVersion$currentSP is not the latest available. Make sure to upgade to latest SP level before applying latest CU." -Continue
                        }
                        $targetLevel = "$($targetKB.SPLevel | Where-Object { $_ -ne 'LATEST' })$($targetKB.CULevel)"
                        Write-Message -Level Debug -Message "Found a latest Cumulative Update $targetLevel (KB$($targetKB.KBLevel))"
                    } elseif ($Type -eq 'ServicePack') {
                        $targetKB = Get-DbaBuildReference -MajorVersion $targetKB.NameLevel -ServicePack $targetSP
                        $targetLevel = $targetKB.SPLevel | Where-Object { $_ -ne 'LATEST' }
                        Write-Message -Level Debug -Message "Found a latest Service Pack $targetLevel (KB$($targetKB.KBLevel))"
                    }
                } else {
                    Write-Message -Message "$($currentVersion.Build) on computer [$($computer)] is already the latest available." -Level Verbose
                    continue
                }
            }
            if ($targetKB.KBLevel) {
                if ($targetKB.MatchType -ne 'Exact') {
                    Stop-Function -Message "Couldn't find an exact build match with specified parameters while updating $currentMajorVersion" -Continue
                }
                $targetLevel = "$($targetKB.SPLevel | Where-Object { $_ -ne 'LATEST' })$($targetKB.CULevel)"
                $targetKBLevel = $targetKB.KBLevel | Select-Object -First 1
                Write-Message -Level Verbose -Message "Upgrading SQL$($targetKB.NameLevel) to $targetLevel (KB$($targetKBLevel))"
                $kbLookupParams.KB = $targetKBLevel
            } else {
                Stop-Function -Message "Could not find a KB$KB reference for $currentMajorVersion SP $ServicePack CU $CumulativeUpdate" -Continue
            }

            # Compare versions - whether to proceed with the installation
            if ($currentVersion.BuildLevel -ge $targetKB.BuildLevel) {
                Write-Message -Message "Current $currentMajorVersion version $($currentVersion.BuildLevel) on computer [$($computer)] matches or already higher than target version $($targetKB.BuildLevel)" -Level Verbose
                continue
            }
            ## Find the installer to use
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Searching for update binaries"

            $installer = Find-SqlServerUpdate @kbLookupParams
            if (!$installer) {
                Stop-Function -Message "Could not find installer for the $currentMajorVersion update KB$($kbLookupParams.KB)" -Continue
            }
            ## Apply patch
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Installing $targetLevel KB$($targetKB.KBLevel) ($($installer.Name)) for $currentMajorVersion ($($currentVersion.BuildLevel))"
            if ($PSCmdlet.ShouldProcess($computer, "Install $targetLevel KB$($targetKB.KBLevel) ($($installer.Name)) for $currentMajorVersion ($($currentVersion.BuildLevel))")) {
                $invProgParams = @{
                    ComputerName = $computer
                    Credential   = $Credential
                    ErrorAction  = 'Stop'
                }
                # Find a temporary folder to extract to - the drive that has most free space
                $chosenDrive = (Get-DbaDiskSpace -ComputerName $computer -Credential $Credential | Sort-Object -Property Free -Descending | Select-Object -First 1).Name
                if (!$chosenDrive) {
                    # Fall back to the system drive
                    $chosenDrive = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { $env:SystemDrive } -Raw -ErrorAction Stop
                }
                $spExtractPath = $chosenDrive.TrimEnd('\') + "\dbatools_KB$($targetKB.KBLevel)_Extract"
                if ($spExtractPath) {
                    try {
                        # Extract file
                        Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Extracting $installer to $spExtractPath"
                        Write-Message -Level Verbose -Message "Extracting $installer to $spExtractPath"
                        $null = Invoke-Program @invProgParams -Path $installer.FullName -ArgumentList "/x`:`"$spExtractPath`" /quiet"
                        # Install the patch
                        Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Now installing update from $spExtractPath"
                        Write-Message -Level Verbose -Message "Starting installation from $spExtractPath"
                        $log = Invoke-Program @invProgParams -Path "$spExtractPath\setup.exe" -ArgumentList '/quiet /allinstances /IAcceptSQLServerLicenseTerms' -WorkingDirectory $spExtractPath
                        $success = $true
                    } catch {
                        Stop-Function -Message "Upgrade failed" -ErrorRecord $_
                        return
                    } finally {
                        ## Cleanup temp
                        try {
                            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Removing temporary files"
                            $null = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock {
                                if ($args[0] -like '*\dbatools_KB*_Extract' -and (Test-Path $args[0])) {
                                    Remove-Item -Recurse -Force -LiteralPath $args[0] -ErrorAction Stop
                                }
                            } -Raw -ArgumentList $spExtractPath -ErrorAction Stop
                        } catch {
                            Write-Message -Level Warning -Message "Failed to cleanup temp folder on computer $computer`: $($_.Exception.Message) "
                        }
                    }
                }
                if ($Restart) {
                    Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Restarting computer $computer and waiting for it to come back online"
                    Write-Message -Level Verbose "Restarting computer $computer and waiting for it to come back online"
                    try {
                        $restartParams = @{
                            ComputerName = $computer
                        }
                        if ($Credential) { $restartParams += @{ Credential = $Credential }
                        }
                        $null = Restart-Computer @restartParams -Wait -For WinRm -Force -ErrorAction Stop
                        $restarted = $true
                    } catch {
                        Stop-Function -Message "Failed to restart computer" -ErrorRecord $_
                        return
                    }
                } else {
                    $message = "Restart is required for computer $computer to finish the installation of $currentMajorVersion$targetLevel"
                }
            } else {
                $message = 'The installation was not performed - running in WhatIf mode'
                $success = $true
            }
            # return resulting object. This function throws, so all results here are expected to be shown only in a positive light
            [psobject]@{
                ComputerName = $ComputerName
                MajorVersion = $kbLookupParams.MajorVersion
                TargetLevel  = $targetLevel
                KB           = $kbLookupParams.KB
                Successful   = [bool]$success
                Restarted    = [bool]$restarted
                Installer    = $installer.FullName
                ExtractPath  = $spExtractPath
                Message      = $message
                Log          = $log
            }
            if (-not $restarted) {
                Write-Message -Level Verbose "No more installations for other versions on $computer - restart is pending"
                return
            }
        }
    }
}