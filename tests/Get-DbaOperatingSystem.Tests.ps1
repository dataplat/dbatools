param($ModuleName = 'dbatools')

Describe "Get-DbaOperatingSystem" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaOperatingSystem
        }

        $params = @(
            "ComputerName",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName {$null}
            { Get-DbaOperatingSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null } | Should -Throw
        }
    }

    Context "Get-DbaOperatingSystem Integration Test" -Tag "IntegrationTests" {
        BeforeAll {
            $result = Get-DbaOperatingSystem -ComputerName $global:instance1

            $props = 'ComputerName', 'Manufacturer', 'Organization',
            'Architecture', 'Build', 'Version', 'InstallDate', 'LastBootTime', 'LocalDateTime',
            'BootDevice', 'TimeZone', 'TimeZoneDaylight', 'TimeZoneStandard', 'TotalVisibleMemory',
            'OSVersion', 'SPVersion', 'PowerShellVersion', 'SystemDevice', 'SystemDrive', 'WindowsDirectory',
            'PagingFileSize', 'FreePhysicalMemory', 'TotalVirtualMemory', 'FreeVirtualMemory', 'ActivePowerPlan',
            'Status', 'Language', 'LanguageId', 'LanguageKeyboardLayoutId', 'LanguageTwoLetter', 'LanguageThreeLetter',
            'LanguageAlias', 'LanguageNative', 'CodeSet', 'CountryCode', 'Locale', 'IsWsfc'
        }

        It "Should return property: <_>" -ForEach $props {
            $result.PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
        }
    }
}
