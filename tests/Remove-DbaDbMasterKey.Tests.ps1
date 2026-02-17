#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMasterKey",
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
                "ExcludeDatabase",
                "All",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $testDbName = "dbatoolsci_removemk_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $testDbName
        $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $testDbName -SecurePassword (ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force) -Confirm:$false
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "Can remove a database master key" {
        It "Successfully removes database master key" {
            $global:dbatoolsciOutput = @(Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $testDbName | Remove-DbaDbMasterKey -Confirm:$false | Where-Object { $null -ne $PSItem })
            $global:dbatoolsciOutput | Should -Not -BeNullOrEmpty
            $global:dbatoolsciOutput.Status | Should -Be "Master key removed"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Status"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}