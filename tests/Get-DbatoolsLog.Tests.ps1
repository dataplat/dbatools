param($ModuleName = 'dbatools')

Describe "Get-DbatoolsLog" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsLog
        }
        It "Should have FunctionName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter FunctionName -Type String -Not -Mandatory
        }
        It "Should have ModuleName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleName -Type String -Not -Mandatory
        }
        It "Should have Target as a non-mandatory Object parameter" {
            $CommandUnderTest | Should -HaveParameter Target -Type Object -Not -Mandatory
        }
        It "Should have Tag as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Tag -Type String[] -Not -Mandatory
        }
        It "Should have Last as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type Int32 -Not -Mandatory
        }
        It "Should have LastError as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter LastError -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Skip as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Skip -Type Int32 -Not -Mandatory
        }
        It "Should have Runspace as a non-mandatory Guid parameter" {
            $CommandUnderTest | Should -HaveParameter Runspace -Type Guid -Not -Mandatory
        }
        It "Should have Level as a non-mandatory MessageLevel[] parameter" {
            $CommandUnderTest | Should -HaveParameter Level -Type MessageLevel[] -Not -Mandatory
        }
        It "Should have Raw as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Errors as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Errors -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Add any necessary setup for command usage tests
        }

        It "Should return log entries" {
            $result = Get-DbatoolsLog
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should filter by FunctionName" {
            $functionName = "Test-Function"
            $result = Get-DbatoolsLog -FunctionName $functionName
            $result | ForEach-Object { $_.FunctionName | Should -Be $functionName }
        }

        It "Should filter by ModuleName" {
            $moduleName = "dbatools"
            $result = Get-DbatoolsLog -ModuleName $moduleName
            $result | ForEach-Object { $_.ModuleName | Should -Be $moduleName }
        }

        It "Should limit results with Last parameter" {
            $last = 5
            $result = Get-DbatoolsLog -Last $last
            $result.Count | Should -Be $last
        }

        It "Should return raw results when Raw switch is used" {
            $result = Get-DbatoolsLog -Raw
            $result | Should -BeOfType [PSCustomObject]
        }

        It "Should return only errors when Errors switch is used" {
            $result = Get-DbatoolsLog -Errors
            $result | ForEach-Object { $_.Level | Should -Be 'Error' }
        }
    }
}
