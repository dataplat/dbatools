#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaServiceMasterKey",
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
                "Credential",
                "SecurePassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # New-DbaServiceMasterKey creates a master-database master key (the service master key). An
        # instance master already carrying one is the common case: creating a second fails, and
        # dropping a pre-existing one would break the encryption hierarchy. So this suite ONLY acts
        # when master has none, and the AfterAll removes only the key this suite created - master is
        # left exactly as found.
        $securePassword = ConvertTo-SecureString "Dbatools.IO.$(Get-Random)" -AsPlainText -Force
        $existingKey = Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database master -EnableException:$false
    }

    Context "Creating the service master key on a live instance" {
        It "Creates a MasterKey in master with the documented shape when none exists" {
            if ($existingKey) {
                Set-ItResult -Skipped -Because "master already has a master key on $($TestConfig.InstanceSingle); creating or dropping it would disturb the encryption hierarchy"
                return
            }
            $splatServiceKey = @{
                SqlInstance     = $TestConfig.InstanceSingle
                SecurePassword  = $securePassword
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaServiceMasterKey @splatServiceKey
            $result | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be "master"
            $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.MasterKey
        }
    }

    AfterAll {
        # Leave master as found: drop the key only when the suite created it (master had none before).
        if (-not $existingKey) {
            $null = Remove-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database master -Confirm:$false -EnableException:$false
        }
    }
}