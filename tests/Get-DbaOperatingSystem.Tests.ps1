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
        $result = Get-DbaOperatingSystem -ComputerName $TestConfig.InstanceSingle

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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaOperatingSystem -ComputerName $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "Manufacturer",
                "Organization",
                "Architecture",
                "Version",
                "OSVersion",
                "LastBootTime",
                "LocalDateTime",
                "PowerShellVersion",
                "TimeZone",
                "TotalVisibleMemory",
                "ActivePowerPlan",
                "LanguageNative"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has all documented additional properties" {
            $additionalProps = @(
                "Build",
                "SPVersion",
                "InstallDate",
                "BootDevice",
                "SystemDevice",
                "SystemDrive",
                "WindowsDirectory",
                "PagingFileSize",
                "FreePhysicalMemory",
                "TotalVirtualMemory",
                "FreeVirtualMemory",
                "Status",
                "Language",
                "LanguageId",
                "LanguageKeyboardLayoutId",
                "LanguageTwoLetter",
                "LanguageThreeLetter",
                "LanguageAlias",
                "CodeSet",
                "CountryCode",
                "Locale",
                "IsWsfc"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }
    }
}