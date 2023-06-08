$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Name', 'Type', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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
                $Results = Get-DbaReplPublication -SqlInstance MockServerName
                $Results.Server | Should Be "MockServerName"
            }

            It "Honors the Database parameter" {
                $Results = Get-DbaReplPublication -SqlInstance MockServerName -Database TestDB
                $Results.Database | Should Be "TestDB"
            }

            It "Honors the Type parameter" {

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

                $Results = Get-DbaReplPublication -SqlInstance MockServerName -Database TestDB -Type Snapshot
                $Results.Type | Should Be "Snapshot"
            }

            It "Stops if validate set for Type is not met" {

                { Get-DbaReplPublication -SqlInstance MockServerName -Type NotAPubType } | should Throw

            }
        }
    }
}