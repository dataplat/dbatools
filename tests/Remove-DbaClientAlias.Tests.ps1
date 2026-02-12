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
    BeforeAll {
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias1 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias2 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias3 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias4 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias5 -Verbose:$false
    }

    InModuleScope dbatools {
        Context "removes the alias" {
            BeforeAll {
                $aliases = Get-DbaClientAlias
            }

            It "alias exists" {
                $aliases.AliasName -contains "dbatoolscialias1" | Should -Be $true
            }

            It "removes the alias and shows computername" {
                $script:results = Remove-DbaClientAlias -Alias dbatoolscialias1 -Verbose:$false
                $script:results.ComputerName | Should -Not -BeNullOrEmpty
            }

            It "alias is not included in results" {
                $aliases = Get-DbaClientAlias
                $aliases.AliasName -notcontains "dbatoolscialias1" | Should -Be $true
            }

            Context "Output validation" {
                It "Returns output of the documented type" {
                    $script:results | Should -Not -BeNullOrEmpty
                    $script:results[0] | Should -BeOfType [PSCustomObject]
                }

                It "Has the expected properties" {
                    $expectedProperties = @("ComputerName", "Architecture", "Alias", "Status")
                    foreach ($prop in $expectedProperties) {
                        $script:results[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
                    }
                }

                It "Returns the correct values" {
                    $script:results[0].Status | Should -Be "Removed"
                    $script:results[0].Alias | Should -Be "dbatoolscialias1"
                    $script:results[0].ComputerName | Should -Not -BeNullOrEmpty
                }
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

        Context "SQL client is not installed" {
            It "warns that the key doesn't exist" {
                Mock -CommandName Test-Path -MockWith {
                    return $false
                }
                $defaultParamValues = $PSDefaultParameterValues
                $PSDefaultParameterValues = @{"*:WarningVariable" = "+buffer" }
                $null = Remove-DbaClientAlias -Alias dbatoolscialias5 -WarningAction SilentlyContinue
                $PSDefaultParameterValues = $defaultParamValues
                $buffer.Count -ge 4 | Should -Be $true
            }
        }
    }
}