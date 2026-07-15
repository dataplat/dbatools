#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "appveyor.prep",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        $prepScriptPath = Join-Path $PSScriptRoot "appveyor.prep.ps1"
        $prepTokens = $null
        $prepParseErrors = $null
        $prepAst = [System.Management.Automation.Language.Parser]::ParseFile($prepScriptPath, [ref]$prepTokens, [ref]$prepParseErrors)
        $directoryCommands = $prepAst.FindAll( {
                param($ast)

                $ast -is [System.Management.Automation.Language.CommandAst] -and
                $ast.GetCommandName() -eq "New-Item"
            }, $true)
    }

    It "creates required directories idempotently" {
        foreach ($requiredPath in "C:\Users\appveyor\Documents\DbatoolsExport", "C:\Temp") {
            $matchingCommands = @($directoryCommands | Where-Object { $PSItem.Extent.Text -match [regex]::Escape("-Path $requiredPath") })
            $matchingCommands.Count | Should -Be 1

            $parameterNames = $matchingCommands[0].CommandElements |
                Where-Object { $PSItem -is [System.Management.Automation.Language.CommandParameterAst] } |
                ForEach-Object ParameterName
            $parameterNames | Should -Contain "Force"
        }
    }
}
