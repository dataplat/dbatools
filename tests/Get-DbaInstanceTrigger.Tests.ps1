param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceTrigger Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceTrigger
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

Describe "Get-DbaInstanceTrigger Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $global:instance2
        $random = Get-Random
        $trigger1 = "dbatoolsci_trigger1_$random"
        $trigger2 = "dbatoolsci_trigger2_$random"
        $sql1 = "CREATE TRIGGER [$trigger1] ON ALL SERVER FOR CREATE_DATABASE AS PRINT 'Database Created.'"
        $sql2 = "CREATE TRIGGER [$trigger2] ON ALL SERVER FOR CREATE_DATABASE AS PRINT 'Database Created.'"
        $instance.query($sql1)
        $instance.query($sql2)
    }

    AfterAll {
        $sql = "DROP TRIGGER [$trigger1] ON ALL SERVER;DROP TRIGGER [$trigger2] ON ALL SERVER"
        $instance.query($sql)
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaInstanceTrigger -SqlInstance $global:instance2
        }

        It "Should return results" {
            $results.Count | Should -Be 2
        }

        It "Should have correct properties" {
            $ExpectedProps = 'AnsiNullsStatus,AssemblyName,BodyStartIndex,ClassName,ComputerName,CreateDate,DatabaseEngineEdition,DatabaseEngineType,DateLastModified,DdlTriggerEvents,ExecutionContext,ExecutionContextLogin,ExecutionManager,ID,ImplementationType,InstanceName,IsDesignMode,IsEnabled,IsEncrypted,IsSystemObject,MethodName,Name,Parent,ParentCollection,Properties,QuotedIdentifierStatus,ServerVersion,SqlInstance,State,Text,TextBody,TextHeader,TextMode,Urn,UserData'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}
