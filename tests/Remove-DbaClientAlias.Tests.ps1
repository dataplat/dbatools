param($ModuleName = 'dbatools')

Describe "Remove-DbaClientAlias" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        # Create test aliases
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias1 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias2 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias3 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias4 -Verbose:$false
        $null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias5 -Verbose:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaClientAlias
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Alias as a parameter" {
            $CommandUnderTest | Should -HaveParameter Alias
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Removes the alias" {
        BeforeAll {
            $aliases = Get-DbaClientAlias
        }
        It "Alias exists" {
            $aliases.AliasName | Should -Contain 'dbatoolscialias1'
        }

        It "Removes the alias and shows computername" {
            $results = Remove-DbaClientAlias -Alias dbatoolscialias1 -Verbose:$false
            $results.ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Alias is not included in results" {
            $aliases = Get-DbaClientAlias
            $aliases.AliasName | Should -Not -Contain 'dbatoolscialias1'
        }
    }

    Context "Removes an array of aliases" {
        BeforeAll {
            $testCases = @(
                @{'Alias' = 'dbatoolscialias2'},
                @{'Alias' = 'dbatoolscialias3'}
            )
            $aliases = Get-DbaClientAlias
        }

        It "Alias <Alias> exists" -TestCases $testCases {
            param ($Alias)
            $aliases.AliasName | Should -Contain $Alias
        }

        It "Removes multiple aliases" {
            $null = Remove-DbaClientAlias -Alias @('dbatoolscialias2', 'dbatoolscialias3')
            $aliases = Get-DbaClientAlias
            $aliases.AliasName | Should -Not -Contain 'dbatoolscialias2'
            $aliases.AliasName | Should -Not -Contain 'dbatoolscialias3'
        }
    }

    Context "Removes an alias through the pipeline" {
        BeforeAll {
            $aliases = Get-DbaClientAlias
        }
        It "Alias exists" {
            $aliases.AliasName | Should -Contain 'dbatoolscialias4'
        }

        It "Removes alias through pipeline" {
            $null = Get-DbaClientAlias | Where-Object { $_.AliasName -eq 'dbatoolscialias4' } | Remove-DbaClientAlias
            $aliases = Get-DbaClientAlias
            $aliases.AliasName | Should -Not -Contain 'dbatoolscialias4'
        }
    }

    Context "SQL client is not installed" {
        BeforeAll {
            Mock -CommandName 'Test-Path' -MockWith {
                return $false
            } -ModuleName $ModuleName

            $defaultParamValues = $PSDefaultParameterValues
            $PSDefaultParameterValues = @{"*:WarningVariable" = "+buffer"}
        }

        AfterAll {
            $PSDefaultParameterValues = $defaultParamValues
        }

        It "Warns that the key doesn't exist" {
            $null = Remove-DbaClientAlias -Alias 'dbatoolscialias5' -WarningAction 'SilentlyContinue'
            $buffer.Count | Should -BeGreaterOrEqual 4
        }
    }
}
