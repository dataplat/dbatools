<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaWaitingTask).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Spid', 'IncludeSystemSpid'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
<#
    Integration test are custom to the command you are writing it for,
        but something similar to below should be included if applicable.

    The below examples are by no means set in stone and there are already
        a number of test that you can pull examples from in how they are done.
#>

# Get-DbaNoun
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {

    $flag = "dbatools_$(Get-Random)"
    $time = '00:15:00'
    $sql = "SELECT '$flag'; WAITFOR DELAY '$time'"
    $instance = $script:instance2

    $modulePath = 'C:\Github\dbatools\dbatools.psm1'
    $job = 'YouHaveBeenFoundWaiting'

    Start-Job -Name $job -ScriptBlock {
        Import-Module $args[0];
        (Connect-DbaInstance -SqlInstance $args[1] -ClientName dbatools-waiting).Query($args[2])
    } -ArgumentList $modulePath, $instance, $sql

    <#
        **This has to sleep as it can take a couple seconds for the job to start**
        Setting it lower will cause issues, you have to consider the Start-Job has to load the module which takes on average 3-4 seconds itself before it executes the command.

        If someone knows a cleaner method by all means adjust this test.
    #>
    Start-Sleep -Seconds 8

    $process = Get-DbaProcess -SqlInstance $instance | Where-Object Program -eq 'dbatools-waiting' | Select-Object -ExpandProperty Spid

    if ($process -ne $null) {
        Context "Command actually works" {
            $results = Get-DbaWaitingTask -SqlInstance $instance -Spid $process
            It "Should have correct properties" {
                $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Spid,Thread,Scheduler,WaitMs,WaitType,BlockingSpid,ResourceDesc,NodeId,Dop,DbId,InfoUrl,QueryPlan,SqlText'.Split(',')
                ($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            }
            It "Should have command of 'WAITFOR'" {
                $results.WaitType | Should BeLike "*WAITFOR*"
            }
        }

        $isProcess = Get-DbaProcess -SqlInstance $instance -Spid $process
        if ($isProcess) {
            Stop-DbaProcess -SqlInstance $instance -Spid $process

            # I've had a few cases where first run didn't actually kill the process
            $isProcess = Get-DbaProcess -SqlInstance $instance -Spid $process
            if ($isProcess) {
                Stop-DbaProcess -SqlInstance $instance -Spid $process -ErrorAction SilentlyContinue
            }
        }
        Get-Job -Name $job | Remove-Job -Force -ErrorAction SilentlyContinue
    }
}