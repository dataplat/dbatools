#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbView",
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
                "Database",
                "View",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Get-DbaProcess -SqlInstance $InstanceSingle | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbname1

        $view1 = "dbatoolssci_view1_$(Get-Random)"
        $view2 = "dbatoolssci_view2_$(Get-Random)"
        $null = $InstanceSingle.Query("CREATE VIEW $view1 (a) AS (SELECT @@VERSION );" , $dbname1)
        $null = $InstanceSingle.Query("CREATE VIEW $view2 (b) AS (SELECT 1);", $dbname1)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbname1

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing views" {
        It "removes a view" {
            (Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbname1 -View $view1) | Should -Not -BeNullOrEmpty
            Remove-DbaDbView -SqlInstance $InstanceSingle -Database $dbname1 -View $view1
            (Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbname1 -View $view1) | Should -BeNullOrEmpty
        }

        It "supports piping view" {
            (Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbname1 -View $view2) | Should -Not -BeNullOrEmpty
            Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbname1 -View $view2 | Remove-DbaDbView
            (Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbname1 -View $view2) | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputDbName = "dbatoolsci_removeview_output_$(Get-Random)"
            $outputViewName = "dbatoolsci_outputview_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputDbName
            $outputInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = $outputInstance.Query("CREATE VIEW $outputViewName (a) AS (SELECT 1);", $outputDbName)
            $result = Remove-DbaDbView -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -View $outputViewName -Confirm:$false
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "View", "ViewName", "ViewSchema", "Status", "IsRemoved")
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the correct values for a successful removal" {
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Dropped"
            $result.IsRemoved | Should -BeTrue
            $result.Database | Should -Be $outputDbName
            $result.ViewName | Should -Be $outputViewName
            $result.ViewSchema | Should -Be "dbo"
            $result.View | Should -Be "dbo.$outputViewName"
        }
    }
}