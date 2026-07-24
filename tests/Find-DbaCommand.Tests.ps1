#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaCommand",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Pattern",
                "Tag",
                "Author",
                "MinimumVersion",
                "MaximumVersion",
                "Rebuild",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $dbatoolsModule = Get-Module -Name dbatools |
            Where-Object ModuleType -eq "Script" |
            Select-Object -First 1
        $script:indexPath = Join-Path $dbatoolsModule.ModuleBase "bin\dbatools-index.json"
        $script:indexBytes = [System.IO.File]::ReadAllBytes($script:indexPath)
        $script:indexHash = (Get-FileHash -LiteralPath $script:indexPath -Algorithm SHA256).Hash
    }

    AfterAll {
        [System.IO.File]::WriteAllBytes($script:indexPath, $script:indexBytes)
        $restoredHash = (Get-FileHash -LiteralPath $script:indexPath -Algorithm SHA256).Hash
        if ($restoredHash -ne $script:indexHash) {
            throw "Find-DbaCommand test fixture restore failed: $restoredHash != $($script:indexHash)"
        }
    }

    Context "Command finds jobs using all parameters" {
        It "Should find more than 5 snapshot commands" {
            $results = @(Find-DbaCommand -Pattern "snapshot")
            $results.Count | Should -BeGreaterThan 5
        }

        It "Should find more than 20 commands tagged as job" {
            $results = @(Find-DbaCommand -Tag Job)
            $results.Count | Should -BeGreaterThan 20
        }

        It "Should find a command that has both Job and Owner tags" {
            $results = @(Find-DbaCommand -Tag Job, Owner)
            $results.CommandName | Should -Contain "Test-DbaAgentJobOwner"
        }

        It "Should find more than 250 commands authored by Chrissy" {
            $results = @(Find-DbaCommand -Author chrissy)
            $results.Count | Should -BeGreaterThan 250
        }

        It "Should find more than 15 commands for AGs authored by Chrissy" {
            $results = @(Find-DbaCommand -Author chrissy -Tag AG)
            $results.Count | Should -BeGreaterThan 15
        }

        It "Should find more than 5 snapshot commands after Rebuilding the index" {
            $results = @(Find-DbaCommand -Pattern snapshot -Rebuild)
            $results.Count | Should -BeGreaterThan 5

            $eligibleCommands = @(
                (Get-Module -Name "dbatools*").ExportedCommands.Values |
                    Where-Object CommandType -In "Function", "Cmdlet" |
                    Where-Object Name -NotIn "Write-Message" |
                    Sort-Object -Property Name -Unique
            )
            [array]$rebuiltIndex = Get-Content -LiteralPath $script:indexPath -Raw | ConvertFrom-Json
            @($rebuiltIndex.CommandName | Sort-Object -Unique).Count |
                Should -Be $eligibleCommands.Count

            @(Find-DbaCommand -Tag Job).Count | Should -BeGreaterThan 20
            @(Find-DbaCommand -Author chrissy).Count | Should -BeGreaterThan 250
            @(Find-DbaCommand -Author chrissy -Tag AG).Count | Should -BeGreaterThan 15
        }
    }
}
