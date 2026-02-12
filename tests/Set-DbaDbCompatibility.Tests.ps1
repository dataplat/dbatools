#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbCompatibility",
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
                "Compatibility",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        Get-DbaProcess -SqlInstance $TestConfig.InstanceMulti1 -Database model | Stop-DbaProcess
        $sqlCn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $sqlCn.Refresh()
        $dbNameNotMatches = "dbatoolscliCompatibilityLevelNotMatch_$(Get-Random -Minimum 600 -Maximum 1100)"
        $instanceLevel = $sqlCn.Databases["master"].CompatibilityLevel
        <# create a database that is one level down from instance level, any version tested against supports the prior level        #>
        $previousCompatLevel = [int]($instanceLevel.ToString().Trim("Version")) - 10
        Get-DbaProcess -SqlInstance $TestConfig.InstanceMulti2 -Database model | Stop-DbaProcess
        $queryNot = "CREATE DATABASE $dbNameNotMatches"
        #$null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $dbNameNotMatches
        $sqlCn.Query($queryNot)
        Start-Sleep 5
        $queryAlter = "ALTER DATABASE $dbNameNotMatches SET COMPATIBILITY_LEVEL = $($previousCompatLevel)"
        $sqlCn.Query($queryAlter)

        $sqlCn.Refresh()
        $sqlCn.Databases.Refresh()
        $resultMatches = Set-DbaDbCompatibility -SqlInstance $sqlCn -Database "master" -Verbose 4>&1
        $verboseMsg = "*current Compatibility Level matches target level*"

        $sqlCn.Refresh()
        $sqlCn.Databases.Refresh()
        $resultNotMatches = Set-DbaDbCompatibility -SqlInstance $sqlCn -Database $dbNameNotMatches -Verbose 4>&1
        $verboseSetMsg = "*Performing the operation `"Setting*Compatibility Level*"

        # Reset compatibility level back to previous so we can capture clean output for validation
        $sqlCn.Query("ALTER DATABASE $dbNameNotMatches SET COMPATIBILITY_LEVEL = $($previousCompatLevel)")
        $sqlCn.Refresh()
        $sqlCn.Databases.Refresh()
        # Capture clean output (without verbose) for output validation
        $script:outputForValidation = Set-DbaDbCompatibility -SqlInstance $sqlCn -Database $dbNameNotMatches
    }
    AfterAll {
        $sqlCn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        Remove-DbaDatabase -SqlInstance $sqlCn -Database $dbNameNotMatches -ErrorAction SilentlyContinue
        $sqlCn.ConnectionContext.Disconnect()
    }
    Context "Instance Compatibility Level" {
        It "Detects database is already at the instance level" {
            $resultMatches[-1] | Should -BeLike $verboseMsg
        }
        It -Skip:$true "Should have no output" {
            ($resultMatches | Get-Member | Select-Object TypeName -Unique).Count | Should -BeExactly 1
        }
    }
    Context "Providing Compatibility Level" {
        It "Performs operation to update compatibility level" {
            $resultNotMatches[-2] | Should -BeLike $verboseSetMsg
        }
        It "Should output an object" {
            ($resultNotMatches | Get-Member | Select-Object TypeName -Unique).Count | Should -BeExactly 2
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                $script:outputForValidation | Should -Not -BeNullOrEmpty
                $script:outputForValidation | Should -BeOfType PSCustomObject
            }

            It "Has the expected properties" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Compatibility", "PreviousCompatibility")
                foreach ($prop in $expectedProps) {
                    $script:outputForValidation.psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
                }
            }

            It "Has correct values for key properties" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $script:outputForValidation.Database | Should -Be $dbNameNotMatches
                $script:outputForValidation.ComputerName | Should -Not -BeNullOrEmpty
                $script:outputForValidation.InstanceName | Should -Not -BeNullOrEmpty
                $script:outputForValidation.SqlInstance | Should -Not -BeNullOrEmpty
            }
        }
    }
}