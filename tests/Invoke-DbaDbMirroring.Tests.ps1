#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbMirroring",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Primary",
                "PrimarySqlCredential",
                "Mirror",
                "MirrorSqlCredential",
                "Witness",
                "WitnessSqlCredential",
                "Database",
                "EndpointEncryption",
                "EncryptionAlgorithm",
                "SharedPath",
                "InputObject",
                "UseLastBackup",
                "Force",
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

        # Set variables. They are available in all the It blocks.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $dbName = "dbatoolsci_mirroring"
        $endpointName = "dbatoolsci_MirroringEndpoint"

        # Create the objects.
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $dbName
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1 -Name $endpointName -Type DatabaseMirroring -Port 5022 -Owner sa
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Name $endpointName -Type DatabaseMirroring -Port 5023 -Owner sa

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbName
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbName
        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -EndPoint $endpointName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns success" {
        $splatMirroring = @{
            Primary    = $TestConfig.InstanceCopy1
            Mirror     = $TestConfig.InstanceCopy2
            Database   = $dbName
            Force      = $true
            SharedPath = $TestConfig.Temp
        }
        $results = Invoke-DbaDbMirroring @splatMirroring -WarningVariable WarnVar
        $global:dbatoolsciOutput = $results
        $WarnVar | Should -BeNullOrEmpty
        $results.Status | Should -Be "Success"
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Primary",
                "Mirror",
                "Witness",
                "Database",
                "ServiceAccount",
                "Status"
            )
            $actualProperties = $global:dbatoolsciOutput.PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "Primary",
                "Mirror",
                "Database",
                "Status"
            )
            $defaultColumns = $global:dbatoolsciOutput.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}