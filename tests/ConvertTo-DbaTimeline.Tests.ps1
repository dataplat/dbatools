#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "ConvertTo-DbaTimeline",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "ExcludeRowLabel",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $backupPath -ItemType Directory
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master -Type Full -FilePath "$backupPath\master.bak" -SqlCredential $TestConfig.SqlCred
            $backupHistory = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database master -Last -SqlCredential $TestConfig.SqlCred
            $result = $backupHistory | ConvertTo-DbaTimeline
        }

        AfterAll {
            Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output of type System.String" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [System.String]
        }

        It "Returns exactly three string parts" {
            $result.Count | Should -Be 3
        }

        It "Returns valid HTML content" {
            $result[0] | Should -Match "<html>"
            $result[2] | Should -Match "</html>"
        }
    }
}