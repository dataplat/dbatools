#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-SqlDefaultSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Private SQL configuration defaults" {
    BeforeAll {
        $defaultsModule = Get-Module dbatools | Where-Object ModuleType -eq Script
    }

    It "preserves the mandatory object parameter and Version alias" {
        $defaultsCommand = & $defaultsModule { Get-Command Get-SqlDefaultSpConfigure }
        $defaultsCommand.Parameters["SqlVersion"].ParameterType | Should -Be ([object])
        $defaultsCommand.Parameters["SqlVersion"].Aliases | Should -Contain "Version"
        $defaultsBinding = $defaultsCommand.ParameterSets.Parameters | Where-Object Name -eq SqlVersion
        $defaultsBinding.Position | Should -Be 0
        $defaultsBinding.IsMandatory | Should -BeTrue
        $defaultsBinding.ValueFromPipeline | Should -BeFalse
        $defaultsBinding.ValueFromPipelineByPropertyName | Should -BeFalse
        Compare-Object (@($TestConfig.CommonParameters) + "SqlVersion") @($defaultsCommand.Parameters.Keys) | Should -BeNullOrEmpty
        $defaultsAliasRows = @(& $defaultsModule { Get-SqlDefaultSpConfigure -Version 16 })
        $defaultsAliasRows.Count | Should -Be 1
        $defaultsAliasRows[0]."max degree of parallelism" | Should -Be 4
    }

    It "returns each pinned version table with integer values and version-specific defaults" {
        $defaultsCounts = @(37, 67, 72, 71, 72, 78, 79, 83, 95)
        foreach ($defaultsVersion in 8..16) {
            $defaultsRows = @(& $defaultsModule { param($value) Get-SqlDefaultSpConfigure -SqlVersion $value } $defaultsVersion)
            $defaultsRows.Count | Should -Be 1
            $defaultsRows[0] | Should -BeOfType System.Management.Automation.PSCustomObject
            @($defaultsRows[0].PSObject.Properties).Count | Should -Be $defaultsCounts[$defaultsVersion - 8]
            foreach ($defaultsProperty in $defaultsRows[0].PSObject.Properties) {
                $defaultsProperty.Value | Should -BeOfType System.Int32
            }
            $defaultsRows[0]."cost threshold for parallelism" | Should -Be 5
            $defaultsRows[0]."max server memory (MB)" | Should -Be 2147483647
        }
        (& $defaultsModule { Get-SqlDefaultSpConfigure 8 })."max worker threads" | Should -Be 255
        (& $defaultsModule { Get-SqlDefaultSpConfigure 16 })."max degree of parallelism" | Should -Be 4
    }

    It "emits ordered independent tables for array values and ignores unsupported versions" {
        $defaultsArray = @(& $defaultsModule { Get-SqlDefaultSpConfigure -SqlVersion @(8, 999, 16) })
        $defaultsArray.Count | Should -Be 2
        @($defaultsArray[0].PSObject.Properties).Count | Should -Be 37
        @($defaultsArray[1].PSObject.Properties).Count | Should -Be 95
        $defaultsDuplicates = @(& $defaultsModule { Get-SqlDefaultSpConfigure -SqlVersion @(14, 14) })
        $defaultsDuplicates.Count | Should -Be 2
        $defaultsDuplicates[0]."cost threshold for parallelism" = 99
        $defaultsDuplicates[1]."cost threshold for parallelism" | Should -Be 5
        @(& $defaultsModule { Get-SqlDefaultSpConfigure -SqlVersion "unknown" }).Count | Should -Be 0
    }

    It "preserves the observed switch conversion instead of normalizing numeric-looking strings" {
        foreach ($defaultsMatching in @("8", [double]8.0)) {
            $defaultsMatchingRows = @(& $defaultsModule { param($value) Get-SqlDefaultSpConfigure -SqlVersion $value } $defaultsMatching)
            $defaultsMatchingRows.Count | Should -Be 1
            @($defaultsMatchingRows[0].PSObject.Properties).Count | Should -Be 37
        }
        foreach ($defaultsNonmatching in @("08", "8.0", [decimal]::Parse("8.0", [Globalization.CultureInfo]::InvariantCulture))) {
            @(& $defaultsModule { param($value) Get-SqlDefaultSpConfigure -SqlVersion $value } $defaultsNonmatching).Count | Should -Be 0
        }
    }

    It "rejects null and empty mandatory values" {
        { & $defaultsModule { Get-SqlDefaultSpConfigure -SqlVersion $null } } | Should -Throw
        { & $defaultsModule { Get-SqlDefaultSpConfigure -SqlVersion "" } } | Should -Throw
        { & $defaultsModule { Get-SqlDefaultSpConfigure -SqlVersion @() } } | Should -Throw
    }
}
