function Get-SqlInstanceUpdate {
    <#
    Originally based on https://github.com/adbertram/PSSqlUpdater
    Internal function. Provides information on the target update version for a specific set of SQL Server instances based on current and target SQL Server levels.
    Component parameter is using the output object of Get-SqlInstanceComponent.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Latest')]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$ComputerName,
        [pscredential]$Credential,
        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [ValidateSet('ServicePack', 'CumulativeUpdate')]
        [string]$Type,
        [object[]]$Component,
        [Parameter(ParameterSetName = 'Number')]
        [int]$ServicePack,
        [Parameter(ParameterSetName = 'Number')]
        [int]$CumulativeUpdate,
        [Parameter(Mandatory, ParameterSetName = 'KB')]
        [ValidateNotNullOrEmpty()]
        [string]$KB,
        [string]$InstanceName,
        [bool]$EnableException = $EnableException,
        [bool]$Continue
    )
    process {

        # check if any type of the update was specified
        if ($PSCmdlet.ParameterSetName -eq 'Number' -and -not ((Test-Bound ServicePack) -or (Test-Bound CumulativeUpdate))) {
            Stop-Function -Message "No update was specified, provide at least one value for either SP/CU"
            return
        }
        $computer = $ComputerName.ComputerName
        $verCount = ($Component | Measure-Object).Count
        $verDesc = ($Component | ForEach-Object { "$($_.Version.NameLevel) ($($_.Version.Build))" }) -join ', '
        Write-Message -Level Debug -Message "Selected $verCount existing SQL Server version(s): $verDesc"

        # Group by version
        $currentVersionGroups = $Component | Group-Object -Property { $_.Version.NameLevel }
        #Check if more than one version is found
        if (($currentVersionGroups | Measure-Object ).Count -gt 1 -and ($CumulativeUpdate -or $ServicePack) -and !$MajorVersion) {
            Stop-Function -Message "Updating multiple different versions of SQL Server to a specific SP/CU is not supported. Please specify a version of SQL Server on $computer that you want to update."
            return
        }
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
        foreach ($currentGroup in $currentVersionGroups) {
            $currentMajorVersion = "SQL" + $currentGroup.Name
            $currentMajorNumber = $currentGroup.Name

            # Use the earliest version in case specifics are needed
            $currentVersion = $currentGroup.Group | Sort-Object -Property { $_.Version.BuildLevel } | Select-Object -ExpandProperty Version -First 1

            #create output object
            $output = [pscustomobject]@{
                ComputerName  = $ComputerName
                MajorVersion  = $currentMajorNumber
                Build         = $currentVersion.Build
                Architecture  = $arch
                TargetVersion = $null
                TargetLevel   = $null
                KB            = $null
                Successful    = $false
                Restarted     = $false
                InstanceName  = $InstanceName
                Installer     = $null
                ExtractPath   = $null
                Notes         = @()
                ExitCode      = $null
                Log           = $null
            }

            # Find target KB number based on provided SP/CU levels or KB numbers
            if ($CumulativeUpdate -gt 0) {
                #Cumulative update is present - installing CU
                if (Test-Bound -Parameter ServicePack) {
                    #Service pack is present - using it as a reference
                    $targetKB = Get-DbaBuildReference -MajorVersion $currentMajorNumber -ServicePack $ServicePack -CumulativeUpdate $CumulativeUpdate
                } else {
                    #Service pack not present - using current SP level
                    $targetSP = $currentVersion.SPLevel
                    $targetKB = Get-DbaBuildReference -MajorVersion $currentMajorNumber -ServicePack $targetSP -CumulativeUpdate $CumulativeUpdate
                }
            } elseif ($ServicePack -gt 0) {
                #Service pack number was passed without CU - installing service pack
                $targetKB = Get-DbaBuildReference -MajorVersion $currentMajorNumber -ServicePack $ServicePack
            } elseif ($KB) {
                $targetKB = Get-DbaBuildReference -KB $KB
                if ($targetKB -and $currentMajorNumber -ne $targetKB.NameLevel) {
                    Write-Message -Level Debug -Message "$($targetKB.NameLevel) is not a target Major version $($currentMajorNumber), skipping"
                    continue
                }
            } else {
                #No parameters = latest patch. Find latest SQL Server build and corresponding SP and CU KBs
                $latestCU = Test-DbaBuild -Build $currentVersion.BuildLevel -MaxBehind '0CU'
                if (!$latestCU.Compliant) {
                    #more recent build is found, get KB number depending on what is the current upgrade $Type
                    $targetKB = Get-DbaBuildReference -Build $latestCU.BuildTarget
                    $targetSP = $targetKB.SPLevel
                    if ($Type -eq 'CumulativeUpdate') {
                        if ($currentVersion.SPLevel -ne $latestCU.SPTarget) {
                            $currentSP = $currentVersion.SPLevel
                            Stop-Function -Message "Current SP version $currentMajorVersion$currentSP is not the latest available. Make sure to upgade to latest SP level before applying latest CU." -Continue
                        }
                        $targetLevel = "$($targetKB.SPLevel)$($targetKB.CULevel)"
                        Write-Message -Level Debug -Message "Found a latest Cumulative Update $targetLevel (KB$($targetKB.KBLevel))"
                    } elseif ($Type -eq 'ServicePack') {
                        $targetKB = Get-DbaBuildReference -MajorVersion $targetKB.NameLevel -ServicePack $targetSP
                        $targetLevel = $targetKB.SPLevel
                        if ($currentVersion.SPLevel -eq $latestCU.SPTarget) {
                            Write-Message -Message "No need to update $currentMajorVersion to $targetLevel - it's already on the latest SP version" -Level Verbose
                            continue
                        }
                        Write-Message -Level Debug -Message "Found a latest Service Pack $targetLevel (KB$($targetKB.KBLevel))"
                    }
                } else {
                    Write-Message -Message "$($currentVersion.Build) on computer [$($computer)] is already the latest available." -Level Warning
                    continue
                }
            }
            if ($targetKB.KBLevel) {
                if ($targetKB.MatchType -ne 'Exact') {
                    Stop-Function -Message "Couldn't find an exact build match with specified parameters while updating $currentMajorVersion" -Continue
                }
                $output.TargetVersion = $targetKB
                $targetLevel = "$($targetKB.SPLevel)$($targetKB.CULevel)"
                $targetKBLevel = $targetKB.KBLevel | Select-Object -First 1
                Write-Message -Level Verbose -Message "Found applicable upgrade for SQL$($targetKB.NameLevel) to $targetLevel (KB$($targetKBLevel))"
                $output.KB = $targetKBLevel
            } else {
                $msg = "Could not find a KB$KB reference for $currentMajorVersion SP $ServicePack CU $CumulativeUpdate"
                $output.Notes += $msg
                $output
                Stop-Function -Message $msg -Continue
            }

            # Compare versions - whether to proceed with the installation
            $needsUpgrade = $false
            foreach ($currentComponent in $currentGroup.Group) {
                $groupVersion = $currentComponent.Version
                #target version is less than requested
                if ($groupVersion.BuildLevel -lt $targetKB.BuildLevel) {
                    $needsUpgrade = $true
                }
                #target version is the same but installation has failed last time
                elseif ($groupVersion.BuildLevel -eq $targetKB.BuildLevel -and $Continue -and $currentComponent.Resume) {
                    $needsUpgrade = $true
                }
            }
            if (!$needsUpgrade) {
                Write-Message -Message "Current $currentMajorVersion version $($currentVersion.BuildLevel) on computer [$($computer)] matches or already higher than target version $($targetKB.BuildLevel)" -Level Verbose
                continue
            }

            $output.TargetLevel = $targetLevel
            $output.Successful = $true
            #Return the object for further processing
            $output
        }
    }
}