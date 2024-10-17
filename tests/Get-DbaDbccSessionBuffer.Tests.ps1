param($ModuleName = 'dbatools')

Describe "Get-DbaDbccSessionBuffer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccSessionBuffer
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Operation parameter" {
            $CommandUnderTest | Should -HaveParameter Operation -Type String
        }
        It "Should have SessionId parameter" {
            $CommandUnderTest | Should -HaveParameter SessionId -Type Int32[]
        }
        It "Should have RequestId parameter" {
            $CommandUnderTest | Should -HaveParameter RequestId -Type Int32
        }
        It "Should have All parameter" {
            $CommandUnderTest | Should -HaveParameter All -Type Switch
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
            $queryResult = $db.Query('SELECT top 10 object_id, @@Spid as MySpid FROM sys.objects')
        }

        Context "Validate standard output for all databases" {
            It "returns results for InputBuffer" {
                $result = Get-DbaDbccSessionBuffer -SqlInstance $global:instance1 -Operation InputBuffer -All
                $result.Count | Should -BeGreaterThan 0
                $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
                $result[0].PSObject.Properties.Name | Should -Contain 'InstanceName'
                $result[0].PSObject.Properties.Name | Should -Contain 'SqlInstance'
                $result[0].PSObject.Properties.Name | Should -Contain 'SessionId'
                $result[0].PSObject.Properties.Name | Should -Contain 'EventType'
                $result[0].PSObject.Properties.Name | Should -Contain 'Parameters'
                $result[0].PSObject.Properties.Name | Should -Contain 'EventInfo'
            }

            It "returns results for OutputBuffer" {
                $result = Get-DbaDbccSessionBuffer -SqlInstance $global:instance1 -Operation OutputBuffer -All
                $result.Count | Should -BeGreaterThan 0
                $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
                $result[0].PSObject.Properties.Name | Should -Contain 'InstanceName'
                $result[0].PSObject.Properties.Name | Should -Contain 'SqlInstance'
                $result[0].PSObject.Properties.Name | Should -Contain 'SessionId'
                $result[0].PSObject.Properties.Name | Should -Contain 'Buffer'
                $result[0].PSObject.Properties.Name | Should -Contain 'HexBuffer'
            }
        }

        Context "Validate returns results for SessionId" {
            It "returns results for InputBuffer" {
                $spid = $queryResult[0].MySpid
                $result = Get-DbaDbccSessionBuffer -SqlInstance $global:instance1 -Operation InputBuffer -SessionId $spid
                $result.SessionId | Should -Be $spid
            }

            It "returns results for OutputBuffer" {
                $spid = $queryResult[0].MySpid
                $result = Get-DbaDbccSessionBuffer -SqlInstance $global:instance1 -Operation OutputBuffer -SessionId $spid
                $result.SessionId | Should -Be $spid
            }
        }
    }
}
