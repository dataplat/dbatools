param($ModuleName = 'dbatools')

Describe "Get-DbaPbmCondition" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmCondition
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Condition as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Condition
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have IncludeSystemObject as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
                <ObjType>System.String</TypeClass>
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
