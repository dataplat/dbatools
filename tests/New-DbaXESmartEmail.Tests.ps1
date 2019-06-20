$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SmtpServer', 'Sender', 'To', 'Cc', 'Bcc', 'Credential', 'Subject', 'Body', 'Attachment', 'AttachmentFileName', 'PlainText', 'Event', 'Filter', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Creates a smart object" {
        It "returns the object with all of the correct properties" {
            $results = New-DbaXESmartEmail -SmtpServer smtp.ad.local -Sender me@me.com -To you@you.net -Subject Test -Body Sup -Event abc
            $results.SMTPServer | Should -Be 'smtp.ad.local'
            $results.Sender | Should -Be 'me@me.com'
            $results.To | Should -be 'you@you.net'
            $results.Subject | Should -Be 'Test'
            $results.Events | Should -Contain 'abc'
            $results.HTMLFormat | SHould -Be $false
        }
    }
}