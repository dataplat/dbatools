#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaOperatingSystem",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName { $null }
            { Get-DbaOperatingSystem -ComputerName "DoesNotExist142" -WarningAction Stop 3> $null } | Should -Throw
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $result = Get-DbaOperatingSystem -ComputerName $TestConfig.instance1

        $props = @(
            "ComputerName", "Manufacturer", "Organization",
            "Architecture", "Build", "Version", "InstallDate", "LastBootTime", "LocalDateTime",
            "BootDevice", "TimeZone", "TimeZoneDaylight", "TimeZoneStandard", "TotalVisibleMemory",
            "OSVersion", "SPVersion", "PowerShellVersion", "SystemDevice", "SystemDrive", "WindowsDirectory",
            "PagingFileSize", "FreePhysicalMemory", "TotalVirtualMemory", "FreeVirtualMemory", "ActivePowerPlan",
            "Status", "Language", "LanguageId", "LanguageKeyboardLayoutId", "LanguageTwoLetter", "LanguageThreeLetter",
            "LanguageAlias", "LanguageNative", "CodeSet", "CountryCode", "Locale", "IsWsfc"
        )

        <#
            FreePhysicalMemory: units = KB
            FreeVirtualMemory: units = KB
            TimeZoneStandard: StandardName from win32_timezone
            TimeZoneDaylight: DaylightName from win32_timezone
            TimeZone: Caption from win32_timezone
        #>
    }

    Context "Validate standard output" {
        BeforeAll {
            $propertyTests = @()
            foreach ($prop in $props) {
                $p = $result.PSObject.Properties[$prop]
                $propertyTests += @{ PropName = $prop; PropObject = $p }
            }
        }

        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $p = $result.PSObject.Properties[$prop]
                $p.Name | Should -Be $prop
            }
        }
    }
}