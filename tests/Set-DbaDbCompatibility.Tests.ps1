param($ModuleName = 'dbatools')

Describe "Set-DbaDbCompatibility" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbCompatibility
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have Compatibility parameter" {
            $CommandUnderTest | Should -HaveParameter Compatibility -Type CompatibilityLevel
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[]
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $sqlCn = Connect-DbaInstance -SqlInstance $global:instance2
            $sqlCn.Refresh()
            $dbNameNotMatches = "dbatoolscliCompatibilityLevelNotMatch_$(Get-Random -Minimum 600 -Maximum 1100)"
            $instanceLevel = $sqlCn.Databases['master'].CompatibilityLevel
            $previousCompatLevel = [int]($instanceLevel.ToString().Trim('Version')) - 10
            Get-DbaProcess -SqlInstance $global:instance2 -Database model | Stop-DbaProcess -Confirm:$false
            $queryNot = "CREATE DATABASE $dbNameNotMatches"
            $sqlCn.Query($queryNot)
            Start-Sleep 5
            $queryAlter = "ALTER DATABASE $dbNameNotMatches SET COMPATIBILITY_LEVEL = $($previousCompatLevel)"
            $sqlCn.Query($queryAlter)

            $sqlCn.Refresh()
            $sqlCn.Databases.Refresh()
        }

        AfterAll {
            $sqlCn = Connect-DbaInstance -SqlInstance $global:instance2
            Remove-DbaDatabase -SqlInstance $sqlCn -Database $dbNameNotMatches -Confirm:$false
            $sqlCn.ConnectionContext.Disconnect()
        }

        It "Detects database is already at the instance level" {
            $resultMatches = Set-DbaDbCompatibility -SqlInstance $sqlCn -Database 'master' -Verbose 4>&1
            $resultMatches | Should -BeLike '*current Compatibility Level matches target level*'
        }

        It "Performs operation to update compatibility level" {
            $resultNotMatches = Set-DbaDbCompatibility -SqlInstance $sqlCn -Database $dbNameNotMatches -Verbose 4>&1
            $resultNotMatches | Should -BeLike '*Performing the operation "Setting*Compatibility Level*'
        }

        It "Should output an object when updating compatibility level" {
            $resultNotMatches = Set-DbaDbCompatibility -SqlInstance $sqlCn -Database $dbNameNotMatches
            $resultNotMatches | Should -Not -BeNullOrEmpty
            $resultNotMatches | Should -BeOfType [PSObject]
        }
    }
}
