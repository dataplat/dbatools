$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $script:instance2
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
        $results = Get-DbaInstanceTrigger -SqlInstance $script:instance2

        It "Should return results" {
            $results.Count | Should Be 2
        }

        It "Should have correct properties" {
            $ExpectedProps = 'AnsiNullsStatus,AssemblyName,BodyStartIndex,ClassName,ComputerName,CreateDate,DatabaseEngineEdition,DatabaseEngineType,DateLastModified,DdlTriggerEvents,ExecutionContext,ExecutionContextLogin,ExecutionManager,ID,ImplementationType,InstanceName,IsDesignMode,IsEnabled,IsEncrypted,IsSystemObject,MethodName,Name,Parent,ParentCollection,Properties,QuotedIdentifierStatus,ServerVersion,SqlInstance,State,Text,TextBody,TextHeader,TextMode,Urn,UserData'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
    }
}