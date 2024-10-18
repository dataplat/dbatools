param($ModuleName = 'dbatools')

Describe "Get-DbatoolsLog" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsLog
        }
        It "Should have FunctionName as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter FunctionName -Type System.String -Mandatory:$false
        }
        It "Should have ModuleName as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleName -Type System.String -Mandatory:$false
        }
        It "Should have Target as a non-mandatory System.Object parameter" {
            $CommandUnderTest | Should -HaveParameter Target -Type System.Object -Mandatory:$false
        }
        It "Should have Tag as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Tag -Type System.String[] -Mandatory:$false
        }
        It "Should have Last as a non-mandatory System.Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type System.Int32 -Mandatory:$false
        }
        It "Should have LastError as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter LastError -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have Skip as a non-mandatory System.Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Skip -Type System.Int32 -Mandatory:$false
        }
        It "Should have Runspace as a non-mandatory System.Guid parameter" {
            $CommandUnderTest | Should -HaveParameter Runspace -Type System.Guid -Mandatory:$false
        }
        It "Should have Level as a non-mandatory Dataplat.Dbatools.Message.MessageLevel[] parameter" {
            $CommandUnderTest | Should -HaveParameter Level -Type Dataplat.Dbatools.Message.MessageLevel[] -Mandatory:$false
        }
        It "Should have Raw as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have Errors as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Errors -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
