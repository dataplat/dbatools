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
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Set variables. They are available in all the It blocks.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $dbName = "dbatoolsci_mirroring"
        $endpointName = "dbatoolsci_MirroringEndpoint"

        # Create the objects.
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbName
        $null = New-DbaEndpoint -SqlInstance $TestConfig.instance2 -Name $endpointName -Type DatabaseMirroring -Port 5022 -Owner sa
        $null = New-DbaEndpoint -SqlInstance $TestConfig.instance3 -Name $endpointName -Type DatabaseMirroring -Port 5023 -Owner sa

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDbMirror -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $dbName -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $dbName -Confirm:$false
        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -EndPoint $endpointName -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    It "returns success" {
        $splatMirroring = @{
            Primary    = $TestConfig.instance2
            Mirror     = $TestConfig.instance3
            Database   = $dbName
            Confirm    = $false
            Force      = $true
            SharedPath = $TestConfig.Temp
        }
        $results = Invoke-DbaDbMirroring @splatMirroring -WarningVariable WarnVar
        $WarnVar | Should -BeNullOrEmpty
        $results.Status | Should -Be "Success"
    }
}