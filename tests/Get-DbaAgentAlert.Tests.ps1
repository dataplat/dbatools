param($ModuleName = 'dbatools')

Describe "Get-DbaAgentAlert Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Importing the function if it's not automatically loaded
        . (Join-Path $PSScriptRoot '..\functions\Get-DbaAgentAlert.ps1')
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentAlert
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Alert as a parameter" {
            $CommandUnderTest | Should -HaveParameter Alert -Type String[]
        }
        It "Should have ExcludeAlert as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeAlert -Type String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Get-DbaAgentAlert Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues = @{ 'It:Skip' = $false }
        . (Join-Path $PSScriptRoot 'constants.ps1')

        $server = Connect-DbaInstance -SqlInstance $global:instance2 -Database master
        $server.Query("EXEC msdb.dbo.sp_add_alert @name=N'dbatoolsci test alert',@message_id=0,@severity=6,@enabled=1,@delay_between_responses=0,@include_event_description_in=0,@category_name=N'[Uncategorized]',@job_id=N'00000000-0000-0000-0000-000000000000'")
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2 -Database master
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'dbatoolsci test alert'")
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaAgentAlert -SqlInstance $global:instance2
        }

        It "gets the newly created alert" {
            $results.Name | Should -Contain 'dbatoolsci test alert'
        }
    }
}
