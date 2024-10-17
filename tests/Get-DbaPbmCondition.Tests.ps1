param($ModuleName = 'dbatools')

Describe "Get-DbaPbmCondition" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmCondition
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Condition as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Condition -Type String[] -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type PSObject[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type PSObject[] -Mandatory:$false
        }
        It "Should have IncludeSystemObject as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObject -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

Describe "Get-DbaPbmCondition Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $conditionName = "dbatoolsCondition_$(Get-Random)"
        $conditionQuery = @"
            DECLARE @condition_id int
            EXEC msdb.dbo.sp_syspolicy_add_condition @name=N'$conditionName', @description=N'', @facet=N'Database', @expression=N'<Operator>
            <TypeClass>Bool</TypeClass>
            <OpType>EQ</OpType>
            <Count>2</Count>
            <Attribute>
                <TypeClass>String</TypeClass>
                <Name>Name</Name>
            </Attribute>
            <Constant>
                <TypeClass>String</TypeClass>
                <ObjType>System.String</ObjType>
                <Value>test</Value>
            </Constant>
            </Operator>', @is_name_condition=1, @obj_name=N'test', @condition_id=@condition_id OUTPUT
            SELECT @condition_id AS conditionId
"@

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $conditionId = $server.Query($conditionQuery) | Select-Object -ExpandProperty conditionId
    }

    AfterAll {
        $dropQuery = "EXEC msdb.dbo.sp_syspolicy_delete_condition @condition_id=$conditionId"
        $null = $server.Query($dropQuery)
    }

    Context "Command returns results" {
        It "Should get results" {
            $results = Get-DbaPbmCondition -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have name property '$conditionName'" {
            $results = Get-DbaPbmCondition -SqlInstance $global:instance2
            $results.Name | Should -Contain $conditionName
        }
    }

    Context "Command actually works by condition name" {
        It "Should get results" {
            $results = Get-DbaPbmCondition -SqlInstance $global:instance2 -Condition $conditionName
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have name property '$conditionName'" {
            $results = Get-DbaPbmCondition -SqlInstance $global:instance2 -Condition $conditionName
            $results.Name | Should -Be $conditionName
        }
    }
}
