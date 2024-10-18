param($ModuleName = 'dbatools')

Describe "Write-DbaDbTableData" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $global:instance1
        $random = Get-Random
        $db = "dbatoolsci_writedbadaatable$random"
        $server.Query("CREATE DATABASE $db")
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Write-DbaDbTableData
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Connection.ManagementConnectionType
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Microsoft.SqlServer.Management.Smo.Database
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object
        }
        It "Should have Table parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type System.String
        }
        It "Should have Schema parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type System.String
        }
        It "Should have BatchSize parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSize -Type System.Int32
        }
        It "Should have NotifyAfter parameter" {
            $CommandUnderTest | Should -HaveParameter NotifyAfter -Type System.Int32
        }
        It "Should have AutoCreateTable parameter" {
            $CommandUnderTest | Should -HaveParameter AutoCreateTable -Type System.Management.Automation.SwitchParameter
        }
        It "Should have NoTableLock parameter" {
            $CommandUnderTest | Should -HaveParameter NoTableLock -Type System.Management.Automation.SwitchParameter
        }
        It "Should have CheckConstraints parameter" {
            $CommandUnderTest | Should -HaveParameter CheckConstraints -Type System.Management.Automation.SwitchParameter
        }
        It "Should have FireTriggers parameter" {
            $CommandUnderTest | Should -HaveParameter FireTriggers -Type System.Management.Automation.SwitchParameter
        }
        It "Should have KeepIdentity parameter" {
            $CommandUnderTest | Should -HaveParameter KeepIdentity -Type System.Management.Automation.SwitchParameter
        }
        It "Should have KeepNulls parameter" {
            $CommandUnderTest | Should -HaveParameter KeepNulls -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Truncate parameter" {
            $CommandUnderTest | Should -HaveParameter Truncate -Type System.Management.Automation.SwitchParameter
        }
        It "Should have BulkCopyTimeOut parameter" {
            $CommandUnderTest | Should -HaveParameter BulkCopyTimeOut -Type System.Int32
        }
        It "Should have ColumnMap parameter" {
            $CommandUnderTest | Should -HaveParameter ColumnMap -Type System.Collections.Hashtable
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
        It "Should have UseDynamicStringLength parameter" {
            $CommandUnderTest | Should -HaveParameter UseDynamicStringLength -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        It "defaults to dbo if no schema is specified" {
            $results = Get-ChildItem | ConvertTo-DbaDataTable
            $results | Write-DbaDbTableData -SqlInstance $global:instance1 -Database $db -Table 'childitem' -AutoCreateTable

            ($server.Databases[$db].Tables | Where-Object { $_.Schema -eq 'dbo' -and $_.Name -eq 'childitem' }).Count | Should -Be 1
        }
    }
}
