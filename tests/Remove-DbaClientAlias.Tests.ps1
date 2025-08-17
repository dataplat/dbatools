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
                $global:aliases = Get-DbaClientAlias
            }

            It "alias exists" {
                $global:aliases.AliasName -contains "dbatoolscialias1" | Should -Be $true
            }

            It "removes the alias and shows computername" {
                $results = Remove-DbaClientAlias -Alias dbatoolscialias1 -Verbose:$false
                $results.ComputerName | Should -Not -BeNullOrEmpty
            }

            It "alias is not included in results" {
                $global:aliases = Get-DbaClientAlias
                $global:aliases.AliasName -notcontains "dbatoolscialias1" | Should -Be $true
            }
        }

        Context "removes an array of aliases" {
            BeforeAll {
                $global:testCases = @(
                    @{"Alias" = "dbatoolscialias2" },
                    @{"Alias" = "dbatoolscialias3" }
                )
                $global:aliases = Get-DbaClientAlias
            }

            It "alias <Alias> exists" -TestCases $global:testCases {
                param ($Alias)
                $global:aliases.AliasName -contains $Alias | Should -Be $true
            }

            It "removes array of aliases" {
                $null = Remove-DbaClientAlias -Alias @("dbatoolscialias2", "dbatoolscialias3")
                $global:aliases = Get-DbaClientAlias
                $global:aliases.AliasName -notcontains "dbatoolscialias2" | Should -Be $true
                $global:aliases.AliasName -notcontains "dbatoolscialias3" | Should -Be $true
            }
        }

        Context "removes an alias through the pipeline" {
            BeforeAll {
                $global:aliases = Get-DbaClientAlias
            }

            It "alias exists" {
                $global:aliases.AliasName -contains "dbatoolscialias4" | Should -Be $true
            }

            It "removes alias via pipeline" {
                $null = Get-DbaClientAlias | Where-Object AliasName -eq "dbatoolscialias4" | Remove-DbaClientAlias
                $global:aliases = Get-DbaClientAlias
                $global:aliases.AliasName -notcontains "dbatoolscialias4" | Should -Be $true
            }
        }

        Context "SQL client is not installed" {
            It "warns that the key doesn't exist" {
                Mock -CommandName Test-Path -MockWith {
                    return $false
                }
                $global:defaultParamValues = $PSDefaultParameterValues
                $PSDefaultParameterValues = @{"*:WarningVariable" = "+buffer" }
                $null = Remove-DbaClientAlias -Alias dbatoolscialias5 -WarningAction SilentlyContinue
                $PSDefaultParameterValues = $global:defaultParamValues
                $buffer.Count -ge 4 | Should -Be $true
            }
        }
    }
}