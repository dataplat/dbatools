$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $knownParameters = 'ComputerName', 'Credential', 'EnableException'
        $paramCount = $knownParameters.Count
        $SupportShouldProcess = $false
        if ($SupportShouldProcess) {
            $defaultParamCount = 13
        } else {
            $defaultParamCount = 11
        }
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys

        it "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            mock Resolve-DbaNetworkName {$null}
            {Get-DbaOperatingSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
        }
    }
}
Describe "Get-DbaOperatingSystem Integration Test" -Tag "IntegrationTests" {
    $result = Get-DbaOperatingSystem -ComputerName $script:instance1

    $props = 'ComputerName', 'Manufacturer', 'Organization',
    'Architecture', 'Build', 'Version', 'InstallDate', 'LastBootTime', 'LocalDateTime',
    'BootDevice', 'TimeZone', 'TimeZoneDaylight', 'TimeZoneStandard', 'TotalVisibleMemory',
    'OSVersion', 'SPVersion', 'PowerShellVersion', 'SystemDevice', 'SystemDrive', 'WindowsDirectory',
    'PagingFileSize', 'FreePhysicalMemory', 'TotalVirtualMemory', 'FreeVirtualMemory', 'ActivePowerPlan',
    'Status', 'Language', 'LanguageId', 'LanguageKeyboardLayoutId', 'LanguageTwoLetter', 'LanguageThreeLetter'
    'LanguageAlias', 'LanguageNative', 'CodeSet', 'CountryCode', 'Locale', 'IsWsfc'

    <#
        FreePhysicalMemory: units = KB
        FreeVirtualMemory: units = KB
        TimeZoneStandard: StandardName from win32_timezone
        TimeZoneDaylight: DaylightName from win32_timezone
        TimeZone: Caption from win32_timezone
       #>
    Context "Validate standard output" {
        foreach ($prop in $props) {
            $p = $result.PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
    }
}