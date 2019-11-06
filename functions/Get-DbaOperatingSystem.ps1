function Get-DbaOperatingSystem {
    <#
    .SYNOPSIS
        Gets operating system information from the server.

    .DESCRIPTION
        Gets operating system information from the server and returns as an object.

    .PARAMETER ComputerName
        Target computer(s). If no computer name is specified, the local computer is targeted

    .PARAMETER Credential
        Alternate credential object to use for accessing the target computer(s).

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Server, Management, OperatingSystem
        Author: Shawn Melton (@wsmelton), https://wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaOperatingSystem

    .EXAMPLE
        PS C:\> Get-DbaOperatingSystem

        Returns information about the local computer's operating system

    .EXAMPLE
        PS C:\> Get-DbaOperatingSystem -ComputerName sql2016

        Returns information about the sql2016's operating system

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> 'sql2016', 'sql2017' | Get-DbaOperatingSystem -Credential $wincred

        Returns information about the sql2016 and sql2017 operating systems using alternative Windows credentials

    .EXAMPLE
        PS C:\> Get-Content .\servers.txt | Get-DbaOperatingSystem

        Returns information about all the servers operating system that are stored in the file. Every line in the file can only contain one hostname for a server.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $ComputerName) {
            Write-Message -Level Verbose -Message "Connecting to $computer"

            $server = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential

            $computerResolved = $server.FullComputerName
            Write-Message -Level Verbose -Message "Resolved $computerResolved"

            if (!$computerResolved) {
                Write-Message -Level Warning -Message "Unable to resolve hostname of $computer. Skipping."
                continue
            }

            try {
                $TestWS = Test-WSMan -ComputerName $computerResolved -ErrorAction SilentlyContinue
            } catch {
                Write-Message -Level Warning -Message "Remoting not availablle on $computer. Skipping checks"
                $TestWS = $null
            }

            $splatDbaCmObject = @{
                ComputerName    = $computerResolved
                EnableException = $true
            }
            if (Test-Bound "Credential") {
                $splatDbaCmObject["Credential"] = $Credential
            }
            if ($TestWS) {
                try {
                    $psVersion = Invoke-Command2 -ComputerName $computerResolved -Credential $Credential -ScriptBlock { $PSVersionTable.PSVersion }
                    $PowerShellVersion = "$($psVersion.Major).$($psVersion.Minor)"
                } catch {
                    Write-Message -Level Warning -Message "PowerShell Version information not available on $computer."
                    $PowerShellVersion = 'Unavailable'
                }
            } else {
                $PowerShellVersion = 'Unknown'
            }

            try {
                $os = Get-DbaCmObject @splatDbaCmObject -ClassName Win32_OperatingSystem
            } catch {
                Stop-Function -Message "Failure collecting OS information on $computer" -Target $computer -ErrorRecord $_
                return
            }

            try {
                $tz = Get-DbaCmObject @splatDbaCmObject -ClassName Win32_TimeZone
            } catch {
                Stop-Function -Message "Failure collecting TimeZone information on $computer" -Target $computer -ErrorRecord $_
                return
            }

            try {
                $powerPlan = Get-DbaCmObject @splatDbaCmObject -ClassName Win32_PowerPlan -Namespace "root\cimv2\power" | Select-Object ElementName, InstanceId, IsActive
            } catch {
                Write-Message -Level Warning -Message "Power plan information not available on $computer."
                $powerPlan = $null
            }

            if ($powerPlan) {
                $activePowerPlan = ($powerPlan | Where-Object IsActive).ElementName -join ','
            } else {
                $activePowerPlan = 'Not Avaliable'
            }

            $language = Get-Language $os.OSLanguage

            try {
                $ss = Get-DbaCmObject @splatDbaCmObject -Class Win32_SystemServices
                if ($ss | Select-Object PartComponent | Where-Object { $_ -like "*ClusSvc*" }) {
                    $IsWsfc = $true
                } else {
                    $IsWsfc = $false
                }
            } catch {
                Write-Message -Level Warning -Message "Unable to determine Cluster State of $computer."
                $IsWsfc = $null
            }

            [PSCustomObject]@{
                ComputerName             = $computerResolved
                Manufacturer             = $os.Manufacturer
                Organization             = $os.Organization
                Architecture             = $os.OSArchitecture
                Version                  = $os.Version
                Build                    = $os.BuildNumber
                OSVersion                = $os.caption
                SPVersion                = $os.servicepackmajorversion
                InstallDate              = [DbaDateTime]$os.InstallDate
                LastBootTime             = [DbaDateTime]$os.LastBootUpTime
                LocalDateTime            = [DbaDateTime]$os.LocalDateTime
                PowerShellVersion        = $PowerShellVersion
                TimeZone                 = $tz.Caption
                TimeZoneStandard         = $tz.StandardName
                TimeZoneDaylight         = $tz.DaylightName
                BootDevice               = $os.BootDevice
                SystemDevice             = $os.SystemDevice
                SystemDrive              = $os.SystemDrive
                WindowsDirectory         = $os.WindowsDirectory
                PagingFileSize           = $os.SizeStoredInPagingFiles
                TotalVisibleMemory       = [DbaSize]($os.TotalVisibleMemorySize * 1024)
                FreePhysicalMemory       = [DbaSize]($os.FreePhysicalMemory * 1024)
                TotalVirtualMemory       = [DbaSize]($os.TotalVirtualMemorySize * 1024)
                FreeVirtualMemory        = [DbaSize]($os.FreeVirtualMemory * 1024)
                ActivePowerPlan          = $activePowerPlan
                Status                   = $os.Status
                Language                 = $language.Name
                LanguageId               = $language.LCID
                LanguageKeyboardLayoutId = $language.KeyboardLayoutId
                LanguageTwoLetter        = $language.TwoLetterISOLanguageName
                LanguageThreeLetter      = $language.ThreeLetterISOLanguageName
                LanguageAlias            = $language.DisplayName
                LanguageNative           = $language.NativeName
                CodeSet                  = $os.CodeSet
                CountryCode              = $os.CountryCode
                Locale                   = $os.Locale
                IsWsfc                   = $IsWsfc
            } | Select-DefaultView -Property ComputerName, Manufacturer, Organization, Architecture, Version, OSVersion, LastBootTime, LocalDateTime, PowerShellVersion, TimeZone, TotalVisibleMemory, ActivePowerPlan, LanguageNative
        }
    }
}