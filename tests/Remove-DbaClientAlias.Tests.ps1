#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaClientAlias",
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
                "Alias",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (W1-033). The previous IntegrationTests wrapped every Context in
    # InModuleScope dbatools - the Invoke-ManualPester harness discovers ZERO tests in that shape
    # (RB-IMP-51 class; plain Invoke-Pester found them all), and the "SQL client is not installed"
    # test relied on Mock Test-Path (unreachable inside the Invoke-Command2 scriptblock hop and
    # impossible against a compiled cmdlet) while asserting a nested-frame warning re-capture
    # COUNT ($buffer.Count -ge 4 for 2 logical warnings). These tests pin the same contract
    # harness-honestly: real registry round-trips plus warning TEXT, count-agnostic.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias1 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias2 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias3 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias4 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias5 -Verbose:$false

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup - remove any test aliases that survived the tests.
        Get-DbaClientAlias | Where-Object AliasName -like "dbatoolscialias*" | Remove-DbaClientAlias

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "removes the alias" {
        BeforeAll {
            $aliases = Get-DbaClientAlias
        }

        It "alias exists" {
            $aliases.AliasName -contains "dbatoolscialias1" | Should -Be $true
        }

        It "removes the alias and shows computername" {
            $results = Remove-DbaClientAlias -Alias dbatoolscialias1 -Verbose:$false
            $results.ComputerName | Should -Not -BeNullOrEmpty
        }

        It "alias is not included in results" {
            $aliases = Get-DbaClientAlias
            $aliases.AliasName -notcontains "dbatoolscialias1" | Should -Be $true
        }
    }

    Context "removes an array of aliases" {
        BeforeAll {
            $testCases = @(
                @{"Alias" = "dbatoolscialias2" },
                @{"Alias" = "dbatoolscialias3" }
            )
            $aliases = Get-DbaClientAlias
        }

        It "alias <Alias> exists" -TestCases $testCases {
            param ($Alias)
            $aliases.AliasName -contains $Alias | Should -Be $true
        }

        It "removes array of aliases" {
            $null = Remove-DbaClientAlias -Alias @("dbatoolscialias2", "dbatoolscialias3")
            $aliases = Get-DbaClientAlias
            $aliases.AliasName -notcontains "dbatoolscialias2" | Should -Be $true
            $aliases.AliasName -notcontains "dbatoolscialias3" | Should -Be $true
        }
    }

    Context "removes an alias through the pipeline" {
        BeforeAll {
            $aliases = Get-DbaClientAlias
        }

        It "alias exists" {
            $aliases.AliasName -contains "dbatoolscialias4" | Should -Be $true
        }

        It "removes alias via pipeline" {
            $null = Get-DbaClientAlias | Where-Object AliasName -eq "dbatoolscialias4" | Remove-DbaClientAlias
            $aliases = Get-DbaClientAlias
            $aliases.AliasName -notcontains "dbatoolscialias4" | Should -Be $true
        }
    }

    Context "warns when a registry key is missing" {
        BeforeAll {
            # Make the command's 32-bit hive Test-Path miss REAL: save the WOW6432Node ConnectTo
            # values, drop the key, and restore both afterward. This replaces the old Mock-based
            # "SQL client is not installed" shape with the warning path the command actually runs.
            $wow64ConnectTo = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer\Client\ConnectTo"
            $savedAliasValues = $null
            if (Test-Path $wow64ConnectTo) {
                $savedAliasValues = Get-ItemProperty -Path $wow64ConnectTo
                Remove-Item -Path $wow64ConnectTo
            }
        }

        AfterAll {
            if ($savedAliasValues) {
                $null = New-Item -Path $wow64ConnectTo -Force
                $aliasProperties = $savedAliasValues.PSObject.Properties | Where-Object { $PSItem.Name -notin ("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider") }
                foreach ($aliasProperty in $aliasProperties) {
                    $null = New-ItemProperty -Path $wow64ConnectTo -Name $aliasProperty.Name -Value $aliasProperty.Value
                }
            }
        }

        It "warns that the key doesn't exist" {
            # The warning is written by the registry scriptblock inside the Invoke-Command2 hop,
            # which bypasses the caller's -WarningVariable for the function and the cmdlet alike
            # (lab-proven: -WarningVariable captures 0 for both); the 3>&1 merge is the shape
            # that observes it for both implementations on both editions.
            $merged = Remove-DbaClientAlias -Alias dbatoolscialias5 3>&1
            $missingKeyWarnings = @($merged) -match "Registry key \(.*WOW6432Node.*\) does not exist"
            $missingKeyWarnings | Should -Not -BeNullOrEmpty
        }
    }
}
