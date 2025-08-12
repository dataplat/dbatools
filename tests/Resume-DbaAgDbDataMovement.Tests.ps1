#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Resume-DbaAgDbDataMovement",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "Database",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $global:agName = "dbatoolsci_resumeagdb_agroup"
        $global:dbName = "dbatoolsci_resumeagdb_agroupdb"
        $global:server.Query("create database $global:dbName")
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $global:dbName | Backup-DbaDatabase -FilePath "$($TestConfig.Temp)\$global:dbName.bak"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $global:dbName | Backup-DbaDatabase -FilePath "$($TestConfig.Temp)\$global:dbName.trn" -Type Log
        
        $splatAvailabilityGroup = @{
            Primary      = $TestConfig.instance3
            Name         = $global:agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Database     = $global:dbName
            Confirm      = $false
            Certificate  = "dbatoolsci_AGCert"
            UseLastBackup = $true
        }
        $global:ag = New-DbaAvailabilityGroup @splatAvailabilityGroup
        $null = Get-DbaAgDatabase -SqlInstance $TestConfig.instance3 -AvailabilityGroup $global:agName | Suspend-DbaAgDbDataMovement -Confirm $false

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAvailabilityGroup -SqlInstance $global:server -AvailabilityGroup $global:agName -Confirm $false
        $null = Get-DbaEndpoint -SqlInstance $global:server -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm $false
        $null = Remove-DbaDatabase -SqlInstance $global:server -Database $global:dbName -Confirm $false
        Remove-Item -Path "$($TestConfig.Temp)\$global:dbName.bak", "$($TestConfig.Temp)\$global:dbName.trn" -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }
    
    Context "Resumes data movement" {
        It "Returns resumed results" {
            $results = Resume-DbaAgDbDataMovement -SqlInstance $TestConfig.instance3 -Database $global:dbName -Confirm $false
            $results.AvailabilityGroup | Should -Be $global:agName
            $results.Name | Should -Be $global:dbName
            $results.SynchronizationState | Should -Be "Synchronized"
        }
    }
} #$TestConfig.instance2 for appveyor
