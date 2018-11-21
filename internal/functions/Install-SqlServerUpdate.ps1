function Install-SqlServerUpdate {
    <#
    Based on https://github.com/adbertram/PSSqlUpdater
    Invokes installation of SQL Server CU.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$ComputerName,
        [pscredential]$Credential,
        [Parameter(Mandatory)]
        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [ValidateSet('ServicePack', 'CumulativeUpdate')]
        [string]$Type,
        [string[]]$MajorVersion,
        [Parameter(Mandatory, ParameterSetName = 'Number')]
        [int]$ServicePack,
        [Parameter(Mandatory, ParameterSetName = 'Number')]
        [int]$CumulativeUpdate,
        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [ValidateNotNullOrEmpty()]
        [switch]$Latest,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [bool]$Restart,
        [string]$RepositoryPath
    )
    process {
        ## Find the current version on the computer
        $currentVersions = Get-SQLServerVersion -ComputerName $ComputerName
        if (!$currentVersions) {
            Stop-Function -Message "No SQL Server installations found on $ComputerName"
            return
        }
        # Group by version and select the earliest version installed
        $currentVersionGroups = $currentVersions | Group-Object -Property NameLevel | ForEach-Object {
            $_.Group | Sort-Object -Property Build | Select-Object -First 1
        }

        #Check if more than one version is found
        if (($currentVersionGroups | Measure-Object ).Count -gt 1 -and !$Latest -and !$MajorVersion) {
            Stop-Function -Message "Updating multiple versions of SQL Server is only supported with -Latest switch. Please specify a version of SQL Server on $ComputerName that you want to update." -EnableException $true
        }
        if ($MajorVersion) {
            $currentVersionGroups = $currentVersionGroups | Where-Object { $_NameLevel -in $MajorVersion }
        }
        ## Find the architecture of the computer
        $arch = (Get-DbaCmObject -ComputerName $ComputerName -ClassName 'Win32_ComputerSystem').SystemType
        if ($arch -eq 'x64-based PC') {
            $arch = 'x64'
        } else {
            $arch = 'x86'
        }
        # Launch a setup sequence for each version found
        foreach ($currentVersion in $currentVersionGroups) {
            # create a parameter set for Find-SqlServerUpdate
            $params = @{
                'Architecture'     = $arch
                'SqlServerVersion' = $currentVersion.NameLevel
            }
            if ($Latest) {
                #Find latest SQL Server build and corresponding SP and CU KBs
                $latestCU = Test-DbaBuild -Build $currentVersion.Build -MaxBehind '0CU'
                if ($latestCU.CUTarget) {
                    #more recent build is found, get KB number depending on what is the current upgrade $Type
                    $targetKB = Get-DbaBuildReference -Build $latestCU.CUTarget
                    if ($Type -eq 'CumulativeUpdate') {
                        $params.KB = $targetKB.KBLevel
                    } elseif ($Type -eq 'ServicePack') {
                        $targetSP = $targetKB.SPLevel | Where-Object { $_ -ne 'LATEST' } | Select-Object -First 1
                        $spKb = Get-DbaBuildReference -SqlServerVersion $targetKB.NameLevel -ServicePack $targetSP
                        $params.KB = $spKb.KBLevel
                    }
                } else {
                    Write-Message -Message "No latest cumulative updates found for build $($currentVersion.Build) on computer [$($ComputerName)]." -Level Verbose
                    return
                }
            } else {
                # Find target KB number based on provided SP/CU levels
                if ($CumulativeUpdate -gt 0) {
                    #Cumulative update is present - installing CU
                    if ($null -ne $ServicePack) {
                        #Service pack is present - using it as a reference
                        $targetKB = Get-DbaBuildReference -SqlServerVersion $currentVersion.NameLevel -ServicePack $ServicePack -CumulativeUpdate $CumulativeUpdate
                    } else {
                        #Service pack not present - using current SP level
                        $targetSP = $currentVersion.SPLevel | Where-Object { $_ -ne 'LATEST' } | Select-Object -First 1
                        $targetKB = Get-DbaBuildReference -SqlServerVersion $currentVersion.NameLevel -ServicePack $targetSP -CumulativeUpdate $CumulativeUpdate
                    }
                } elseif ($ServicePack -gt 0) {
                    #Service pack number was passed without CU - installing service pack
                    $targetKB = Get-DbaBuildReference -SqlServerVersion $currentVersion.NameLevel -ServicePack $Number
                }
                if ($targetKB) {
                    $params.KB = $targetKB.KBLevel
                } else {
                    Stop-Function -Message "Could not find a KB reference for SP $ServicePack CU $CumulativeUpdate" -EnableException $true
                }
            }
            # Compare versions - whether to proceed with the installation
            if ($currentVersion.BuildLevel -ge $targetKB.BuildLevel) {
                Write-Message -Message "Current version $($currentVersion.BuildLevel) on computer [$($ComputerName)] matches or already higher than target version $($targetKB.BuildLevel)" -Level Verbose
                return
            }
            ## Find the installer to use
            if (-not ($installer = Find-SqlServerUpdate @params)) {
                Stop-Function -Message "Could not find installer for the update [$($params.KB)]" -EnableException $true
            }
            ## Apply patch
            if ($PSCmdlet.ShouldProcess($ComputerName, "Install $Type $($targetKB.KBLevel) ($($installer.Name)) for SQL Server $($currentVersion.BuildLevel)")) {
                $invProgParams = @{
                    ComputerName = $ComputerName
                    Credential   = $Credential
                }
                # Find a temporary folder to extract to
                $spExtractPath = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock { $env:temp } -Raw -ErrorAction Stop
                $spExtractPath = Join-Path $spExtractPath "$($targetKB.KBLevel)_Extract" -ErrorAction Stop
                if ($spExtractPath) {
                    try {
                        # Extract file
                        $null = Invoke-Program @invProgParams -Path $installer.FullName -ArgumentList "/extract:`"$spExtractPath`" /quiet"
                        # Install the patch
                        $null = Invoke-Program @invProgParams -Path "$spExtractPath\setup.exe" -ArgumentList '/quiet /allinstances'
                    } catch {
                        Stop-Function -Message "Upgrade failed" -ErrorRecord $_ -EnableException $true
                    } finally {
                        ## Cleanup temp
                        try {
                            $null = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock { Remove-Item -Recurse -Force -LiteralPath $args[0] -ErrorAction Stop } -Raw -ArgumentLit $spExtractPath
                        } catch {
                            Stop-Function -Message "Failed to cleanup temp folder on computer $ComputerName" -ErrorRecord $_
                        }
                    }
                }
                if ($Restart) {
                    Write-Message "Restarting computer $ComputerName and waiting for it to come back online"
                    try {
                        Restart-Computer -ComputerName $ComputerName -Credential $Credential -Wait -For WinRm -Force -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Failed to restart computer" -ErrorRecord $_ -EnableException $true
                    }
                }
            }
        }
    }
}