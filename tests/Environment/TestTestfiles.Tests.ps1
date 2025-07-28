#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName               = "dbatools",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "the test files" {
    BeforeAll {
        $scriptPath = 'C:\GitHub\dbatools\tests\Add-DbaAgDatabase.Tests.ps1'

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)

        $paramBlockParameters = $ast.ParamBlock.Parameters
        $describeBlocks = $ast.EndBlock.Statements
    }

    It "Has the correct param block" {
        $paramBlockParameters.Count | Should -Be 2
        $paramBlockParameters.Name.VariablePath.UserPath | Should -Contain 'ModuleName'
        $paramBlockParameters.Name.VariablePath.UserPath | Should -Contain 'PSDefaultParameterValues'
        ($paramBlockParameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ModuleName' }).DefaultValue.Value | Should -Be 'dbatools'
        ($paramBlockParameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'PSDefaultParameterValues' }).DefaultValue.Extent.Text | Should -Be '$TestConfig.Defaults'
    }

    It "Has the correct Describe blocks" {
        $describeBlocks.Count | Should -Be 2

        $unitTestBlock = $describeBlocks[0]  # Describe "... UnitTests" -Tag "UnitTests" { ... }
        $unitTestBlock.PipelineElements.CommandElements[0].Value | Should -Be 'Describe'
        $unitTestBlock.PipelineElements.CommandElements[3].Value | Should -Be 'UnitTests'

        $integrationTestBlock = $describeBlocks[1]  # Describe "... IntegrationTests" -Tag "IntegrationTests" { ... }
        $integrationTestBlock.PipelineElements.CommandElements[0].Value | Should -Be 'Describe'
        $integrationTestBlock.PipelineElements.CommandElements[3].Value | Should -Be 'IntegrationTests'

        $integrationTestStatements = $integrationTestBlock.PipelineElements.CommandElements[-1].ScriptBlock.EndBlock.Statements
        $integrationTestStatements[0].PipelineElements.CommandElements[0].Value | Should -Be 'BeforeAll'

        $integrationTestBeforeAllStatements = $integrationTestStatements[0].PipelineElements.CommandElements[-1].ScriptBlock.EndBlock.Statements
        $integrationTestBeforeAllStatements[0].Extent.Text | Should -Be '$PSDefaultParameterValues[''*-Dba*:EnableException''] = $true'
        $integrationTestBeforeAllStatements[-1].Extent.Text | Should -Be '$PSDefaultParameterValues.Remove(''*-Dba*:EnableException'')'

        $integrationTestAfterAllStatements = $integrationTestStatements[1].PipelineElements.CommandElements[-1].ScriptBlock.EndBlock.Statements
        $integrationTestAfterAllStatements[0].Extent.Text | Should -Be '$PSDefaultParameterValues[''*-Dba*:EnableException''] = $true'
    }
}
