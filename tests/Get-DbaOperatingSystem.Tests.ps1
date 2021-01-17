$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'ComputerName', 'Credential', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            mock Resolve-DbaNetworkName { $null }
            { Get-DbaOperatingSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null } | Should Throw
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