$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LogNumber', 'Source', 'Text', 'After', 'Before', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Correctly gets error log messages" {
        $sourceFilter = "Logon"
        $textFilter = "All rights reserved"
        BeforeAll {
            $login = 'DaperDan'
            $l = Get-DbaLogin -SqlInstance $script:instance1 -Login $login
            if ($l) {
                Get-DbaProcess -SqlInstance $instance -Login $login | Stop-DbaProcess
                $l.Drop()
            }
            # (1) Cycle errorlog message: The error log has been reinitialized
            $sql = "EXEC sp_cycle_errorlog;"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query($sql)

            # (2) Need a login failure, source would be Logon
            $pwd = "p0w3rsh3llrules" | ConvertTo-SecureString -Force -AsPlainText
            $sqlCred = New-Object System.Management.Automation.PSCredential($login, $pwd)
            try {
                Connect-DbaInstance -SqlInstance $script:instance1 -SqlCredential $sqlCred -ErrorVariable $whatever
            } catch {}
        }
        It "Has the correct default properties" {
            $expectedProps = 'ComputerName,InstanceName,SqlInstance,LogDate,Source,Text'.Split(',')
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 0
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($expectedProps | Sort-Object)
        }
        It "Returns filtered results for [Source = $sourceFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -Source $sourceFilter
            $results[0].Source | Should Be $sourceFilter
        }
        It "Returns filtered result for [LogNumber = 0] and [Source = $sourceFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 0 -Source $sourceFilter
            $results[0].Source | Should Be $sourceFilter
        }
        It "Returns filtered results for [Text = $textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -Text $textFilter
            {$results[0].Text -like "*$textFilter*"} | Should Be $true
        }
        It "Returns filtered result for [LogNumber = 0] and [Text = $textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 0 -Text $textFilter
            {$results[0].Text -like "*$textFilter"} | Should Be $true
        }
        $after = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 | Select-Object -First 1
        $before = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 | Select-Object -Last 1

        $afterFilter = $after.LogDate.AddMinutes(+1)
        It "Returns filtered results for [After = $afterFilter" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -After $afterFilter
            {$results[0].LogDate -ge $afterFilter} | Should Be $true
        }
        It "Returns filtered results for [LogNumber = 1] and [After = $afterFilter" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 -After $afterFilter
            {$results[0].LogDate -ge $afterFilter} | Should Be $true
        }
        $beforeFilter = $before.LogDate.AddMinutes(-1)
        It "Returns filtered result for [Before = $beforeFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -Before $beforeFilter
            {$results[-1].LogDate -le $beforeFilter} | Should Be $true
        }
        It "Returns filtered result for [LogNumber = 1] and [Before = $beforeFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 -Before $beforeFilter
            {$results[-1].LogDate -le $beforeFilter} | Should Be $true
        }
    }
}