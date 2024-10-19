param($ModuleName = 'dbatools')

Describe "Get-DbaAgentAlert Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Import the function using the correct path
        . "$PSScriptRoot\..\internal\functions\Get-DbaAgentAlert.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentAlert
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Alert",
                "ExcludeAlert",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
        It "gets the newly created alert" {
            $results = Get-DbaAgentAlert -SqlInstance $global:instance2
            $results.Name | Should -Contain 'dbatoolsci test alert'
        }
    }
}
