#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbEncryptionKey",
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

        $encryptionPasswd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $masterCertExists = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $masterCertExists) {
            $delmastercert = $true
            $masterCertExists = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
        }

        $testDatabase = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        $testDatabase | New-DbaDbMasterKey -SecurePassword $encryptionPasswd
        $testDatabase | New-DbaDbCertificate
        $testDbEncryptionKey = $testDatabase | New-DbaDbEncryptionKey -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($testDatabase) {
            $testDatabase | Remove-DbaDatabase
        }
        if ($delmastercert) {
            $masterCertExists | Remove-DbaDbCertificate
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should remove encryption key on a database using piping" {
            $results = $testDbEncryptionKey | Remove-DbaDbEncryptionKey -OutVariable "global:dbatoolsciOutput"
            $results.Status | Should -Be "Success"
            $testDatabase.Refresh()
            $testDatabase | Get-DbaDbEncryptionKey | Should -Be $null
        }
        It "should remove encryption key on a database" {
            $null = $testDatabase | New-DbaDbEncryptionKey -Force
            $results = Remove-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $testDatabase.Name
            $results.Status | Should -Be "Success"
            $testDatabase.Refresh()
            $testDatabase | Get-DbaDbEncryptionKey | Should -Be $null
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