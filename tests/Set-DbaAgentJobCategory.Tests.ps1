#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJobCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Category",
                "NewName",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "New Agent Job Category is changed properly" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create test category for modification
            $testCategoryName = "CategoryTest1"
            $newCategoryName = "CategoryTest2"
            $testCategory = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategoryName

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup and ignore all output
            Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $newCategoryName -ErrorAction SilentlyContinue
            Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategoryName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have the right name and category type" {
            $testCategory.Name | Should -Be "CategoryTest1"
            $testCategory.CategoryType | Should -Be "LocalJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest1
            $newresults.Name | Should -Be "CategoryTest1"
            $newresults.CategoryType | Should -Be "LocalJob"
        }

        It "Change the name of the job category" {
            $results = Set-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest1 -NewName CategoryTest2
            $results.Name | Should -Be "CategoryTest2"
        }
    }

    Context "Begin guard and WhatIf" {
        It "Halts every record when several categories are renamed to one name" {
            # The begin block's many-to-one guard is a non-Continue Stop-Function that sets the
            # function-scope interrupt; every process record then short-circuits at Test-FunctionInterrupt.
            # So the rename never runs and both source categories keep their names - proving the begin
            # interrupt carries into the process records.
            $splatNew = @{
                SqlInstance     = $TestConfig.InstanceSingle
                EnableException = $true
            }
            $catA = "dbatoolsci_guardA_$(Get-Random)"
            $catB = "dbatoolsci_guardB_$(Get-Random)"
            $null = New-DbaAgentJobCategory @splatNew -Category $catA
            $null = New-DbaAgentJobCategory @splatNew -Category $catB
            try {
                $splatMany = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Category        = @($catA, $catB)
                    NewName         = "dbatoolsci_guardOne_$(Get-Random)"
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "warn"
                }
                Set-DbaAgentJobCategory @splatMany 3> $null
                $warn -join " " | Should -Match "cannot rename multiple"
                (Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $catA).Name | Should -Be $catA
                (Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $catB).Name | Should -Be $catB
            } finally {
                Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category @($catA, $catB) -ErrorAction SilentlyContinue
            }
        }

        It "Does not rename under -WhatIf" {
            $splatNew = @{
                SqlInstance     = $TestConfig.InstanceSingle
                EnableException = $true
            }
            $catSrc = "dbatoolsci_wifsrc_$(Get-Random)"
            $catDst = "dbatoolsci_wifdst_$(Get-Random)"
            $null = New-DbaAgentJobCategory @splatNew -Category $catSrc
            try {
                Set-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $catSrc -NewName $catDst -WhatIf
                (Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $catSrc).Name | Should -Be $catSrc
                Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $catDst -WarningAction SilentlyContinue | Should -BeNullOrEmpty
            } finally {
                Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category @($catSrc, $catDst) -ErrorAction SilentlyContinue
            }
        }
    }
}