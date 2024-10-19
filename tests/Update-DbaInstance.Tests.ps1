$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$exeDir = "C:\Temp\dbatools_$CommandName"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { [pscustomobject]@{ Successful = $true; ExitCode = [uint32[]]3010 } } -ModuleName dbatools
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Get-DbaDiskSpace -MockWith { [pscustomobject]@{ Name = 'C:\'; Free = 1 } } -ModuleName dbatools
    }
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'Version', 'Type', 'KB', 'InstanceName', 'Path', 'Restart', 'Continue', 'Throttle', 'Authentication', 'EnableException', 'ExtractPath', 'ArgumentList', 'Download', 'NoPendingRenameCheck'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "Version",
                "InstanceName"
            )
            foreach ($param in $requiredParameters) {
                $CommandName | Should -HaveParameter $param
            }
        }
    }
    # ... rest of the code ...
}
