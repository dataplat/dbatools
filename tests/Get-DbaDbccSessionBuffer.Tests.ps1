param($ModuleName = 'dbatools')

Describe "Get-DbaDbccSessionBuffer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccSessionBuffer
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Operation",
            "SessionId",
            "RequestId",
            "All",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
