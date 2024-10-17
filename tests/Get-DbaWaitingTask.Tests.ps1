param($ModuleName = 'dbatools')

Describe "Get-DbaWaitingTask" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaWaitingTask
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Spid as a parameter" {
            $CommandUnderTest | Should -HaveParameter Spid -Type Object[]
        }
        It "Should have IncludeSystemSpid as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemSpid -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $flag = "dbatools_$(Get-Random)"
            $time = '00:15:00'
            $sql = "SELECT '$flag'; WAITFOR DELAY '$time'"
            $instance = $global:instance2

            $modulePath = 'C:\Github\dbatools\dbatools.psm1'
            $job = 'YouHaveBeenFoundWaiting'

            Start-Job -Name $job -ScriptBlock {
                Import-Module $args[0]
                (Connect-DbaInstance -SqlInstance $args[1] -ClientName dbatools-waiting).Query($args[2])
            } -ArgumentList $modulePath, $instance, $sql

            Start-Sleep -Seconds 8

            $process = Get-DbaProcess -SqlInstance $instance | Where-Object Program -eq 'dbatools-waiting' | Select-Object -ExpandProperty Spid
        }

        AfterAll {
            if ($process) {
                $isProcess = Get-DbaProcess -SqlInstance $instance -Spid $process
                if ($isProcess) {
                    Stop-DbaProcess -SqlInstance $instance -Spid $process

                    $isProcess = Get-DbaProcess -SqlInstance $instance -Spid $process
                    if ($isProcess) {
                        Stop-DbaProcess -SqlInstance $instance -Spid $process -ErrorAction SilentlyContinue
                    }
                }
            }
            Get-Job -Name $job | Remove-Job -Force -ErrorAction SilentlyContinue
        }

        It "Should have correct properties" -Skip:($null -eq $process) {
            $results = Get-DbaWaitingTask -SqlInstance $instance -Spid $process
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Spid,Thread,Scheduler,WaitMs,WaitType,BlockingSpid,ResourceDesc,NodeId,Dop,DbId,InfoUrl,QueryPlan,SqlText'.Split(',')
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should have command of 'WAITFOR'" -Skip:($null -eq $process) {
            $results = Get-DbaWaitingTask -SqlInstance $instance -Spid $process
            $results.WaitType | Should -BeLike "*WAITFOR*"
        }
    }
}
