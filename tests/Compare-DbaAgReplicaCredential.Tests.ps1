#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaCredential",
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
                "AvailabilityGroup",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues["*-Dba*:SqlCredential"] = $TestConfig.SqlCred
        $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

        $credentialName = "dbatoolsci_AgCredCompare_$(Get-Random)"
        $securePassword = ConvertTo-SecureString -String "dbatools.IO" -AsPlainText -Force

        # Create credential on instance1 only so it will be "Missing" on other replicas
        $splatCredential = @{
            SqlInstance    = $TestConfig.instance1
            Name           = $credentialName
            Identity       = "dbatoolsci_identity"
            SecurePassword = $securePassword
        }
        $null = New-DbaCredential @splatCredential

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues["*-Dba*:SqlCredential"] = $TestConfig.SqlCred
        $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

        # Get AG replicas and clean up credential from all of them
        $ag = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.instance1
        foreach ($replica in $ag.AvailabilityReplicas.Name) {
            Get-DbaCredential -SqlInstance $replica -Credential $credentialName -ErrorAction SilentlyContinue | Remove-DbaCredential -ErrorAction SilentlyContinue
        }
    }

    Context "When comparing credentials across AG replicas" {
        BeforeAll {
            $splatCompare = @{
                SqlInstance   = $TestConfig.instance1
                SqlCredential = $TestConfig.SqlCred
            }
            $results = Compare-DbaAgReplicaCredential @splatCompare -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return results for credentials that differ across replicas" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return results containing the test credential" {
            $testResults = $results | Where-Object CredentialName -eq $credentialName
            $testResults | Should -Not -BeNullOrEmpty
        }

        It "Should show Present status on the replica where credential exists" {
            $presentResult = $results | Where-Object { $PSItem.CredentialName -eq $credentialName -and $PSItem.Replica -eq $TestConfig.instance1 }
            $presentResult.Status | Should -Be "Present"
        }

        It "Should show Missing status on replicas where credential does not exist" {
            $missingResults = $results | Where-Object { $PSItem.CredentialName -eq $credentialName -and $PSItem.Status -eq "Missing" }
            $missingResults | Should -Not -BeNullOrEmpty
        }

        It "Should include the correct identity for present credentials" {
            $presentResult = $results | Where-Object { $PSItem.CredentialName -eq $credentialName -and $PSItem.Status -eq "Present" }
            $presentResult.Identity | Should -Be "dbatoolsci_identity"
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
                "AvailabilityGroup",
                "Replica",
                "CredentialName",
                "Status",
                "Identity"
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
