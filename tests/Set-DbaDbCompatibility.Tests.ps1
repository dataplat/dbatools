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
        $global:TestConfig = Get-TestConfig

        Get-DbaProcess -SqlInstance $TestConfig.instance1 -Database model | Stop-DbaProcess -Confirm:$false
        $global:sqlCn = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $global:sqlCn.Refresh()
        $global:dbNameNotMatches = "dbatoolscliCompatibilityLevelNotMatch_$(Get-Random -Minimum 600 -Maximum 1100)"
        $instanceLevel = $global:sqlCn.Databases["master"].CompatibilityLevel
        <# create a database that is one level down from instance level, any version tested against supports the prior level        #>
        $previousCompatLevel = [int]($instanceLevel.ToString().Trim("Version")) - 10
        Get-DbaProcess -SqlInstance $TestConfig.instance2 -Database model | Stop-DbaProcess -Confirm:$false
        $queryNot = "CREATE DATABASE $global:dbNameNotMatches"
        #$null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $global:dbNameNotMatches
        $global:sqlCn.Query($queryNot)
        Start-Sleep 5
        $queryAlter = "ALTER DATABASE $global:dbNameNotMatches SET COMPATIBILITY_LEVEL = $($previousCompatLevel)"
        $global:sqlCn.Query($queryAlter)

        $global:sqlCn.Refresh()
        $global:sqlCn.Databases.Refresh()
        $global:resultMatches = Set-DbaDbCompatibility -SqlInstance $global:sqlCn -Database "master" -Verbose 4>&1
        $global:verboseMsg = "*current Compatibility Level matches target level*"

        $global:sqlCn.Refresh()
        $global:sqlCn.Databases.Refresh()
        $global:resultNotMatches = Set-DbaDbCompatibility -SqlInstance $global:sqlCn -Database $global:dbNameNotMatches -Verbose 4>&1
        $global:verboseSetMsg = "*Performing the operation `"Setting*Compatibility Level*"
    }
    AfterAll {
        $sqlCn = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        Remove-DbaDatabase -SqlInstance $sqlCn -Database $global:dbNameNotMatches -Confirm:$false -ErrorAction SilentlyContinue
        $sqlCn.ConnectionContext.Disconnect()
    }
    Context "Instance Compatibility Level" {
        It "Detects database is already at the instance level" {
            $global:resultMatches[-1] | Should -BeLike $global:verboseMsg
        }
        It -Skip:$true "Should have no output" {
            ($global:resultMatches | Get-Member | Select-Object TypeName -Unique).Count | Should -BeExactly 1
        }
    }
    Context "Providing Compatibility Level" {
        It "Performs operation to update compatibility level" {
            $global:resultNotMatches[-2] | Should -BeLike $global:verboseSetMsg
        }
        It "Should output an object" {
            ($global:resultNotMatches | Get-Member | Select-Object TypeName -Unique).Count | Should -BeExactly 2
        }
    }
}
#$TestConfig.instance3