$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'Database', 'SqlCredential', 'PublicationType', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Code Validation" {

            Mock Connect-ReplicationDB -MockWith {
                [object]@{
                    Name              = 'TestDB'
                    TransPublications = @{
                        Name = 'TestDB_pub'
                        Type = 'Transactional'
                    }
                    MergePublications = @{}
                }
            }

            Mock Connect-DbaInstance -MockWith {
                [object]@{
                    Name              = "MockServerName"
                    ComputerName      = 'MockComputerName'
                    Databases         = @{
                        Name               = 'TestDB'
                        #state
                        #status
                        ID                 = 5
                        ReplicationOptions = 'Published'
                    }
                    ConnectionContext = @{
                        SqlConnectionObject = 'FakeConnectionContext'
                    }
                }
            }

            It "Honors the SQLInstance parameter" {
                $Results = Get-DbaRepPublication -SqlInstance MockServerName
                $Results.Server | Should Be "MockServerName"
            }

            It "Honors the Database parameter" {
                $Results = Get-DbaRepPublication -SqlInstance MockServerName -Database TestDB
                $Results.Database | Should Be "TestDB"
            }

            It "Honors the PublicationType parameter" {

                Mock Connect-ReplicationDB -MockWith {
                    [object]@{
                        Name              = 'TestDB'
                        TransPublications = @{
                            Name = 'TestDB_pub'
                            Type = 'Snapshot'
                        }
                        MergePublications = @{}
                    }
                }

                $Results = Get-DbaRepPublication -SqlInstance MockServerName -Database TestDB -PublicationType Snapshot
                $Results.PublicationType | Should Be "Snapshot"
            }

            It "Stops if validate set for PublicationType is not met" {

                { Get-DbaRepPublication -SqlInstance MockServerName -PublicationType NotAPubType } | should Throw

            }
        }
    }
}