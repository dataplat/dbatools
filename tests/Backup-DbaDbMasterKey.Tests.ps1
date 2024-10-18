param($ModuleName = 'dbatools')

Describe "Backup-DbaDbMasterKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaDbMasterKey
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.String[] -Mandatory:$false
        }
        It "Should have SecurePassword as a non-mandatory parameter of type System.Security.SecureString" {
            $CommandUnderTest | Should -HaveParameter SecurePassword -Type System.Security.SecureString -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $password = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            if (-not (Get-DbaDbMasterKey -SqlInstance $server -Database tempdb)) {
                $null = New-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            }
        }

        AfterAll {
            $null = Get-DbaDbMasterKey -SqlInstance $server -Database tempdb | Remove-DbaDbMasterKey -Confirm:$false
        }

        It "backs up the db master key" {
            $results = Backup-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

            $results.Database | Should -Be 'tempdb'
            $results.Status | Should -Be "Success"
        }

        It "returns the correct Database ID" {
            $results = Backup-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $server -Database tempdb).ID
        }
    }
}
