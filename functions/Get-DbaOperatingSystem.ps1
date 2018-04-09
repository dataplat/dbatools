#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
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
            Tags: ServerInfo, OperatingSystem
            Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

            Website: https: //dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaOperatingSystem

        .EXAMPLE
            Get-DbaOperatingSystem

            Returns information about the local computer's operating system

        .EXAMPLE
            Get-DbaOperatingSystem -ComputerName sql2016

            Returns information about the sql2016's operating system
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias('Silent')]
        [switch]$EnableException
    )
    process {
        foreach ($computer in $ComputerName) {
            Write-Message -Level Verbose -Message "Attempting to connect to $computer"
            $server = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential

            $computerResolved = $server.FullComputerName

            if (!$computerResolved) {
                Write-Message -Level Warning -Message "Unable to resolve hostname of $computer. Skipping."
                continue
            }

            try {
                $psVersion = Invoke-Command2 -ComputerName $computerResolved -Credential $Credential -ScriptBlock { $PSVersionTable.PSVersion }
            }
            catch {
                Stop-Function -Message "Failure collecting PowerShell version on $computer" -Target $computer -ErrorRecord $_
                return
            }

            try {
                if (Test-Bound "Credential") {
                    $os = Get-DbaCmObject -ClassName Win32_OperatingSystem -ComputerName $computerResolved -Credential $Credential -EnableException
                }
                else {
                    $os = Get-DbaCmObject -ClassName Win32_OperatingSystem -ComputerName $computerResolved -EnableException
                }
            }
            catch {
                Stop-Function -Message "Failure collecting OS information on $computer" -Target $computer -ErrorRecord $_
                return
            }

            try {
                if (Test-Bound "Credential") {
                    $tz = Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $computerResolved -Credential $Credential -EnableException
                }
                else {
                    $tz = Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $computerResolved -EnableException
                }
            }
            catch {
                Stop-Function -Message "Failure collecting TimeZone information on $computer" -Target $computer -ErrorRecord $_
                return
            }

            try {
                if (Test-Bound "Credential") {
                    $powerPlan = Get-DbaCmObject -ClassName Win32_PowerPlan -Namespace "root\cimv2\power" -ComputerName $computerResolved -Credential $Credential -EnableException | Select-Object ElementName, InstanceId, IsActive
                }
                else {
                    $powerPlan = Get-DbaCmObject -ClassName Win32_PowerPlan -Namespace "root\cimv2\power" -ComputerName $computerResolved -EnableException | Select-Object ElementName, InstanceId, IsActive
                }
            }
            catch {
                Stop-Function -Message "Failure collecting PowerPlan information on $computer" -Target $computer -ErrorRecord $_
                return
            }

            $activePowerPlan = ($powerPlan | Where-Object IsActive).ElementName -join ','
            $language = Get-Language $os.OSLanguage

            [PSCustomObject]@{
                ComputerName             = $computerResolved
                Manufacturer             = $os.Manufacturer
                Organization             = $os.Organization
                Architecture             = $os.OSArchitecture
                Version                  = $os.Version
                Build                    = $os.BuildNumber
                Caption                  = $os.Caption
                InstallDate              = [DbaDateTime]$os.InstallDate
                LastBootTime             = [DbaDateTime]$os.LastBootUpTime
                LocalDateTime            = [DbaDateTime]$os.LocalDateTime
                PowerShellVersion        = "$($psVersion.Major).$($psVersion.Minor)"
                TimeZone                 = $tz.Caption
                TimeZoneStandard         = $tz.StandardName
                TimeZoneDaylight         = $tz.DaylightName
                BootDevice               = $os.BootDevice
                TotalVisibleMemory       = [DbaSize]($os.TotalVisibleMemorySize * 1024)
                FreePhysicalMemory       = [DbaSize]($os.FreePhysicalMemory * 1024)
                TotalVirtualMemory       = [DbaSize]($os.TotalVirtualMemorySize * 1024)
                FreeVirtualMemory        = [DbaSize]($os.FreeVirtualMemory * 1024)
                ActivePowerPlan          = $activePowerPlan
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
            } | Select-DefaultView -Property ComputerName, Manufacturer, Organization, Architecture, Version, Caption, LastBootTime, LocalDateTime, PowerShellVersion, TimeZone, TotalVisibleMemory, ActivePowerPlan, LanguageNative
        }
    }
}