param($ModuleName = 'dbatools')

Describe "Get-DbaReplPublication" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaReplPublication
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Code Validation" {
        BeforeAll {
            Mock -ModuleName $ModuleName -CommandName Connect-ReplicationDB -MockWith {
                [PSCustomObject]@{
                    Name              = 'TestDB'
                    TransPublications = @{
                        Name         = 'TestDB_pub'
                        Type         = 'Transactional'
                        DatabaseName = 'TestDB'
                    }
                    MergePublications = @{}
                }
            }

            Mock -ModuleName $ModuleName -CommandName Connect-DbaInstance -MockWith {
                [PSCustomObject]@{
                    Name               = "MockServerName"
                    ServiceName        = 'MSSQLSERVER'
                    DomainInstanceName = 'MockServerName'
                    ComputerName       = 'MockComputerName'
                    Databases          = @{
                        Name               = 'TestDB'
                        ID                 = 5
                        ReplicationOptions = 'Published'
                        IsAccessible       = $true
                        IsSystemObject     = $false
                    }
                    ConnectionContext  = @{
                        SqlConnectionObject = 'FakeConnectionContext'
                    }
                }
            }
        }

        It "Honors the SQLInstance parameter" {
            $Results = Get-DbaReplPublication -SqlInstance MockServerName
            $Results.SqlInstance.Name | Should -Be "MockServerName"
        }

        It "Honors the Database parameter" {
            $Results = Get-DbaReplPublication -SqlInstance MockServerName -Database TestDB
            $Results.DatabaseName | Should -Be "TestDB"
        }

        It "Honors the Type parameter" {
            Mock -ModuleName $ModuleName -CommandName Connect-ReplicationDB -MockWith {
                [PSCustomObject]@{
                    Name              = 'TestDB'
                    TransPublications = @{
                        Name = 'TestDB_pub'
                        Type = 'Snapshot'
                    }
                    MergePublications = @{}
                }
            }

            $Results = Get-DbaReplPublication -SqlInstance MockServerName -Database TestDB -Type Snapshot
            $Results.Type | Should -Be "Snapshot"
        }

        It "Stops if validate set for Type is not met" {
            { Get-DbaReplPublication -SqlInstance MockServerName -Type NotAPubType } | Should -Throw
        }
    }
}
