param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbDbccUpdateUsage" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"

        $dbname = "dbatoolsci_getdbUsage$random"
        $db = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname
        $null = $db.Query("CREATE TABLE $tableName (id int)", $dbname)
        $null = $db.Query("CREATE CLUSTERED INDEX [PK_Id] ON $tableName ([id] ASC)", $dbname)
        $null = $db.Query("INSERT $tableName(id) SELECT object_id FROM sys.objects", $dbname)
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbDbccUpdateUsage
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
        It "Should have Table parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String
        }
        It "Should have Index parameter" {
            $CommandUnderTest | Should -HaveParameter Index -Type String
        }
        It "Should have NoInformationalMessages parameter" {
            $CommandUnderTest | Should -HaveParameter NoInformationalMessages -Type Switch
        }
        It "Should have CountRows parameter" {
            $CommandUnderTest | Should -HaveParameter CountRows -Type Switch
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Validate standard output" {
        BeforeAll {
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $script:instance1 -Confirm:$false
        }

        It "returns results" {
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should return expected properties" {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Cmd', 'Output'
            $result[0].PSObject.Properties.Name | Should -Contain $props
        }
    }

    Context "Validate returns results" {
        It "returns results for table" {
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $script:instance1 -Database $dbname -Table $tableName -Confirm:$false
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
        }

        It "returns results for index by id" {
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $script:instance1 -Database $dbname -Table $tableName -Index 1 -Confirm:$false
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
        }
    }
}
